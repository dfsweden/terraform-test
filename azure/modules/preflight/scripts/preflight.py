#!/usr/bin/env python3
"""Pre-flight validation for the Hammerspace Azure Terraform deployment.

Invoked as an `external` data source: reads a JSON query on stdin, prints a
flat JSON object on stdout. Never exits non-zero for a *failed check* -
errors are returned in the payload so the Terraform postcondition can
present them.

Checks (hard errors unless noted):
  - the Azure CLI is installed and logged in (az account show)
  - every requested VM size exists in the target location
  - sizes with a Premium_LRS disk selected support premium storage
  - the image resource exists, when an image_id is used
  - ha-multi-az: the location has availability zones, every requested zone
    offers the VM size (and the PremiumV2/Ultra disk SKU when in use) and is
    not restricted for this subscription
  - standalone: PremiumV2/Ultra metadata disks are not requested in a region
    that HAS zones, where Azure allows them only on a zonal VM
  - dsx mode only: the existing Anvil answers :8443 with the supplied
    credentials; when the image carries an hs_version tag, its Major.Minor
    must match the cluster's ANVIL node(s) (WARNING when the tag is absent)
"""

import base64
import hashlib
import json
import os
import ssl
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

errors = []
warnings = []

# Regional VM-SKU catalogs barely change - cache them so repeat plans skip
# the (few-second) fetch entirely.
SKU_CACHE_TTL_S = 24 * 3600


def az(q, args):
    """Run an Azure CLI command, return parsed JSON output. Raises on failure."""
    cmd = ["az"] + args
    if q.get("subscription"):
        cmd += ["--subscription", q["subscription"]]
    cmd += ["--output", "json"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or "az cli call failed")
    return json.loads(r.stdout) if r.stdout.strip() else None


def http_get(url, user, password, timeout):
    """GET with basic auth, TLS verification off. Returns (status, body)."""
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url)
    token = base64.b64encode(f"{user}:{password}".encode()).decode()
    req.add_header("Authorization", f"Basic {token}")
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return resp.status, resp.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, ""
    except Exception:
        return 0, ""


def major_minor(raw):
    """'5.1.24-123' -> '5.1'. Empty / 'None' -> ''."""
    raw = (raw or "").strip()
    if raw in ("", "None"):
        return ""
    return ".".join(raw.split("-")[0].split(".")[:2])


def check_login(q):
    try:
        acct = az(q, ["account", "show"])
        return f"{acct.get('user', {}).get('name', '?')} (subscription {acct.get('name', '?')})"
    except Exception:
        errors.append("The Azure CLI is not logged in (az account show failed) - run 'az login' "
                      "(and 'az account set --subscription ...' if needed).")
        return ""


SKU_CACHE_VERSION = 2  # v2: keeps 'disks' next to 'virtualMachines' (the zone checks need both)


def fetch_region_skus(q):
    """The region's SKU catalog as {'virtualMachines': {name: sku}, 'disks': {name: sku}}, cached on disk.

    Calls the Resource SKUs REST API directly with its server-side location
    filter (a few seconds). `az vm list-skus --size` is NOT used - its size
    filter is client-side, so every call downloads and parses the entire
    multi-region catalog (~100s per call).
    """
    tok_args = ["account", "get-access-token"]
    tok = az(q, tok_args)
    sub = q.get("subscription") or tok.get("subscription")
    location = q["location"]

    cache_key = hashlib.sha256(f"{sub}|{location}".encode()).hexdigest()[:16]
    cache_file = os.path.join(tempfile.gettempdir(), f"hs-preflight-skus-v{SKU_CACHE_VERSION}-{cache_key}.json")
    try:
        if time.time() - os.path.getmtime(cache_file) < SKU_CACHE_TTL_S:
            with open(cache_file) as f:
                return json.load(f)
    except OSError:
        pass

    url = (f"https://management.azure.com/subscriptions/{sub}/providers/Microsoft.Compute/skus"
           f"?api-version=2021-07-01&$filter=location%20eq%20%27{location}%27")
    skus = {"virtualMachines": {}, "disks": {}}
    while url:
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok['accessToken']}"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            payload = json.load(resp)
        for s in payload.get("value", []):
            rt = s.get("resourceType")
            if rt in skus:
                # disks: the API lists one entry per tier (P4, P6, ...) under the
                # same name; they share zones and restrictions, so last-wins is fine.
                skus[rt][s["name"]] = s
        url = payload.get("nextLink")

    try:
        with open(cache_file, "w") as f:
            json.dump(skus, f)
    except OSError:
        pass
    return skus


