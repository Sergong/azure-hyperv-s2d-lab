packer {
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "~> 1"
    }
  }
}

variable "generation" {
  type        = number
  default     = 1
  description = "Hyper-V VM generation (1 or 2)"
}

variable "switch_name" {
  type        = string
  default     = "PackerInternal"
  description = "Hyper-V switch to use"
}

variable "output_directory" {
  type        = string
  default     = "output-almalinux-simple"
  description = "Directory for output VM"
}

variable "vm_name" {
  type        = string
  default     = "almalinux-simple-template"
  description = "Name of the VM template"
}

variable "iso_path" {
  type        = string
  default     = "C:/ISOs/AlmaLinux-9-latest-x86_64-dvd.iso"
  description = "Path to AlmaLinux ISO file"
}

source "hyperv-iso" "almalinux" {
  # ISO Configuration - Using local ISO file
  iso_url      = var.iso_path
  iso_checksum = "none"  # Skip checksum verification
  
  # VM Configuration
  vm_name           = var.vm_name
  output_directory  = var.output_directory
  generation        = var.generation
  guest_additions_mode = "disable"
  
  # Hardware
  cpus      = 2
  memory    = 2048
  disk_size = 20480
  
  # Network - Simple configuration
  switch_name              = var.switch_name
  enable_mac_spoofing      = true
  enable_dynamic_memory    = false
  enable_secure_boot       = false
  
  # HTTP Server for Kickstart
  http_directory = "templates"
  http_port_min  = 8080
  http_port_max  = 8090
  
  # Boot Configuration
  boot_wait = "10s"
  boot_command = [
    "<tab>",
    " text",
    " inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/AlmaLinux/hyperv/ks.cfg",
    " ip=dhcp",
    " biosdevname=0",
    " net.ifnames=0",
    " rd.live.check=0",
    "<enter>"
  ]
  
  # SSH Configuration
  ssh_username     = "root"
  ssh_password     = "packer"
  ssh_timeout     = "30m"
  ssh_handshake_attempts = 100
  
  # Shutdown
  shutdown_command = "systemctl poweroff"
  shutdown_timeout = "5m"
  
  # Show console for debugging
  headless = false
}

build {
  sources = ["source.hyperv-iso.almalinux"]
  
  provisioner "shell" {
    inline = [
      "echo 'Basic AlmaLinux template build completed'",
      "dnf update -y",
      "dnf install -y hyperv-daemons hyperv-tools cloud-init",
      "systemctl enable hypervkvpd hypervvssd hypervfcopyd",
      "systemctl enable cloud-init",
      "echo 'Template ready for deployment'"
    ]
  }
}
