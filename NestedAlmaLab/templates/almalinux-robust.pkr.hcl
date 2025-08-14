packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "~> 1"
    }
  }
}

variable "kickstart_version" {
  type        = string
  default     = "v2"
  description = "Version of kickstart config to use"
}

variable "switch_name" {
  type        = string
  default     = "Default Switch"
  description = "Hyper-V switch to use - can override for External/Internal switches"
}

variable "output_directory" {
  type        = string
  default     = "output-almalinux"
  description = "Directory for output VM"
}

variable "vm_name" {
  type        = string
  default     = "almalinux-9.4-template"
  description = "Name of the VM template"
}

# Locals for computed values
locals {
  kickstart_file = "kickstart-${var.kickstart_version}.cfg"
  iso_url        = "https://repo.almalinux.org/almalinux/9.4/isos/x86_64/AlmaLinux-9.4-x86_64-minimal.iso"
  iso_checksum   = "file:https://repo.almalinux.org/almalinux/9.4/isos/x86_64/CHECKSUM"
}

source "hyperv-iso" "almalinux" {
  # ISO Configuration
  iso_url      = local.iso_url
  iso_checksum = local.iso_checksum
  
  # VM Basic Configuration
  vm_name           = var.vm_name
  output_directory  = var.output_directory
  generation        = 2
  guest_additions_mode = "disable"
  
  # Hardware Configuration
  cpus              = 2
  memory            = 2048
  disk_size         = 20480
  disk_block_size   = 1
  
  # Critical Network Configuration
  switch_name              = var.switch_name
  enable_mac_spoofing      = true
  enable_dynamic_memory    = false
  enable_secure_boot       = false
  enable_virtualization_extensions = false
  
  # HTTP Server for Kickstart - Enhanced Configuration
  http_directory    = "kickstart"
  http_port_min     = 8080
  http_port_max     = 8090
  http_bind_address = "0.0.0.0"  # Bind to all interfaces
  
  # Boot Configuration - Robust boot sequence
  boot_wait = "10s"  # Longer wait for stability
  boot_command = [
    "<tab>",
    " inst.text",
    " inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/${local.kickstart_file}",
    " ip=dhcp",
    " biosdevname=0", 
    " net.ifnames=0",
    " inst.repo=https://repo.almalinux.org/almalinux/9.4/BaseOS/x86_64/os/",
    "<enter>"
  ]
  
  # SSH Configuration - More tolerant settings
  ssh_username           = "root"
  ssh_password           = "packer"
  ssh_timeout           = "45m"
  ssh_handshake_attempts = 200
  ssh_pty               = true
  
  # Shutdown Configuration
  shutdown_command = "systemctl poweroff"
  shutdown_timeout = "10m"
  
  # Additional Robustness
  headless = false  # Show VM console for debugging
}

build {
  name = "almalinux-lab"
  sources = ["source.hyperv-iso.almalinux"]
  
  # Basic provisioning to verify the template works
  provisioner "shell" {
    inline = [
      "echo 'AlmaLinux template build started'",
      "dnf update -y",
      "dnf install -y cloud-init cloud-utils-growpart",
      "systemctl enable cloud-init",
      "echo 'Template provisioning completed successfully'"
    ]
  }
  
  # Clean up for template use
  provisioner "shell" {
    inline = [
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "history -c",
      "cat /dev/null > ~/.bash_history",
      "rm -f /root/.ssh/authorized_keys",
      "echo 'Template cleanup completed'"
    ]
  }
}