def fetch_region_vm_skus(q):
    return fetch_region_skus(q)["virtualMachines"]


def _offered_zones(sku):
    """Zones a SKU is OFFERED in (locationInfo[0].zones); empty in a non-zonal region."""
    return set((sku.get("locationInfo") or [{}])[0].get("zones") or [])


def _restrictions(sku):
    """(whole_location: bool, zones: set) - a 'Location' restriction covers the
    region, a 'Zone' one lists the zones THIS subscription may not deploy in."""
    loc, zones = False, set()
    for r in sku.get("restrictions", []) or []:
        if not r:
            continue
        if r.get("type") == "Zone":
            zones |= set((r.get("restrictionInfo") or {}).get("zones") or [])
        else:
            loc = True
    return loc, zones


def check_vm_sizes(q):
    location = q["location"]
    sizes = json.loads(q["vm_sizes"])
    premium = set(json.loads(q["premium_sizes"]))
    try:
        skus = fetch_region_vm_skus(q)
        for size in dict.fromkeys(sizes):  # de-dup, keep order
            match = skus.get(size)
            if match is None:
                errors.append(f"VM size {size} is not available in location {location}.")
                continue
            # A Zone restriction on SOME zones is not a regional restriction: a
            # non-zonal VM (ha / standalone) is placed around it. Only a
            # Location restriction, or zones restricted everywhere the size is
            # offered, makes the size unusable here. Requested zones are
            # checked against zone restrictions in check_zones.
            loc_restricted, zone_restricted = _restrictions(match)
            offered = _offered_zones(match)
            if loc_restricted or (offered and zone_restricted >= offered):
                reasons = ", ".join(r.get("reasonCode", "?") for r in match.get("restrictions", []) if r)
                errors.append(f"VM size {size} is restricted for this subscription in {location} ({reasons}).")
            if size in premium:
                caps = {c.get("name"): c.get("value") for c in match.get("capabilities", [])}
                if str(caps.get("PremiumIO", "")).lower() != "true":
                    errors.append(f"VM size {size} does not support premium storage, but a premium disk type was selected for it.")
            # Hammerspace VHDs are Hyper-V Generation 1; Gen2-only sizes
            # (Mv2, ARM64, confidential-computing series, ...) cannot boot
            # them and fail at VM creation - catch it here instead.
            image_gen = (q.get("image_generation") or "").strip()
            if image_gen:
                caps = {c.get("name"): c.get("value") for c in match.get("capabilities", [])}
                hv_gens = [g.strip() for g in str(caps.get("HyperVGenerations", "")).split(",") if g.strip()]
                if hv_gens and image_gen not in hv_gens:
                    errors.append(
                        f"VM size {size} only boots Hyper-V generation {'/'.join(hv_gens)} images, but the "
                        f"Hammerspace image is Generation {image_gen.lstrip('V')} ({image_gen}) - pick a size "
                        f"that supports {image_gen} (most D/E/F-series sizes do).")

        # Product minimums: Anvil 16 vCPU / 32 GiB, DSX 8 vCPU / 16 GiB.
        for role, size_key, vcpu_key, mem_key, dflt_vcpus, dflt_mem in (
                ("Anvil", "anvil_size", "anvil_min_vcpus", "anvil_min_mem_gb", 16, 32),
                ("DSX", "dsx_size", "dsx_min_vcpus", "dsx_min_mem_gb", 8, 16)):
            size = (q.get(size_key) or "").strip()
            if size and size in skus:
                caps = {c.get("name"): c.get("value") for c in skus[size].get("capabilities", [])}
                vcpus = float(caps.get("vCPUs", 0) or 0)
                mem = float(caps.get("MemoryGB", 0) or 0)
                min_vcpus = float(q.get(vcpu_key) or dflt_vcpus)
                min_mem = float(q.get(mem_key) or dflt_mem)
                if vcpus < min_vcpus or mem < min_mem:
                    errors.append(
                        f"{role} size {size} is below the product minimum: has {vcpus:g} vCPU / {mem:g} GiB, "
                        f"needs at least {min_vcpus:g} vCPU / {min_mem:g} GiB.")
    except Exception as e:
        warnings.append(f"NOT CHECKED: could not verify VM size availability ({e}) - confirm the sizes exist in {location} manually.")


