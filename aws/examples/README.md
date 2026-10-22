# Example variable files

Two kinds, and the difference matters for what may leave Hammerspace.

## `examples/*.tfvars` — generic

Every account-specific value is a `<PLACEHOLDER>`. These are the files that
ship. They contain no VPC, subnet, AMI, account or profile name belonging to
anyone, and they are safe to publish.

| file | shape |
|---|---|
| `sa-standard.tfvars` | standalone: 1 Anvil + 1 DSX |
| `ha-standard.tfvars` | HA: 2 Anvils in one AZ + DSX |
| `ha-multi-az.tfvars` | HA across two AZs, a DSX in each, overlay cluster IP, internal NLB |
| `dsx-add-to-existing.tfvars` | add DSX node(s) to an EXISTING cluster (`deployment_mode = "dsx"`) - the ONLY supported way to grow a cluster |

A placeholder is not merely documentation: input validation rejects
`<YOUR_VPC_ID>` and `vpc-xxxxxxxx` alike at plan time, so an unedited file
fails immediately with a message naming the variable, rather than failing
against the AWS API half-way through an apply.

## `examples/lab/*.tfvars` — real values, INTERNAL ONLY

The same shapes filled in against a Hammerspace test account, so a lab
deployment is one command instead of a scavenger hunt. What they name, and which
of them have actually been applied, is documented in `lab/README.md`.

**Do not publish `lab/` outside Hammerspace.** Anything sanitised for external
release must exclude this directory wholesale — that is the entire reason it is
a directory rather than a naming convention. Before adding a file there, ask
whether it names infrastructure that belongs to us; if it does, it belongs
there and not one level up.

**That rule applies to this file.** No VPC, subnet, AMI, account or profile name
appears anywhere above, and none should be added — a README that ships beside
the generic examples is not the place to record them, or excluding one directory
stops being sufficient.

## Sizing is enforced, not advised

Anvil **16 vCPU / 32 GiB**, DSX **8 vCPU / 16 GiB**. Pre-flight fails the plan
below either. The Ansible examples in `hs-anvil-dsx-provision/examples/` predate
this and specify 4- and 8-vCPU Anvils; those numbers are wrong, and the values
here are correct.

## Instance families

Prefer the newest generation available. AWS examples use **m8i** (Intel Xeon 6);
`m7a` was the previous choice and every example has been moved off it. The
ephemeral-storage examples use `r8id`/`c8id`/`r8i`, which are current.

A newer generation is only usable if it is offered in your region's AZs and
your account has quota in that family - both are worth checking before
substituting one in.

## Ephemeral storage

On instance types with built-in NVMe (`i4i`, `i7ie`, `r8id`, `c8id`, ...) the
metadata EBS volumes for an Anvil and the data EBS volumes for a DSX are skipped
automatically — Hammerspace uses the local drives. The boot volume is always
provisioned. Detection happens at plan time, so the plan shows exactly which
volumes will be created.
