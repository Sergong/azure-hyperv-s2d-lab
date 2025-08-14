# AlmaLinux Packer Template for Hyper-V
# Builds a pre-configured AlmaLinux VM image ready for lab use

# Required plugins
packer {
  required_plugins {
    hyperv = {
      version = ">= 1.1.1"
      source  = "github.com/hashicorp/hyperv"
    }
  }
}

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
  default = "file:https://repo.almalinux.org/almalinux/9/isos/x86_64/CHECKSUM"
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
  default = "C:/Packer/Output"
}

variable "temp_path" {
  type    = string
  default = "C:/Packer/Temp"
}

variable "kickstart_version" {
  type    = string
  default = "v2"
}

variable "host_ip" {
  type    = string
  default = "192.168.1.1"  # Will be overridden by script
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
  switch_name      = "PackerExternal"
  
  # Temporary paths for Windows
  temp_path        = var.temp_path
  
  # SSH Configuration
  ssh_username     = var.ssh_username
  ssh_password     = var.ssh_password
  ssh_timeout      = "20m"
  
  # Boot Configuration
  boot_wait        = "10s"
  boot_command     = [
    "<tab>",
    " inst.ks=http://${var.host_ip}:{{ .HTTPPort }}/ks.cfg",
    " inst.text console=tty0 console=ttyS0,115200",
    " ip=dhcp",
    "<enter>"
  ]
  
  # HTTP server for kickstart
  http_directory   = "../templates/AlmaLinux/${var.kickstart_version}"
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
      "echo 'Starting Packer provisioning...'",
      "dnf update -y",
      "dnf install -y epel-release",
      "dnf install -y git vim-enhanced tmux htop tree wget curl net-tools bind-utils tcpdump nmap-ncat python3 python3-pip ansible-core"
    ]
  }
  
  # Install Docker
  provisioner "shell" {
    inline = [
      "echo 'Installing Docker...'",
      "dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo",
      "dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin",
      "systemctl enable docker",
      "systemctl start docker",
      "usermod -aG docker root",
      "usermod -aG docker labuser"
    ]
  }
  
  # Install additional development tools
  provisioner "shell" {
    inline = [
      "echo 'Installing development tools...'",
      "dnf groupinstall -y 'Development Tools'",
      "dnf install -y nodejs npm golang rust cargo"
    ]
  }
  
  # Configure useful aliases and environment
  provisioner "shell" {
    inline = [
      "echo 'Setting up shell environment...'",
      "cat > /etc/profile.d/lab_aliases.sh << 'EOF'",
      "# Lab environment aliases",
      "alias ll='ls -alF'",
      "alias la='ls -A'",
      "alias grep='grep --color=auto'",
      "alias h='history'",
      "alias c='clear'",
      "alias ..='cd ..'",
      "alias df='df -h'",
      "alias free='free -h'",
      "alias dps='docker ps'",
      "alias di='docker images'",
      "alias gs='git status'",
      "alias gc='git commit'",
      "alias gp='git push'",
      "EOF",
      "chmod +x /etc/profile.d/lab_aliases.sh"
    ]
  }
  
  # Template cleanup and finalization
  provisioner "shell" {
    inline = [
      "echo 'Finalizing template...'",
      "# Create template MOTD",
      "cat > /etc/motd << 'EOF'",
      "===============================================",
      "   AlmaLinux Lab Template (Packer-built)",
      "===============================================",
      "Template includes:",
      "- AlmaLinux 9 with latest updates",
      "- Docker + Docker Compose",
      "- Development tools (git, vim, python3, nodejs, go, rust)",
      "- Ansible core",
      "- SSH configured for lab access",
      "",
      "Default accounts:",
      "- root (password: alma123!)",
      "- labuser (password: labpass123!)",
      "",
      "Ready for nested virtualization labs!",
      "===============================================",
      "EOF",
      "",
      "# Final cleanup",
      "dnf clean all",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "# Clear histories",
      "> ~/.bash_history",
      "> /home/labuser/.bash_history || true",
      "# Prepare for template deployment",
      "> /etc/machine-id",
      "rm -f /etc/ssh/ssh_host_*",
      "touch /etc/packer-template-ready",
      "echo 'Template preparation completed'"
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