def check_vcpu_quota(q):
    """Per-family and regional vCPU quota vs what this deployment will consume.

    Pre-flight used to verify a VM size is OFFERED in the region but never that
    the subscription has ROOM for it, so a quota shortfall - the single most
    common reason a "newer is better" size substitution fails - surfaced only
    at apply, as an OperationNotAllowed on the second or third VM. Quota is
    granted per family (standardDSv5Family, ...) and separately as a regional
    total ('cores'), and both are checked here.

    Sizes are mapped to families through the same SKU catalog check_vm_sizes
    already fetched (cached on disk), and the numbers come from
    `az vm list-usage`, which is what an operator would run by hand.
    """
    location = q["location"]
    try:
        skus = fetch_region_vm_skus(q)
        needed = {}      # family -> vCPUs this apply adds
        total = 0.0
        for size_key, count_key in (("anvil_size", "anvil_count"), ("dsx_size", "dsx_count")):
            size = (q.get(size_key) or "").strip()
            count = int(float(q.get(count_key) or 0))
            if not size or count <= 0 or size not in skus:
                continue
            sku = skus[size]
            caps = {c.get("name"): c.get("value") for c in sku.get("capabilities", [])}
            vcpus = float(caps.get("vCPUs", 0) or 0) * count
            family = sku.get("family") or ""
            if family:
                needed[family] = needed.get(family, 0.0) + vcpus
            total += vcpus
        if not needed:
            return
        usage = {u.get("name", {}).get("value"): u for u in (az(q, ["vm", "list-usage", "-l", location]) or [])}
        for family, add in needed.items():
            u = usage.get(family)
            if u is None:
                warnings.append(f"NOT CHECKED: no quota entry named {family} in {location} - confirm capacity manually.")
                continue
            cur, lim = float(u.get("currentValue", 0)), float(u.get("limit", 0))
            if cur + add > lim:
                errors.append(
                    f"vCPU quota for {family} in {location} cannot fit this deployment: "
                    f"{cur:g} in use + {add:g} needed = {cur + add:g}, limit {lim:g} (only {lim - cur:g} free). "
                    f"Request an increase for that family, or choose sizes from a family with room - "
                    f"quota is per family, so mixing e.g. Dsv5 Anvils with Dsv3 DSX is a valid workaround.")
        u = usage.get("cores")
        if u is not None:
            cur, lim = float(u.get("currentValue", 0)), float(u.get("limit", 0))
            if cur + total > lim:
                errors.append(
                    f"Total regional vCPU quota in {location} cannot fit this deployment: "
                    f"{cur:g} in use + {total:g} needed = {cur + total:g}, limit {lim:g}.")
    except Exception as e:
        warnings.append(f"NOT CHECKED: could not verify vCPU quota ({e}) - run 'az vm list-usage -l {location}' manually.")


