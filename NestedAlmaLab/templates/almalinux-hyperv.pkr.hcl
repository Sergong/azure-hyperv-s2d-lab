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
  default     = "hyperv"
  description = "Version of kickstart config to use (hyperv, v1, v2)"
}

variable "generation" {
  type        = number
  default     = 1
  description = "Hyper-V VM generation (1 or 2) - Gen 1 is more compatible"
}

variable "switch_name" {
  type        = string
  default     = "Default Switch"
  description = "Hyper-V switch to use"
}

variable "output_directory" {
  type        = string
  default     = "output-almalinux-hyperv"
  description = "Directory for output VM"
}

variable "vm_name" {
  type        = string
  default     = "almalinux-9.4-hyperv-template"
  description = "Name of the VM template"
}

# Locals for computed values
locals {
  kickstart_file = var.kickstart_version == "hyperv" ? "hyperv/ks.cfg" : "${var.kickstart_version}/ks.cfg"
  iso_url        = "https://repo.almalinux.org/almalinux/9.4/isos/x86_64/AlmaLinux-9.4-x86_64-minimal.iso"
  iso_checksum   = "file:https://repo.almalinux.org/almalinux/9.4/isos/x86_64/CHECKSUM"
  
  # Different boot commands for Gen1 vs Gen2
  boot_command_gen1 = [
    "<tab>",
    " text",
    " inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/AlmaLinux/${local.kickstart_file}",
    " ip=dhcp",
    " biosdevname=0",
    " net.ifnames=0",
    " console=tty0",
    " console=ttyS0,115200n8",
    "<enter>"
  ]
  
  boot_command_gen2 = [
    "<tab>",
    " text",
    " inst.ks=http://{{.HTTPIP}}:{{.HTTPPort}}/AlmaLinux/${local.kickstart_file}",
    " ip=dhcp",
    " biosdevname=0",
    " net.ifnames=0",
    " console=tty0",
    " console=ttyS0,115200n8",
    " modprobe.blacklist=nouveau",
    "<enter>"
  ]
}

source "hyperv-iso" "almalinux" {
  # ISO Configuration
  iso_url      = local.iso_url
  iso_checksum = local.iso_checksum
  
  # VM Basic Configuration
  vm_name           = var.vm_name
  output_directory  = var.output_directory
  generation        = var.generation
  guest_additions_mode = "disable"
  
  # Hardware Configuration - Conservative settings for compatibility
  cpus              = 2
  memory            = 2048
  disk_size         = 20480
  disk_block_size   = 1
  
  # Network Configuration - Hyper-V optimized
  switch_name              = var.switch_name
  enable_mac_spoofing      = true
  enable_dynamic_memory    = false
  enable_secure_boot       = false  # Disable for better compatibility
  enable_virtualization_extensions = false
  
  # HTTP Server for Kickstart
  http_directory = "templates"
  http_port_min  = 8080
  http_port_max  = 8090
  
  # Boot Configuration - Different for Gen1 vs Gen2
  boot_wait    = "15s"  # Longer wait for Hyper-V
  boot_command = var.generation == 1 ? local.boot_command_gen1 : local.boot_command_gen2
  
  # SSH Configuration - Extended timeouts for slow Hyper-V networking
  ssh_username           = "root"
  ssh_password           = "packer"
  ssh_timeout           = "60m"
  ssh_handshake_attempts = 300
  ssh_pty               = true
  
  # Shutdown Configuration
  shutdown_command = "systemctl poweroff"
  shutdown_timeout = "15m"
  
  # Debugging - Show console for troubleshooting
  headless = false
}

build {
  name = "almalinux-hyperv"
  sources = ["source.hyperv-iso.almalinux"]
  
  # Wait for system to fully boot and network to be ready
  provisioner "shell" {
    pause_before = "30s"
    inline = [
      "echo 'Waiting for system to be fully ready...'",
      "sleep 30",
      "systemctl status NetworkManager --no-pager || true",
      "ip addr show || true",
      "ping -c 3 8.8.8.8 || echo 'Network not ready yet'"
    ]
  }
  
  # Install additional packages and optimize for Hyper-V
  provisioner "shell" {
    inline = [
      "echo 'Configuring AlmaLinux for Hyper-V...'",
      "dnf update -y",
      
      # Ensure Hyper-V integration services are installed and running
      "dnf install -y hyperv-daemons hyperv-tools",
      "systemctl enable hypervkvpd hypervvssd hypervfcopyd",
      "systemctl start hypervkvpd hypervvssd hypervfcopyd",
      
      # Install cloud-init for template usage
      "dnf install -y cloud-init cloud-utils-growpart",
      "systemctl enable cloud-init cloud-init-local cloud-config cloud-final",
      
      # Configure network to be more reliable
      "systemctl enable NetworkManager",
      "systemctl start NetworkManager",
      
      # Test network connectivity
      "echo 'Testing network connectivity...'",
      "curl -s --connect-timeout 10 http://google.com >/dev/null && echo 'Internet OK' || echo 'Internet FAILED'",
      
      "echo 'Hyper-V optimization completed'"
    ]
  }
  
  # Create network troubleshooting tools
  provisioner "shell" {
    inline = [
      "echo 'Installing network troubleshooting tools...'",
      
      # Create advanced network diagnostic script
      "cat > /usr/local/bin/hyperv-network-test.sh << 'NETEOF'",
      "#!/bin/bash",
      "echo '=== Hyper-V Network Diagnostics ==='",
      "echo 'Date: '$(date)",
      "echo 'Hostname: '$(hostname)",
      "echo ''",
      "echo 'Hyper-V Integration Services:'",
      "systemctl status hypervkvpd --no-pager",
      "echo ''",
      "echo 'Network Interfaces:'",
      "ip addr show",
      "echo ''",
      "echo 'Network Manager:'",
      "nmcli device status",
      "echo ''",
      "echo 'Routing:'",
      "ip route show",
      "echo ''",
      "echo 'DNS:'",
      "cat /etc/resolv.conf",
      "echo ''",
      "echo 'Connectivity Test:'",
      "ping -c 3 8.8.8.8",
      "NETEOF",
      
      "chmod +x /usr/local/bin/hyperv-network-test.sh",
      "echo 'Network tools installed'"
    ]
  }
  
  # Final template cleanup
  provisioner "shell" {
    inline = [
      "echo 'Cleaning up template...'",
      
      # Clear logs and temporary files
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "truncate -s 0 /var/log/messages",
      "truncate -s 0 /var/log/secure",
      "truncate -s 0 /var/log/maillog",
      
      # Clear shell history
      "history -c",
      "cat /dev/null > ~/.bash_history",
      "rm -f /root/.ssh/authorized_keys",
      
      # Clear network-specific state for template use
      "rm -f /etc/machine-id",
      "touch /etc/machine-id",
      
      # Configure cloud-init for first boot network setup
      "if [ -f /etc/cloud/cloud.cfg ]; then",
      "  sed -i '/ssh_pwauth/c\\ssh_pwauth: true' /etc/cloud/cloud.cfg",
      "fi",
      
      "echo 'Template cleanup completed - ready for deployment'"
    ]
  }
}
