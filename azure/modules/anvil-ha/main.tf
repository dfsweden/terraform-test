# ============================================================
# 2-node HA Anvil on Azure - the ARM template's
# anvilConfiguration=High Availability path.
#
# The floating cluster IP is the frontend IP of an INTERNAL
# Standard Load Balancer on the data subnet: an HA-ports rule
# (protocol All, port 0) with floating IP enabled forwards
# everything to the backend pool holding both Anvil data NICs,
# and a TCP health probe on 4505 steers traffic to the ACTIVE
# node. Failover is probe-driven - no cloud API calls, no route
# rewriting, no IAM/identity requirements (the Azure delta vs
# the AWS design).
#
# NICs: eth0 = data/mgmt (LB pool), eth1 = HA heartbeat on a
# dedicated subnet. The heartbeat subnet is REQUIRED on Azure:
# it is the peer-DISCOVERY mechanism, not just a heartbeat
# link. The product's Azure provisioning (pd/prov/azure.py)
# hard-codes node_idx=0 and cannot consume the nodes-map /
# node_index pattern AWS uses for single-NIC pairing - two
# single-NIC Anvils never find each other (verified live
# 2026-07-28: clean 60-min run, both nodes healthy, no
# pairing). The module still ACCEPTS ha_subnet_id = null for
# a future image that supports node_index, but the root
# validation requires the subnet today.
#
# ARM quirk kept on purpose: Anvil1 boots ha_mode=Secondary and
# Anvil2 boots ha_mode=Primary (hostnames <prefix>Anvil and
# <prefix>Anvil-2).
#
# ha-multi-az (var.zones set): the SAME load balancer with a
# ZONE-REDUNDANT frontend, each Anvil pinned to its own zone with
# zonal disks and a zonal public IP, and no availability set -
# which is what lets the pair keep PremiumV2/Ultra metadata
# disks. Nothing else changes: same NICs, same heartbeat subnet
# (a subnet spans every zone), same custom data.
# ============================================================

# --- Internal load balancer = the floating cluster IP ---
resource "azurerm_lb" "cluster" {
  name                = "${var.prefix}LoadBalancer"
  location            = var.location
  resource_group_name = var.resource_group
  sku                 = "Standard"
  tags                = var.tags

  frontend_ip_configuration {
    name                          = "${var.prefix}LoadBalancerFrontEnd"
    subnet_id                     = var.data_subnet_id
    private_ip_address_allocation = var.cluster_ip != "" ? "Static" : "Dynamic"
    private_ip_address            = var.cluster_ip != "" ? var.cluster_ip : null
    private_ip_address_version    = "IPv4"
    # ha-multi-az: zone-redundant frontend - every zone, which is Azure's
    # definition of zone-redundant (a subset is not a recognised shape) - so
    # the cluster IP outlives the loss of either Anvil's zone. null = today's
    # non-zonal frontend for the availability-set pair.
    zones = local.zonal ? ["1", "2", "3"] : null
  }
}

# The pool, probe and rule are separate resources that all mutate the SAME load
# balancer entity, and Azure serialises writes to it: created in parallel they
# race and one returns
#
#   409 ConflictingConcurrentWriteNotAllowed: The operation was interrupted by a
#   conflicting concurrent write on the same entity. Please retry later.
#
# Measured 2026-09-26 in westus2 on the probe. It is a race, so it passes more
# often than it fails - which is worse than a reliable failure. Chained
# explicitly: pool -> probe -> rule. Terraform infers pool/probe from
# loadbalancer_id but has no reason to order the two against each other, and
# the rule's references do not force the probe to finish writing first.
resource "azurerm_lb_backend_address_pool" "cluster" {
  name            = "${var.prefix}LoadBalancerBEPool"
  loadbalancer_id = azurerm_lb.cluster.id
}

# TCP 4505 answers only on the active Anvil.
resource "azurerm_lb_probe" "active_node" {
  name                = "${var.prefix}LoadBalancerProbe"
  loadbalancer_id     = azurerm_lb.cluster.id
  protocol            = "Tcp"
  port                = 4505
  interval_in_seconds = 15
  number_of_probes    = 2

  depends_on = [azurerm_lb_backend_address_pool.cluster]
}

# HA-ports rule: forward ALL ports/protocols to the active node.
resource "azurerm_lb_rule" "ha_ports" {
  name                           = "${var.prefix}LoadBalancerRule"
  loadbalancer_id                = azurerm_lb.cluster.id
  frontend_ip_configuration_name = "${var.prefix}LoadBalancerFrontEnd"
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.cluster.id]
  probe_id                       = azurerm_lb_probe.active_node.id
  protocol                       = "All"
  frontend_port                  = 0
  backend_port                   = 0
  enable_floating_ip             = true

  depends_on = [azurerm_lb_probe.active_node]
}

