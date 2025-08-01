terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.11"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Get the current public IP of the machine running Terraform
data "http" "current_ip" {
  url = "https://ipv4.icanhazip.com"
}

locals {
  current_ip = chomp(data.http.current_ip.response_body)
}

// Ensure you export TF_VAR_admin_password before running this!
variable "admin_password" {
  description = "Admin password for Windows VM"
  type        = string
  sensitive   = true
}

variable "admin_username" {
  description = "Admin username for the Windows VM"
  type        = string
  default     = "adm-smeeuwsen"  # Optional: set a default or omit this if it must be provided explicitly
}


resource "azurerm_resource_group" "lab" {
  name     = "hyperv-nested-rg"
  location = "UK South"
}

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

# Public IP for each VM
resource "azurerm_public_ip" "vm_public_ip" {
  count               = 2
  name                = "hyperv-pip-${count.index}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Network Security Group
resource "azurerm_network_security_group" "vm_nsg" {
  name                = "hyperv-nsg"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "RDP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "${local.current_ip}/32"  # Restricted to current public IP
    destination_address_prefix = "*"
  }
}

# Associate NSG with subnet
resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  subnet_id                 = azurerm_subnet.subnet.id
  network_security_group_id = azurerm_network_security_group.vm_nsg.id
}

resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "hyperv-nic-${count.index}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_public_ip[count.index].id
  }
}

resource "azurerm_windows_virtual_machine" "hyperv_node" {
  count               = 2
  name                = "hyperv-node-${count.index}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  size                = "Standard_D4s_v3"
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  network_interface_ids = [azurerm_network_interface.nic[count.index].id]
  enable_automatic_updates = false

  os_disk {
    name              = "hyperv-osdisk-${count.index}"
    caching           = "ReadWrite"
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

  custom_data = base64encode(file("bootstrap.ps1"))
}

# Outputs for easy access to connection information
output "vm_public_ips" {
  description = "Public IP addresses of the VMs"
  value = {
    for i in range(2) : "hyperv-node-${i}" => azurerm_public_ip.vm_public_ip[i].ip_address
  }
}

output "vm_private_ips" {
  description = "Private IP addresses of the VMs"
  value = {
    for i in range(2) : "hyperv-node-${i}" => azurerm_network_interface.nic[i].private_ip_address
  }
}

output "rdp_connection_info" {
  description = "RDP connection information"
  value = {
    for i in range(2) : "hyperv-node-${i}" => {
      public_ip = azurerm_public_ip.vm_public_ip[i].ip_address
      username  = var.admin_username
      rdp_port  = 3389
    }
  }
}

output "allowed_source_ip" {
  description = "Your current public IP that is allowed RDP access"
  value       = local.current_ip
}
