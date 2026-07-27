#!/usr/bin/env python3
"""Pre-flight validation for the Hammerspace Terraform deployment.

Terraform port of the Ansible preflight.yml task files. Invoked as an
`external` data source: reads a JSON query on stdin, prints a flat JSON
object on stdout. Never exits non-zero for a *failed check* - errors are
returned in the payload so the Terraform postcondition can present them;
a non-zero exit is reserved for protocol-level breakage.

Checks (hard errors unless noted):
  - deploying identity can perform the required IAM actions
    (via iam:SimulatePrincipalPolicy; degrades to a WARNING when the
    simulate call itself is denied)
  - IAM instance profile exists (when set) and its role allows the
    runtime actions (simulate; degrades to a WARNING as above)
  - VPC has DNS support + DNS hostnames enabled
  - EC2 API reachable from every deployment subnet: a valid
    com.amazonaws.<region>.ec2 interface endpoint (available, private-DNS
    enabled, covering the subnet(s)) OR a 0.0.0.0/0 route to a NAT/IGW
  - STS interface endpoint present (WARNING only)
  - dsx mode only: the existing Anvil answers :8443 with the supplied
    credentials, and the DSX AMI's hs_version tag shares the cluster's
    Major.Minor (read from its ANVIL node(s), never a DSX)
"""

import base64
import json
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

errors = []
warnings = []


def aws(q, args):
    """Run an AWS CLI command, return parsed JSON output. Raises on failure."""
    cmd = ["aws", "--region", q["region"]]
    if q.get("profile"):
        cmd += ["--profile", q["profile"]]
    cmd += args + ["--output", "json"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip() or "aws cli call failed")
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


def check_anvil_probe(q):
    """dsx mode: existing Anvil reachable + credentials valid (hard stop)."""
    ip, user, password = q["anvil_ip"], q["hsuser"] or "admin", q["anvil_password"]
    status, _ = http_get(f"https://{ip}:8443/mgmt/v1.2/rest/cntl", user, password, 15)
    if status == 200:
        return True
    if status == 401:
        errors.append(f"Existing Anvil at {ip}:8443 - credentials rejected (HTTP 401): check hsuser/anvil_password")
    elif status == 0:
        errors.append(f"Existing Anvil at {ip}:8443 - unreachable: check anvil_ip, that the Anvil is up, and 8443 is reachable from here")
    else:
        errors.append(f"Existing Anvil at {ip}:8443 - unexpected HTTP {status}: check the Anvil and credentials")
    return False


def check_version_compat(q):
    """dsx mode: DSX AMI hs_version Major.Minor must match the cluster's ANVIL node(s)."""
    try:
        images = aws(q, ["ec2", "describe-images", "--image-ids", q["hs_ami"],
                         "--query", "Images[0].Tags[?Key=='hs_version']|[0].Value"])
        ami_raw = images if isinstance(images, str) else ""
        ami_mm = major_minor(ami_raw)

        status, body = http_get(f"https://{q['anvil_ip']}:8443/mgmt/v1.2/rest/nodes",
                                q["hsuser"] or "admin", q["anvil_password"], 30)
        if status != 200:
            raise RuntimeError(f"GET /nodes returned HTTP {status}")
        nodes = json.loads(body)
        # ANVIL nodes only - the DSX being added must never be the reference.
        anvil_versions = [
            n.get("swVersion", {}).get("version", "")
            for n in nodes
            if isinstance(n, dict) and n.get("productNodeType") == "ANVIL"
            and isinstance(n.get("swVersion"), dict) and n["swVersion"].get("version")
        ]
        anvil_raw = anvil_versions[0] if anvil_versions else ""
        anvil_mm = major_minor(anvil_raw)

        if not ami_mm:
            errors.append(f"DSX AMI {q['hs_ami']} has no hs_version tag - cannot verify Major.Minor compatibility with the cluster.")
        if not anvil_mm:
            errors.append(f"Could not read swVersion.version from any ANVIL node at {q['anvil_ip']} - cannot verify version compatibility.")
        if ami_mm and anvil_mm and ami_mm != anvil_mm:
            errors.append(
                f"Version mismatch: DSX AMI is {ami_raw} (Major.Minor {ami_mm}) but the cluster ANVIL is "
                f"{anvil_raw} (Major.Minor {anvil_mm}). A DSX can only join a cluster with the same Major.Minor.")
    except Exception as e:
        errors.append(
            f"Could not verify DSX/cluster version compatibility ({e}). "
            "Fix the cause, or set skip_preflight = true to bypass all pre-flight checks.")


def deployer_principal_arn(q):
    """Caller identity, converted to a simulatable principal ARN.

    An assumed-role session ARN (arn:aws:sts::ACCT:assumed-role/ROLE/SESSION)
    is converted back to its underlying role ARN.
    """
    ident = aws(q, ["sts", "get-caller-identity"])
    arn, account = ident["Arn"], ident["Account"]
    if "assumed-role/" in arn:
        role = arn.split("assumed-role/")[1].split("/")[0]
        return arn, f"arn:aws:iam::{account}:role/{role}"
    return arn, arn


def simulate(q, principal_arn, actions, who):
    """simulate-principal-policy; missing actions -> errors, denied simulate -> warning."""
    if not actions:
        return
    try:
        sim = aws(q, ["iam", "simulate-principal-policy",
                      "--policy-source-arn", principal_arn,
                      "--action-names"] + actions)
        for res in sim.get("EvaluationResults", []):
            if res.get("EvalDecision") != "allowed":
                errors.append(f"{who} {principal_arn} is missing IAM action: {res.get('EvalActionName')}")
    except Exception:
        warnings.append(
            f"Could not run iam:SimulatePrincipalPolicy on {principal_arn} - grant that action to enable "
            f"automatic checks. Manually confirm it allows: {', '.join(actions)}")


