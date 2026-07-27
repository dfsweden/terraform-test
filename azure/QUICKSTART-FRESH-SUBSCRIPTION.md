# Quickstart: test in a fresh / personal Azure subscription

Everything Hammerspace-internal is optional here: the only artifact you need
from Hammerspace is a **blob SAS URL** to the product `.vhd` (see
`examples/sa-customer-sas.tfvars` for how it is generated).

## 1. Log in and pick a subscription

```bash
az login
az account set --subscription "<SUBSCRIPTION_NAME_OR_ID>"
```

## 2. Create the network (the deployment expects it to pre-exist)

```bash
LOC=westus2   # any region; must match where you deploy
az group create -n hs-test-rg -l $LOC
az network vnet create -g hs-test-rg -n hs-test-vnet \
  --address-prefix 10.10.0.0/16 \
  --subnet-name data --subnet-prefix 10.10.1.0/24
```

HA mode additionally needs a small dedicated heartbeat subnet:

```bash
az network vnet subnet create -g hs-test-rg --vnet-name hs-test-vnet \
  -n ha --address-prefixes 10.10.2.0/29
```

## 3. Stage the Hammerspace image (once)

Either let Terraform do it inline (`image_sas_url` in the tfvars), or stage
ahead of time:

```bash
./scripts/stage-hammerspace-image.sh -u "<BLOB_SAS_URL>" -g hs-test-rg -l $LOC
# prints: image_id = "/subscriptions/.../images/Hammerspace-<version>"
```

The image persists across deployments - `terraform destroy` never deletes
it, so repeated apply/destroy cycles skip the 30+ GB download.

## 4. Deploy

Copy `examples/sa-customer-sas.tfvars`, fill in:

```hcl
resource_group       = "hs-test-rg"
virtual_network_name = "hs-test-vnet"
data_subnet_name     = "data"
image_sas_url        = "<BLOB_SAS_URL>"   # or image_id from step 3
admin_password       = "<PICK_A_PASSWORD>"
```

Then:

```bash
terraform init
terraform plan  -var-file=my-test.tfvars   # dry run: full pre-flight, creates nothing
terraform apply -var-file=my-test.tfvars
```

The apply waits for the cluster API and tags every VM with the cluster ID.
Login: `https://<anvil_ip>:8443`, user `admin`, your password. If the VMs
have no public IPs (default), run from a machine with a network path to the
VNet, or set `public_ip_addresses = true` for a throwaway test.

## 5. Tear down

```bash
terraform destroy -var-file=my-test.tfvars   # forced, no clean-shutdown wait
```

The staged image (and the small empty `hsimg*` storage account) remain for
the next apply; delete them manually when done for good:

```bash
az image delete -g hs-test-rg -n Hammerspace-<version>
```

## Notes

- Instance minimums are enforced at plan time: Anvil 16 vCPU / 32 GiB,
  DSX 8 vCPU / 16 GiB, boot disks >= 512 GB. The example tfvars comply.
- Metadata disk defaults to Premium SSD v2 (5000 IOPS provisioned); in HA
  mode it transparently falls back to Premium_LRS (availability-set
  restriction) - size >= 1024 GB for equivalent IOPS.
- Pre-flight (`terraform plan`) checks CLI login, VM-size availability in
  the region, size minimums, and the SAS URL/image before anything is
  created.
