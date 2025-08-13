# Alternative version using for_each instead of count for better race condition prevention
# This approach provides more explicit resource naming and dependency management

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.11"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

provider "azurerm" {
  features {}
}

# Define the nodes as a map instead of using count
locals {
  vm_nodes = {
    "hyperv-node-0" = {
      vm_index = 0
      is_primary = true
      disk_indices = [0, 1]
    }
    "hyperv-node-1" = {
      vm_index = 1  
      is_primary = false
      disk_indices = [2, 3]
    }
  }
}

variable "admin_password" {
  description = "Admin password for Windows VM"
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Admin username for the Windows VM"
  type        = string
  default     = "adm-smeeuwsen"
}

resource "azurerm_resource_group" "lab" {
  name     = "hyperv-nested-rg"
  location = "UK South"
}

# Network infrastructure (same as before)
resource "azurerm_virtual_network" "vnet" {
  name                = "hyperv-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "hyperv-subnet"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_network_security_group" "vm_nsg" {
  name                = "hyperv-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "RDP-from-Bastion"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "AzureCloud"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Internal-Communication"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "10.0.1.0/24"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

# Storage for scripts
resource "random_string" "storage_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "scripts" {
  name                     = "hypervscripts${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.lab.name
  location                 = azurerm_resource_group.lab.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = true
}

resource "azurerm_storage_container" "scripts" {
  name                  = "scripts"
  storage_account_name  = azurerm_storage_account.scripts.name
  container_access_type = "blob"
}

resource "azurerm_storage_blob" "bootstrap_script" {
  name                   = "bootstrap.ps1"
  storage_account_name   = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "bootstrap.ps1"
  content_type          = "text/plain"
}

resource "azurerm_storage_blob" "s2d_script" {
  name                   = "setup-s2d-cluster.ps1"
  storage_account_name   = azurerm_storage_account.scripts.name
  storage_container_name = azurerm_storage_container.scripts.name
  type                   = "Block"
  source                 = "setup-s2d-cluster.ps1"
  content_type          = "text/plain"
}

##############################################################################
# VMs and NICs using for_each for better resource management
##############################################################################

# Network interfaces using for_each
resource "azurerm_network_interface" "nic" {
  for_each            = local.vm_nodes
  name                = "${each.key}-nic"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

# Virtual machines using for_each
resource "azurerm_windows_virtual_machine" "hyperv_node" {
  for_each            = local.vm_nodes
  name                = each.key
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  size                = "Standard_D4s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.nic[each.key].id]
  enable_automatic_updates = true

  os_disk {
    name                 = "${each.key}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter"
    version   = "latest"
  }

  boot_diagnostics {}

  additional_unattend_content {
    setting = "AutoLogon"
    content = <<CONTENT
<AutoLogon>
  <Password>
    <Value>${var.admin_password}</Value>
    <PlainText>true</PlainText>
  </Password>
  <Enabled>true</Enabled>
  <Username>${var.admin_username}</Username>
</AutoLogon>
CONTENT
  }
}

##############################################################################
# Storage disks with explicit naming
##############################################################################

resource "azurerm_managed_disk" "s2d_disk" {
  count                = 4
  name                 = "s2d-disk-${count.index}"
  location             = azurerm_resource_group.lab.location
  resource_group_name  = azurerm_resource_group.lab.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128
}

# Disk attachments with explicit VM targeting
resource "azurerm_virtual_machine_data_disk_attachment" "s2d_disk_attachment" {
  count              = 4
  managed_disk_id    = azurerm_managed_disk.s2d_disk[count.index].id
  virtual_machine_id = count.index < 2 ? azurerm_windows_virtual_machine.hyperv_node["hyperv-node-0"].id : azurerm_windows_virtual_machine.hyperv_node["hyperv-node-1"].id
  lun                = count.index < 2 ? count.index : count.index - 2
  caching            = "ReadWrite"
}

##############################################################################
# VM EXTENSIONS - RACE CONDITION PREVENTION WITH for_each
##############################################################################
# Using for_each with explicit dependency chaining between nodes

# Primary node extension
resource "azurerm_virtual_machine_extension" "bootstrap_primary" {
  name                 = "bootstrap-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.hyperv_node["hyperv-node-0"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  settings = jsonencode({
    fileUris = [azurerm_storage_blob.bootstrap_script.url]
    commandToExecute = "powershell -ExecutionPolicy Bypass -File bootstrap.ps1 -NodeName hyperv-node-0 -S2DScriptUrl '${azurerm_storage_blob.s2d_script.url}'"
  })
  
  # Explicit timeouts for long-running operations
  timeouts {
    create = "30m"
  }
  
  depends_on = [
    azurerm_virtual_machine_data_disk_attachment.s2d_disk_attachment,
    azurerm_storage_blob.bootstrap_script,
    azurerm_storage_blob.s2d_script
  ]
}

# Secondary node extension (waits for primary)
resource "azurerm_virtual_machine_extension" "bootstrap_secondary" {
  name                 = "bootstrap-extension"
  virtual_machine_id   = azurerm_windows_virtual_machine.hyperv_node["hyperv-node-1"].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  
  settings = jsonencode({
    fileUris = [azurerm_storage_blob.bootstrap_script.url]
    commandToExecute = "powershell -ExecutionPolicy Bypass -File bootstrap.ps1 -NodeName hyperv-node-1"
  })
  
  timeouts {
    create = "30m"
  }
  
  # This creates a strict dependency chain: secondary waits for primary completion
  depends_on = [
    azurerm_virtual_machine_extension.bootstrap_primary
  ]
}

##############################################################################
# OUTPUTS
##############################################################################

output "vm_private_ips" {
  description = "Private IP addresses of the VMs"
  value = {
    for vm_name, nic in azurerm_network_interface.nic : vm_name => nic.private_ip_address
  }
}

output "bastion_connection_info" {
  description = "Bastion connection information"
  value = {
    resource_group = azurerm_resource_group.lab.name
    connection_instructions = "Azure Bastion Developer SKU will be created automatically when you connect to VMs through Azure Portal"
  }
}

output "script_urls" {
  description = "URLs for the uploaded scripts"
  value = {
    bootstrap_script = azurerm_storage_blob.bootstrap_script.url
    s2d_script = azurerm_storage_blob.s2d_script.url
  }
}