locals {
  cluster_ip = var.cluster_ip != "" ? var.cluster_ip : azurerm_lb.cluster.private_ip_address

  # Dual-NIC (eth1 on a dedicated heartbeat subnet) whenever a subnet was
  # supplied - which the root validation requires for ha mode today, because
  # heartbeat-on-eth0 cannot pair on Azure (see the header). The single-NIC
  # branch below is kept for a future image with node_index support; it is NOT
  # a supported configuration now.
  dual_nic = var.ha_subnet_id != null && var.ha_subnet_id != ""

  zonal = length(var.zones) > 0

  nodes = {
    "1" = { computer_name = "${var.prefix}Anvil", ha_mode = "Secondary", zone = local.zonal ? var.zones[0] : null }
    "2" = { computer_name = "${var.prefix}Anvil-2", ha_mode = "Primary", zone = local.zonal ? var.zones[1] : null }
  }

  # eth0 carries the cluster IP with the data subnet's prefix length; the
  # ha role rides on eth0 unless a dedicated heartbeat subnet adds eth1.
  custom_data = {
    for idx, node in local.nodes : idx => jsonencode({
      cluster = {
        domainname = var.domain
      }
      node = {
        hostname = node.computer_name
        ha_mode  = node.ha_mode
        networks = merge(
          {
            eth0 = {
              cluster_ips = ["${local.cluster_ip}/${var.subnet_prefixlen}"]
              roles       = local.dual_nic ? ["data", "mgmt"] : ["data", "mgmt", "ha"]
            }
          },
          local.dual_nic ? {
            eth1 = {
              dhcp  = true
              roles = ["ha"]
            }
          } : {}
        )
      }
    })
  }
}

# --- Per-node networking ---
resource "azurerm_public_ip" "anvil" {
  for_each = var.public_ip ? local.nodes : {}

  name                = "${var.prefix}Anvil${each.key}PubIP"
  location            = var.location
  resource_group_name = var.resource_group
  allocation_method   = "Static"
  sku                 = "Standard"
  # Zonal, matching the VM: a per-node PIP has no life beyond its VM
  # (zone-redundant would also attach, and buy nothing).
  zones = local.zonal ? [each.value.zone] : null
  tags  = var.tags
}

resource "azurerm_network_interface" "data" {
  for_each = local.nodes

  name                = "${var.prefix}Anvil${each.key}DataIface"
  location            = var.location
  resource_group_name = var.resource_group
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    primary                       = true
    subnet_id                     = var.data_subnet_id
    private_ip_address_allocation = length(var.node_ips) >= tonumber(each.key) ? "Static" : "Dynamic"
    private_ip_address            = length(var.node_ips) >= tonumber(each.key) ? var.node_ips[tonumber(each.key) - 1] : null
    public_ip_address_id          = var.public_ip ? azurerm_public_ip.anvil[each.key].id : null
  }
}

resource "azurerm_network_interface" "ha" {
  for_each = local.dual_nic ? local.nodes : {}

  name                = "${var.prefix}Anvil${each.key}HaIface"
  location            = var.location
  resource_group_name = var.resource_group
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.ha_subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_network_interface_security_group_association" "data" {
  for_each = local.nodes

  network_interface_id      = azurerm_network_interface.data[each.key].id
  network_security_group_id = var.nsg_id
}

resource "azurerm_network_interface_security_group_association" "ha" {
  for_each = local.dual_nic ? local.nodes : {}

  network_interface_id      = azurerm_network_interface.ha[each.key].id
  network_security_group_id = var.nsg_id
}

# Also a write to the load balancer, and for_each runs both in parallel: chain
# them behind the rule for the same 409 reason.
resource "azurerm_network_interface_backend_address_pool_association" "data" {
  for_each = local.nodes

  depends_on = [azurerm_lb_rule.ha_ports]

  network_interface_id    = azurerm_network_interface.data[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.cluster.id
}

# --- The two Anvil VMs ---
module "vm" {
  source   = "../hs-vm"
  for_each = local.nodes

  name           = "${var.prefix}Anvil${each.key}"
  computer_name  = each.value.computer_name
  location       = var.location
  resource_group = var.resource_group
  nic_ids = concat(
    [azurerm_network_interface.data[each.key].id],
    local.dual_nic ? [azurerm_network_interface.ha[each.key].id] : [],
  )
  instance_type       = var.instance_type
  availability_set_id = var.availability_set_id
  ppg_id              = var.ppg_id
  zone                = each.value.zone
  image_id            = var.image_id
  marketplace_image   = var.marketplace_image
  os_disk_size        = var.boot_disk_size
  os_disk_type        = var.boot_disk_type
  # Same shape as anvil-standalone: iops/throughput reach the disk only for
  # PremiumV2/Ultra, so they are inert after the ha-mode fallback and live
  # for zonal Anvils.
  data_disks = [
    {
      lun        = 1
      size       = var.metadata_disk_size
      type       = var.metadata_disk_type
      iops       = var.metadata_disk_iops
      throughput = var.metadata_disk_throughput
    }
  ]
  custom_data      = local.custom_data[each.key]
  diag_storage_uri = var.diag_storage_uri
  admin_username   = var.admin_username
  admin_password   = var.admin_password
  tags             = var.tags
}
