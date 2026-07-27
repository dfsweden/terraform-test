# Quickstart: Deploy Hammerspace in your own Azure subscription

This guide walks you from an empty Azure subscription to a running
Hammerspace cluster (1 Anvil metadata server + 1 DSX data node), and back to
a clean teardown. No access to any Hammerspace-internal system is required.

**What you need before starting:**

| Item | Where it comes from |
|---|---|
| An Azure subscription you can create resources in | You (Owner or Contributor role) |
| A **blob SAS URL** to the Hammerspace `.vhd` image | Hammerspace provides this — a long `https://…vhd?…sig=…` link, typically valid 24–48 h |
| Azure CLI (`az`) logged in | `az login` — or use [Azure Cloud Shell](https://shell.azure.com), which has it built in |
| Terraform ≥ 1.5 | terraform.io/downloads (not needed until step 3) |

Time budget: about 10 minutes of your attention, 30–45 minutes wall clock
(one-time image copy ≈ 5–15 min, cluster first boot ≈ 15 min).

---

## Step 1 — Sign in and choose the subscription

```bash
az login
az account set --subscription "<your-subscription-name-or-id>"
az account show --output table     # confirm you're where you think you are
```

## Step 2 — Create a network

The deployment creates VMs, disks, and security groups — but deliberately
**not** networks, so it can never disturb an existing one. A test VNet takes
two commands:

```bash
LOC=westus2    # pick any region; everything below must use the same one

az group create -n hs-net-rg -l $LOC
az network vnet create -g hs-net-rg -n hs-test-vnet \
  --address-prefix 10.10.0.0/16 \
  --subnet-name data --subnet-prefix 10.10.1.0/24
```

That's all standalone mode needs. (HA mode would additionally need a small
dedicated heartbeat subnet — see `examples/ha-standard.tfvars`.)

## Step 3 — Create your variables file

Copy the template and open it:

```bash
cp examples/sa-customer-sas.tfvars my-test.tfvars
```

Here is a complete working file — **the seven values marked CHANGE are the
only ones you must touch**:

```hcl
deployment_mode = "standalone"
name            = "hs1"

# ---- CHANGE (1): where to deploy --------------------------------------
# Terraform CREATES this resource group for you (because
# create_resource_group = true). Pick any unused name.
resource_group        = "hs-test-rg"
create_resource_group = true

# ---- CHANGE (2): the region — must match step 2's $LOC ----------------
location = "westus2"

# ---- CHANGE (3+4): the network you created in step 2 ------------------
virtual_network_resource_group = "hs-net-rg"
virtual_network_name           = "hs-test-vnet"
data_subnet_name               = "data"

# ---- CHANGE (5): the SAS URL from Hammerspace -------------------------
# Paste the whole link, quotes included. Checked at plan time - an expired
# or wrong URL stops the run before anything is created.
image_sas_url = "https://<account>.blob.core.windows.net/<container>/<image>.vhd?sp=r&...&sig=..."

# ---- CHANGE (6): where the downloaded image is kept -------------------
# Auto-created. Kept OUTSIDE hs-test-rg on purpose: destroying the
# deployment keeps the image, so you never download the 30+ GB twice.
image_resource_group = "hs-images-rg"

# ---- CHANGE (7): the cluster admin password ---------------------------
# Login will be user "admin" with this password.
admin_password = "<pick-a-strong-password>"

# ---- Sizing (defaults meet the product minimums - leave as is) --------
anvil_instance_type      = "Standard_F16s_v2" # Anvil minimum: 16 vCPU / 32 GiB
anvil_boot_disk_size     = 512                # minimum 512 GB
anvil_metadata_disk_size = 256
dsx_count                = 1
dsx_instance_type        = "Standard_F8s_v2"  # DSX minimum: 8 vCPU / 16 GiB
dsx_boot_disk_size       = 512
dsx_data_disk_count      = 1
dsx_data_disk_size       = 256

# ---- Access -----------------------------------------------------------
# true = public IPs on the VMs, so you can reach the cluster from your
# desk without VPN/peering. Fine for a throwaway test; use false when the
# VNet is otherwise reachable.
public_ip_addresses = true

owner = "<your-name>"   # tagged onto every resource
```

**Field-by-field reference:**

| # | Variable | What it is | Example |
|---|---|---|---|
| 1 | `resource_group` | New group for the cluster VMs (created for you) | `hs-test-rg` |
| 2 | `location` | Azure region for everything | `westus2` |
| 3 | `virtual_network_resource_group` | Group holding the VNet from step 2 | `hs-net-rg` |
| 4 | `virtual_network_name` / `data_subnet_name` | The VNet and subnet from step 2 | `hs-test-vnet` / `data` |
| 5 | `image_sas_url` | The link Hammerspace gave you | `https://…vhd?…sig=…` |
| 6 | `image_resource_group` | Where the reusable image lives (created for you) | `hs-images-rg` |
| 7 | `admin_password` | Cluster `admin` login password | — |

## Step 4 — Dry run, then deploy

```bash
terraform init
terraform plan -var-file=my-test.tfvars
```

`plan` creates **nothing**. It runs the full pre-flight: your login, the
region's VM sizes, the product sizing minimums, and the SAS URL itself. Fix
anything it flags and re-run — a clean plan means the apply will not die
half-way for a predictable reason.

```bash
terraform apply -var-file=my-test.tfvars
```

What you'll see, in order:

1. **Image staging** (first time only, ≈ 5–15 min): the VHD is copied
   server-side into `hs-images-rg` and becomes a managed image. Later
   applies find the image in about a second.
2. **VMs boot** (≈ 15 min): each VM's first boot runs the Hammerspace
   non-interactive installer; the apply waits until the cluster API
   answers, then tags every VM with the cluster ID.
3. Terraform prints outputs including `anvil_ip`.

## Step 5 — Log in

Open `https://<anvil_ip>:8443` — user `admin`, password from the vars file
(the certificate is self-signed, accept the warning). The DSX node appears
under Infrastructure as it finishes joining.

## Step 6 — Tear down

```bash
terraform destroy -var-file=my-test.tfvars
```

This deletes the cluster **and** `hs-test-rg` (Terraform created it), using
forced VM deletion — no waiting on guest shutdowns. It deliberately does
**not** touch:

- `hs-images-rg` — the staged image, so the next apply skips the download;
- `hs-net-rg` — your network.

Done with Hammerspace for good? Remove those too:

```bash
az group delete -n hs-images-rg --yes
az group delete -n hs-net-rg --yes
```

---

## If something goes wrong

| Symptom | Likely cause / fix |
|---|---|
| `plan` fails on `image_sas_url` | SAS expired or mispasted — ask Hammerspace for a fresh link. Note: the URL must NOT be IP-restricted (Azure Storage performs the copy, not your machine). |
| `plan` fails on a VM size | That size isn't offered in your region — pick another region, or another size meeting the minimums (Anvil 16 vCPU / 32 GiB, DSX 8 vCPU / 16 GiB). |
| `apply` succeeds but you can't open `:8443` | No network path: set `public_ip_addresses = true` for the test, or run from a machine that can reach the VNet. Ping never works (ICMP is not in the security group) — test the port instead. |
| First boot seems stuck > 25 min | Check the VM isn't stopped (`az vm list -g hs-test-rg -d -o table`) — some corporate subscriptions run automation that powers off unrecognized VMs. |