def check_zones(q):
    """ha-multi-az: every requested zone must exist in the region, offer the VM
    size, not be restricted for this subscription, and (PremiumV2/Ultra) offer
    the disk SKU. Skipped when no zones were requested.

    Zone facts come from the same Resource SKUs catalog check_vm_sizes uses:
    locationInfo[0].zones is where a SKU is OFFERED, restrictions[] of type Zone
    where THIS subscription may not deploy it - both are needed. The region
    "has zones" iff any VM SKU lists one (westus lists none), which is what
    `az vm list-skus -l <loc> --zone` shows an operator, and needs no second
    CLI call.
    """
    roles = (("Anvil", "anvil_size", "anvil_zones", "anvil_meta_disk_type"),
             ("DSX", "dsx_size", "dsx_zones", "dsx_data_disk_type"))
    wanted = {}
    for role, size_key, zones_key, disk_key in roles:
        try:
            zones = json.loads(q.get(zones_key) or "[]")
        except ValueError:
            zones = []
        wanted[role] = ((q.get(size_key) or "").strip(), zones, (q.get(disk_key) or "").strip(), zones_key)
    requested = sorted({z for _, zones, _, _ in wanted.values() for z in zones})
    if not requested:
        return
    location = q["location"]
    try:
        catalog = fetch_region_skus(q)
        vm_skus, disk_skus = catalog["virtualMachines"], catalog["disks"]
        region_zones = sorted({z for sku in vm_skus.values() for z in _offered_zones(sku)})
        if not region_zones:
            errors.append(
                f"Location {location} has no availability zones - ha-multi-az needs a zonal region "
                f"(westus2, westus3, eastus, ...). Use deployment_mode = \"ha\" here, which places the "
                f"Anvils in an availability set instead.")
            return
        missing = [z for z in requested if z not in region_zones]
        if missing:
            errors.append(f"Zone(s) {', '.join(missing)} do not exist in {location} "
                          f"(it has zones {', '.join(region_zones)}).")
            return
        for role, (size, zones, disk_type, var_name) in wanted.items():
            if not size or not zones or size not in vm_skus:  # a missing size is check_vm_sizes' error
                continue
            sku = vm_skus[size]
            offered = _offered_zones(sku)
            _, restricted = _restrictions(sku)
            bad = [z for z in zones if z not in offered]
            if bad:
                errors.append(
                    f"{role} size {size} is not offered in zone(s) {', '.join(bad)} of {location} "
                    f"(offered in {', '.join(sorted(offered)) or 'none'}) - change {var_name}, or pick a "
                    f"size offered in every zone listed.")
            bad = [z for z in zones if z in restricted]
            if bad:
                errors.append(
                    f"{role} size {size} is restricted for this subscription in zone(s) {', '.join(bad)} "
                    f"of {location} - change {var_name}, or have the restriction lifted.")
            if disk_type in ("PremiumV2_LRS", "UltraSSD_LRS"):
                dsku = disk_skus.get(disk_type)
                if dsku is None:
                    errors.append(f"{disk_type} disks are not offered in {location} - choose Premium_LRS for the {role} disks.")
                    continue
                offered = _offered_zones(dsku)
                _, restricted = _restrictions(dsku)
                bad = [z for z in zones if z not in offered or z in restricted]
                if bad:
                    errors.append(
                        f"{disk_type} disks are not available in zone(s) {', '.join(bad)} of {location} "
                        f"(available in {', '.join(sorted(offered - restricted)) or 'none'}), but {var_name} "
                        f"puts {role} nodes there - move them, or choose Premium_LRS.")
    except Exception as e:
        warnings.append(f"NOT CHECKED: could not verify availability-zone placement ({e}) - "
                        f"confirm with 'az vm list-skus -l {location} --zone' manually.")


