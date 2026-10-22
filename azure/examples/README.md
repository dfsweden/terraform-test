# Example variable files

Two kinds, and the difference matters for what may leave Hammerspace. The AWS
tree uses the same split - see `../../aws/examples/README.md`.

## `examples/*.tfvars` — generic

Every subscription-specific value is a `<PLACEHOLDER>`: no subscription ID,
VNet, subnet, resource group or image ID belonging to anyone. These are the
files that ship, and they are safe to publish.

| file | shape |
|---|---|
| `sa-standard.tfvars` | standalone: 1 Anvil + DSX |
| `ha-standard.tfvars` | HA: 2 Anvils + DSX |
| `ha-multi-az.tfvars` | HA across availability ZONES: 2 Anvils (one per zone) + DSX spread over zones, zone-redundant LB - needs a zonal region |
| `sa-customer-sas.tfvars` | standalone, staging the image from a delivered blob SAS URL |
| `dsx-add-to-existing.tfvars` | add DSX node(s) to an EXISTING cluster (`deployment_mode = "dsx"`) |

Validation rejects an unedited placeholder at plan time with a message naming
the variable, rather than failing against ARM half-way through an apply.

## `examples/lab/*.tfvars` — real values, INTERNAL ONLY

The same shapes filled in against a Hammerspace test subscription, so a lab
deployment is one command instead of a scavenger hunt. What they name, and which
of them have actually been applied, is documented in `lab/README.md`.

**Do not publish `lab/` outside Hammerspace.** Anything sanitised for external
release must exclude this directory wholesale — that is the entire reason it is
a directory rather than a naming convention. Before adding a file there, ask
whether it names infrastructure that belongs to us; if it does, it belongs there
and not one level up.

**That rule applies to this file.** No subscription ID, VNet, resource group,
subnet or image name appears anywhere above, and none should be added — a
README that ships beside the generic examples is not the place to record them,
or excluding one directory stops being sufficient.

**No password is stored even in lab.** `admin_password` is
`<SET_AT_APPLY_TIME>`; pass it on the command line instead:

    terraform apply -var-file=examples/lab/sa-standard.tfvars \
      -var "admin_password=$(cat ~/.hs-lab-pw)"

## Instance families and the two Azure gates

Prefer the newest generation - but on Azure "newest" is limited by two
independent things, and a size must clear both:

1. **Image generation.** v6 sizes are Gen2-only. A Gen1 (V1) image, which is
   what the thor4 line ships by default, tops out at **v5**. The same VHD
   registered as V2 (`image_generation = "V2"`, or `-G V2` when staging from
   a SAS URL) boots Gen2 sizes; v6/v7 additionally need a Compute Gallery
   definition with NVMe declared, which the configuration does not create.
2. **Per-family vCPU quota**, which is small by default and is granted per
   family, not per subscription — so clearing it for one family says nothing
   about the next. An HA pair plus two DSX needs 48 vCPU of a single family,
   which is more than a default allocation typically carries. A quota error on
   apply is the usual reason a "newer is better" substitution fails.

Check both before substituting a newer size:

    az vm list-skus -l <REGION> --resource-type virtualMachines \
      --query "[?name=='<SIZE>'].capabilities[?name=='HyperVGenerations']"
    az vm list-usage -l <REGION>