def check_instance_profile(q):
    """Instance profile existence (hard) + role permissions (simulate)."""
    name = (q.get("instance_profile") or "").strip()
    if not name:
        return
    profile_name = name.split("instance-profile/")[-1]
    try:
        prof = aws(q, ["iam", "get-instance-profile", "--instance-profile-name", profile_name])
        role_arn = prof["InstanceProfile"]["Roles"][0]["Arn"]
    except Exception as e:
        errors.append(f'IAM instance profile "{name}" could not be found or read: {e}')
        return
    actions = json.loads(q.get("instance_profile_actions") or "[]")
    simulate(q, role_arn, actions, "Instance profile role")


def check_vpc_endpoints(q):
    """VPC DNS attributes + EC2 API reachability from the deployment subnet(s) + STS (warn)."""
    vpc, region = q["vpc"], q["region"]
    subnets = json.loads(q["subnet_ids"])
    try:
        for attr, key in (("enableDnsSupport", "EnableDnsSupport"), ("enableDnsHostnames", "EnableDnsHostnames")):
            out = aws(q, ["ec2", "describe-vpc-attribute", "--vpc-id", vpc, "--attribute", attr])
            if not out[key]["Value"]:
                errors.append(f"VPC {vpc} must have {attr} enabled for interface-endpoint private DNS to resolve")

        # EC2 endpoint (BLOCKING): one valid interface endpoint covering ALL
        # deployment subnets, OR a 0.0.0.0/0 route to a NAT/IGW on every subnet.
        eps = aws(q, ["ec2", "describe-vpc-endpoints", "--filters",
                      f"Name=vpc-id,Values={vpc}",
                      f"Name=service-name,Values=com.amazonaws.{region}.ec2"])
        endpoint_ok = any(
            ep.get("State") == "available"
            and ep.get("PrivateDnsEnabled")
            and all(s in ep.get("SubnetIds", []) for s in subnets)
            for ep in eps.get("VpcEndpoints", [])
        )

        nat_ok = True
        for subnet in subnets:
            rtbs = aws(q, ["ec2", "describe-route-tables", "--filters",
                           f"Name=association.subnet-id,Values={subnet}"])
            routes = [r for t in rtbs.get("RouteTables", []) for r in t.get("Routes", [])]
            if not routes:
                # No explicit association -> the subnet uses the VPC main route table.
                rtbs = aws(q, ["ec2", "describe-route-tables", "--filters",
                               f"Name=vpc-id,Values={vpc}", "Name=association.main,Values=true"])
                routes = [r for t in rtbs.get("RouteTables", []) for r in t.get("Routes", [])]
            subnet_ok = any(
                r.get("DestinationCidrBlock") == "0.0.0.0/0"
                and (r.get("NatGatewayId") or str(r.get("GatewayId", "")).startswith("igw-"))
                for r in routes
            )
            nat_ok = nat_ok and subnet_ok

        if not (endpoint_ok or nat_ok):
            errors.append(
                f"EC2 API unreachable from subnet(s) {', '.join(subnets)}: no valid com.amazonaws.{region}.ec2 "
                "interface endpoint (must be available, private-DNS enabled, and cover the subnet(s)) and no "
                "0.0.0.0/0 route to a NAT/IGW. Provisioning-time detection and the running nodes "
                "(HA peer discovery, floating-IP failover, SSH-IAM, metering) require this.")

        # STS endpoint (WARN only).
        if q.get("check_sts") == "true":
            sts = aws(q, ["ec2", "describe-vpc-endpoints", "--filters",
                          f"Name=vpc-id,Values={vpc}",
                          f"Name=service-name,Values=com.amazonaws.{region}.sts"])
            if not any(ep.get("State") == "available" for ep in sts.get("VpcEndpoints", [])):
                warnings.append(
                    f"No available STS interface endpoint (com.amazonaws.{region}.sts) in VPC {vpc} - "
                    "STS-dependent features may fail if the subnet has no internet route")
    except Exception:
        warnings.append(
            "Could not complete VPC endpoint validation (insufficient describe permissions?) - "
            f"verify EC2 API reachability from subnet(s) {', '.join(subnets)} manually")


def main():
    q = json.load(sys.stdin)
    deployer_arn = ""

    # dsx mode: existing-Anvil probe + version compatibility first, so a wrong
    # IP / password / AMI fails here rather than 20 minutes into the join wait.
    if q.get("check_anvil") == "true":
        if check_anvil_probe(q):
            check_version_compat(q)

    try:
        caller_arn, deployer_arn = deployer_principal_arn(q)
    except Exception as e:
        errors.append(f"Could not resolve the deploying identity (sts get-caller-identity failed): {e}")

    if deployer_arn:
        check_instance_profile(q)
        simulate(q, deployer_arn, json.loads(q["deployer_actions"]), "Deploying identity")

    check_vpc_endpoints(q)

    json.dump({
        "ok": "false" if errors else "true",
        "errors": "\n".join(f"  - {e}" for e in errors),
        "warnings": "\n".join(f"  - {w}" for w in warnings),
        "deployer_arn": deployer_arn,
    }, sys.stdout)


if __name__ == "__main__":
    main()
