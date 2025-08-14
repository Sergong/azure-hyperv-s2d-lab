# AlmaLinux Packer Template for Hyper-V
# Builds a pre-configured AlmaLinux VM image ready for lab use

# Variables
variable "vm_name" {
  type    = string
  default = "almalinux-lab-template"
}

variable "vm_memory" {
  type    = number
  default = 2048
}

variable "vm_disk_size" {
  type    = number
  default = 30720  # 30GB in MB
}

variable "iso_url" {
  type    = string
  default = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-minimal.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:b21c6edc1e12ee3e5ba57451e9a5a7ff91b0f30a5a9fe62bb3c8b9c4b8c0e50a"  # Update this with actual checksum
}

variable "ssh_username" {
  type    = string
  default = "root"
}

variable "ssh_password" {
  type    = string
  default = "alma123!"
}

variable "output_directory" {
  type    = string
  default = "output-hyperv"
}

# Sources
source "hyperv-iso" "almalinux" {
  # VM Configuration
  vm_name          = var.vm_name
  generation       = 2
  memory           = var.vm_memory
  disk_size        = var.vm_disk_size
  
  # ISO Configuration
  iso_url          = var.iso_url
  iso_checksum     = var.iso_checksum
  
  # Network
  switch_name      = "Default Switch"
  
  # SSH Configuration
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "20m"
  
  # Boot Configuration
  boot_wait        = "10s"
  boot_command     = [
    "<tab>",
    " inst.ks=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ks.cfg",
    " inst.text console=tty0 console=ttyS0,115200",
    "<enter>"
  ]
  
  # HTTP server for kickstart
  http_directory   = "../templates/AlmaLinux/v2"
  http_port_min    = 8080
  http_port_max    = 8090
  
  # Output
  output_directory = var.output_directory
  
  # Shutdown
  shutdown_command = "echo '${var.ssh_password}' | sudo -S shutdown -P now"
  shutdown_timeout = "5m"
  
  # Skip creation of vagrant box
  skip_export      = false
}

# Build
build {
  name = "almalinux-lab"
  sources = ["source.hyperv-iso.almalinux"]
  
  # Wait for SSH to be available
  provisioner "shell" {
    inline = [
      "echo 'Waiting for system to be ready...'",
      "sleep 30"
    ]
  }
  
  # System updates and basic configuration
  provisioner "shell" {
    inline = [
      "dnf update -y",
      "dnf install -y epel-release",
      "dnf install -y git vim-enhanced tmux htop wget curl net-tools bind-utils tcpdump python3 python3-pip"
    ]
  }
  
  # Install Docker
  provisioner "shell" {
    inline = [
      "dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo",
      "dnf install -y docker-ce docker-ce-cli containerd.io",
      "systemctl enable docker",
      "usermod -aG docker root"
    ]
  }
  
  # Configure SSH
  provisioner "shell" {
    inline = [
      "sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config",
      "sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config",
      "systemctl restart sshd"
    ]
  }
  
  # Create lab user
  provisioner "shell" {
    inline = [
      "useradd -m -s /bin/bash labuser",
      "echo 'labuser:labpass123!' | chpasswd",
      "usermod -aG wheel labuser",
      "usermod -aG docker labuser",
      "echo 'labuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/labuser"
    ]
  }
  
  # Final cleanup and preparation
  provisioner "shell" {
    inline = [
      "dnf clean all",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "history -c",
      "echo 'AlmaLinux Lab Template - Ready for deployment' > /etc/motd"
    ]
  }
  
  # Generate image information
  post-processor "shell-local" {
    inline = [
      "echo 'AlmaLinux lab template build completed successfully'",
      "echo 'Template location: ${var.output_directory}'",
      "echo 'SSH: root/alma123! or labuser/labpass123!'",
      "echo 'Docker: Installed and configured'",
      "echo 'Ready for nested virtualization lab use'"
    ]
  }
}
