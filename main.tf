provider "azurerm" {
  features {}
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

resource "azurerm_network_interface" "nic" {
  count               = 2
  name                = "hyperv-nic-${count.index}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  ip_configuration {
    name                          = "ipconfig"
    subnet_id                    = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "hyperv_node" {
  count               = 2
  name                = "hyperv-node-${count.index}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  size                = "Standard_D4s_v3"
  admin_username      = "labadmin"
  admin_password      = "SuperSecurePassword123!"

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
    sku       = "2022-datacenter"
    version   = "latest"
  }

  boot_diagnostics {
    enabled = true
  }

  additional_unattend_content {
    setting = "AutoLogon"
    content = <<CONTENT
<AutoLogon>
  <Password>
    <Value>SuperSecurePassword123!</Value>
    <PlainText>true</PlainText>
  </Password>
  <Enabled>true</Enabled>
  <Username>labadmin</Username>
</AutoLogon>
CONTENT
  }

  custom_data = base64encode(file("bootstrap.ps1"))
}