def check_perf_disk_placement(q):
    """PremiumV2/Ultra disks require a VM in an availability ZONE - but only in
    a region that HAS zones. A standalone Anvil is deliberately in neither a
    zone nor an availability set, so in a zonal region the attachment is
    rejected at apply:

      InvalidParameter: Managed disks with 'PremiumV2_LRS' storage account type
      can be used only with Virtual Machines in an Availability Zone.

    Measured 2026-09-26 in westus2 on deployment_mode=standalone with the
    default anvil_metadata_disk_type. The same configuration works in westus,
    which has no zones - hence the region-dependent check rather than a blanket
    rule, and hence why this was invisible until the tree was exercised in a
    zonal region.

    ha and dsx are unaffected: their VMs sit in availability sets, and the root
    already falls PremiumV2/Ultra back to Premium_LRS for those (with a plan
    warning). ha-multi-az is unaffected because its VMs are zonal, which is
    exactly what these disks want.
    """
    if (q.get("mode") or "") != "standalone":
        return
    disk = (q.get("anvil_meta_disk_type") or "").strip()
    if disk not in ("PremiumV2_LRS", "UltraSSD_LRS"):
        return
    location = q["location"]
    try:
        vm_skus = fetch_region_skus(q)["virtualMachines"]
        region_zones = sorted({z for sku in vm_skus.values() for z in _offered_zones(sku)})
        if not region_zones:
            return  # non-zonal region: a non-zonal VM may use these disks
        errors.append(
            f"anvil_metadata_disk_type {disk} cannot be attached to a standalone Anvil in "
            f"{location}: the region has availability zones ({', '.join(region_zones)}), and Azure "
            f"only allows {disk} on a VM placed IN a zone - a standalone Anvil is in neither a zone "
            f"nor an availability set. Either set anvil_metadata_disk_type = \"Premium_LRS\" (size "
            f"for IOPS: 1024 GB = 5000), or use deployment_mode = \"ha-multi-az\", whose Anvils are "
            f"zonal and keep {disk}. The same configuration is valid in a region without zones.")
    except Exception as e:
        warnings.append(f"NOT CHECKED: could not verify performance-disk placement ({e}) - "
                        f"PremiumV2/Ultra need a zonal VM in a zonal region.")


def check_image(q):
    """Image existence (hard when image_id set). Returns its hs_version tag ('' if absent).

    Uses the typed CLI commands - the generic `az resource show` picks an API
    version Microsoft.Compute/images does not support.
    """
    image_id = (q.get("image_id") or "").strip()
    if not image_id:
        return ""
    lowered = image_id.lower()
    if "/providers/microsoft.compute/images/" in lowered:
        cmd = ["image", "show", "--ids", image_id]
    elif "/galleries/" in lowered and "/versions/" in lowered:
        cmd = ["sig", "image-version", "show", "--ids", image_id]
    else:
        cmd = ["resource", "show", "--ids", image_id]
    try:
        res = az(q, cmd)
        return (res.get("tags") or {}).get("hs_version", "") or ""
    except Exception as e:
        errors.append(f"Image {image_id} could not be found or read: {e}")
        return ""


def check_sas_image(q):
    """image_sas_url: the blob SAS URL must be https, readable, and a page
    blob (VHDs are page blobs) - hard stop before anything is created. The
    later copy runs server-side inside Azure Storage, so reachability from
    here is a good proxy but IP-restricted SAS tokens are called out."""
    url = (q.get("image_sas_url") or "").strip()
    if not url:
        return
    if not url.lower().startswith("https://"):
        errors.append("image_sas_url must be an https:// blob SAS URL.")
        return
    path = url.split("?", 1)[0]
    if "?" not in url or "sig=" not in url.lower():
        warnings.append("image_sas_url does not look like a SAS URL (no sig= token) - "
                        "the copy will fail unless the blob is public.")
    if not path.lower().endswith(".vhd"):
        warnings.append(f"image_sas_url does not point at a .vhd blob ({path.rsplit('/', 1)[-1]}) - "
                        "Azure images require a fixed-format VHD.")
    try:
        req = urllib.request.Request(url, method="HEAD")
        with urllib.request.urlopen(req, timeout=30) as resp:
            blob_type = resp.headers.get("x-ms-blob-type", "")
            size = int(resp.headers.get("Content-Length", 0) or 0)
        if blob_type and blob_type != "PageBlob":
            errors.append(f"image_sas_url blob is a {blob_type}, not a PageBlob - VHDs must be "
                          "uploaded as page blobs for Azure images to boot from them.")
        if size and size % 512 != 0:
            warnings.append("image_sas_url blob size is not 512-byte aligned - not a fixed VHD?")
    except urllib.error.HTTPError as e:
        errors.append(f"image_sas_url is not readable (HTTP {e.code}) - check the SAS token's "
                      "Read permission and expiry. Note: an IP-restricted SAS also breaks the "
                      "server-side copy (Azure Storage fetches the source, not this machine).")
    except Exception as e:
        errors.append(f"image_sas_url is not reachable ({e}).")


