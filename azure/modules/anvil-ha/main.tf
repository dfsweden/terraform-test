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
# Each Anvil has TWO NICs: eth0 = data/mgmt on the data subnet
# (in the LB pool), eth1 = HA heartbeat on a dedicated subnet.
#
# ARM quirk kept on purpose: Anvil1 boots ha_mode=Secondary and
# Anvil2 boots ha_mode=Primary (hostnames <prefix>Anvil and
# <prefix>Anvil-2).
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
  }
}

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
}

locals {
  cluster_ip = var.cluster_ip != "" ? var.cluster_ip : azurerm_lb.cluster.private_ip_address

  nodes = {
    "1" = { computer_name = "${var.prefix}Anvil", ha_mode = "Secondary" }
    "2" = { computer_name = "${var.prefix}Anvil-2", ha_mode = "Primary" }
  }

  # ARM anvil1CustomData / anvil2CustomData (verbatim structure): eth0 carries
  # the cluster IP with the data subnet's prefix length, eth1 is the HA link.
  custom_data = {
    for idx, node in local.nodes : idx => jsonencode({
      cluster = {
        domainname = var.domain
      }
      node = {
        hostname = node.computer_name
        ha_mode  = node.ha_mode
        networks = {
          eth0 = {
            cluster_ips = ["${local.cluster_ip}/${var.subnet_prefixlen}"]
            roles       = ["data", "mgmt"]
          }
          eth1 = {
            dhcp  = true
            roles = ["ha"]
          }
        }
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
  tags                = var.tags
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
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = var.public_ip ? azurerm_public_ip.anvil[each.key].id : null
  }
}

resource "azurerm_network_interface" "ha" {
  for_each = local.nodes

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
  for_each = local.nodes

  network_interface_id      = azurerm_network_interface.ha[each.key].id
  network_security_group_id = var.nsg_id
}

resource "azurerm_network_interface_backend_address_pool_association" "data" {
  for_each = local.nodes

  network_interface_id    = azurerm_network_interface.data[each.key].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.cluster.id
}

# --- The two Anvil VMs ---
module "vm" {
  source   = "../hs-vm"
  for_each = local.nodes

  name                = "${var.prefix}Anvil${each.key}"
  computer_name       = each.value.computer_name
  location            = var.location
  resource_group      = var.resource_group
  nic_ids             = [azurerm_network_interface.data[each.key].id, azurerm_network_interface.ha[each.key].id]
  instance_type       = var.instance_type
  availability_set_id = var.availability_set_id
  ppg_id              = var.ppg_id
  image_id            = var.image_id
  marketplace_image   = var.marketplace_image
  os_disk_size        = var.boot_disk_size
  os_disk_type        = var.boot_disk_type
  data_disks = [
    { lun = 1, size = var.metadata_disk_size, type = var.metadata_disk_type }
  ]
  custom_data    = local.custom_data[each.key]
  admin_username = var.admin_username
  admin_password = var.admin_password
  tags           = var.tags
}