def check_anvil_probe(q):
    """dsx mode: existing Anvil reachable + credentials valid (hard stop)."""
    ip, user, password = q["anvil_ip"], q["hsuser"] or "admin", q["anvil_password"]
    status, _ = http_get(f"https://{ip}:8443/mgmt/v1.2/rest/cntl", user, password, 15)
    if status == 200:
        return True
    if status == 401:
        errors.append(f"Existing Anvil at {ip}:8443 - credentials rejected (HTTP 401): check hsuser/admin_password")
    elif status == 0:
        errors.append(f"Existing Anvil at {ip}:8443 - unreachable: check anvil_ip, that the Anvil is up, and 8443 is reachable from here")
    else:
        errors.append(f"Existing Anvil at {ip}:8443 - unexpected HTTP {status}: check the Anvil and credentials")
    return False


def check_version_compat(q, image_version):
    """Image hs_version Major.Minor vs the cluster's ANVIL node(s).

    Azure images are not guaranteed to carry the hs_version tag the AWS AMIs
    have, so a missing tag degrades to a warning instead of a hard stop.
    """
    image_mm = major_minor(image_version)
    if not image_mm:
        warnings.append("The image has no hs_version tag - image/cluster Major.Minor compatibility "
                        "could not be verified automatically. Confirm the image matches the running "
                        "cluster's version before joining DSX nodes.")
        return
    try:
        status, body = http_get(f"https://{q['anvil_ip']}:8443/mgmt/v1.2/rest/nodes",
                                q["hsuser"] or "admin", q["anvil_password"], 30)
        if status != 200:
            raise RuntimeError(f"GET /nodes returned HTTP {status}")
        nodes = json.loads(body)
        anvil_versions = [
            n.get("swVersion", {}).get("version", "")
            for n in nodes
            if isinstance(n, dict) and n.get("productNodeType") == "ANVIL"
            and isinstance(n.get("swVersion"), dict) and n["swVersion"].get("version")
        ]
        anvil_raw = anvil_versions[0] if anvil_versions else ""
        anvil_mm = major_minor(anvil_raw)
        if not anvil_mm:
            errors.append(f"Could not read swVersion.version from any ANVIL node at {q['anvil_ip']} - cannot verify version compatibility.")
        elif image_mm != anvil_mm:
            errors.append(
                f"Version mismatch: DSX image is {image_version} (Major.Minor {image_mm}) but the cluster ANVIL is "
                f"{anvil_raw} (Major.Minor {anvil_mm}). A DSX can only join a cluster with the same Major.Minor.")
    except Exception as e:
        errors.append(
            f"Could not verify DSX/cluster version compatibility ({e}). "
            "Fix the cause, or set skip_preflight = true to bypass all pre-flight checks.")


def main():
    q = json.load(sys.stdin)

    account = check_login(q)
    image_version = ""
    if account:
        check_vm_sizes(q)
        check_zones(q)
        check_perf_disk_placement(q)
        check_vcpu_quota(q)
        image_version = check_image(q)
    check_sas_image(q)

    if q.get("check_anvil") == "true":
        if check_anvil_probe(q):
            check_version_compat(q, image_version)

    json.dump({
        "ok": "false" if errors else "true",
        "errors": "\n".join(f"  - {e}" for e in errors),
        "warnings": "\n".join(f"  - {w}" for w in warnings),
        "account": account,
    }, sys.stdout)


if __name__ == "__main__":
    main()
