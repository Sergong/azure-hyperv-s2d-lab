#!/bin/bash
# Post-installation script for AlmaLinux VMs
# Nested Virtualization Lab Setup
# This script runs after the VM has been provisioned and is accessible via SSH

set -euo pipefail  # Exit on error, undefined variables, pipe failures

LOG_FILE="/var/log/postinstall.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "AlmaLinux VM Post-Installation Script"
echo "Started: $(date)"
echo "Hostname: $(hostname)"
echo "=========================================="

# Update system packages
echo "Updating system packages..."
dnf update -y

# Install additional useful packages for lab environment
echo "Installing additional packages..."
dnf install -y \
    git \
    vim-enhanced \
    tmux \
    htop \
    tree \
    wget \
    curl \
    net-tools \
    bind-utils \
    tcpdump \
    nmap-ncat \
    rsync \
    unzip \
    tar \
    python3 \
    python3-pip \
    ansible-core \
    sshpass \
    jq

# Install EPEL repository if not already installed
if ! rpm -q epel-release &>/dev/null; then
    echo "Installing EPEL repository..."
    dnf install -y epel-release
fi

# Configure SSH for better lab access
echo "Configuring SSH..."
SSH_CONFIG="/etc/ssh/sshd_config"

# Backup original SSH config
cp "$SSH_CONFIG" "${SSH_CONFIG}.backup"

# Configure SSH settings for lab use
sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' "$SSH_CONFIG"
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' "$SSH_CONFIG"
sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' "$SSH_CONFIG"

# Restart SSH service
systemctl restart sshd

# Configure firewall for lab environment
echo "Configuring firewall..."
firewall-cmd --permanent --add-service=ssh
firewall-cmd --permanent --add-service=http
firewall-cmd --permanent --add-service=https
firewall-cmd --permanent --add-port=8080/tcp  # Common development port
firewall-cmd --permanent --add-port=3000/tcp  # Another common development port
firewall-cmd --reload

# Create lab user if it doesn't exist (for kickstart v1 that doesn't create it)
if ! id "labuser" &>/dev/null; then
    echo "Creating lab user..."
    useradd -m -s /bin/bash labuser
    echo "labuser:labpass123!" | chpasswd
    usermod -aG wheel labuser
    
    # Configure sudo for lab user
    echo "labuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/labuser
    chmod 440 /etc/sudoers.d/labuser
fi

# Set up SSH keys directory for both root and labuser
for user in root labuser; do
    if id "$user" &>/dev/null; then
        USER_HOME=$(eval echo "~$user")
        SSH_DIR="$USER_HOME/.ssh"
        
        echo "Setting up SSH directory for $user..."
        mkdir -p "$SSH_DIR"
        chmod 700 "$SSH_DIR"
        touch "$SSH_DIR/authorized_keys"
        chmod 600 "$SSH_DIR/authorized_keys"
        chown -R "$user:$user" "$SSH_DIR"
    fi
done

# Configure Git globally
echo "Configuring Git..."
git config --system user.name "Lab User"
git config --system user.email "lab@example.com"
git config --system init.defaultBranch main
git config --system credential.helper 'cache --timeout=28800'  # 8 hours

# Install Docker (useful for lab environments)
echo "Installing Docker..."
dnf config-manager --add-repo=https://download.docker.com/linux/centos/docker-ce.repo
dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add users to docker group
usermod -aG docker root
if id "labuser" &>/dev/null; then
    usermod -aG docker labuser
fi

# Install Node.js (useful for modern development)
echo "Installing Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
dnf install -y nodejs

# Create useful aliases
echo "Setting up shell aliases..."
ALIASES_FILE="/etc/profile.d/lab_aliases.sh"
cat > "$ALIASES_FILE" << 'EOF'
# Lab environment aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'
alias h='history'
alias c='clear'
alias ..='cd ..'
alias ...='cd ../..'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps auxf'
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'
alias myip='curl -s ifconfig.me'
alias ports='netstat -tulanp'

# Docker aliases
alias dps='docker ps'
alias dpsa='docker ps -a'
alias di='docker images'
alias dlog='docker logs'
alias dexec='docker exec -it'

# Git aliases
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline'
alias gd='git diff'
EOF

chmod +x "$ALIASES_FILE"

# Set up a useful MOTD
echo "Configuring MOTD..."
cat > /etc/motd << 'EOF'
===============================================
   AlmaLinux Nested Virtualization Lab VM
===============================================
Welcome to your lab environment!

System Information:
- OS: AlmaLinux (RHEL clone)
- Purpose: Nested virtualization lab
- Docker: Installed and running
- Node.js: Installed (LTS version)

Available Users:
- root (password: alma123!)
- labuser (password: labpass123!)

Useful Commands:
- htop          # System monitor
- docker ps     # List containers
- systemctl     # Service management
- firewall-cmd  # Firewall management

Lab Setup Complete!
===============================================
EOF

# Install Python packages useful for automation
echo "Installing Python packages..."
pip3 install --upgrade pip
pip3 install \
    requests \
    paramiko \
    pyyaml \
    jinja2 \
    netaddr

# Create a sample project directory
echo "Setting up project directories..."
mkdir -p /opt/lab/{scripts,configs,logs,projects}
chown -R labuser:labuser /opt/lab
chmod -R 755 /opt/lab

# Create a sample script for testing
cat > /opt/lab/scripts/test-connectivity.sh << 'EOF'
#!/bin/bash
# Simple connectivity test script
echo "Testing network connectivity..."
ping -c 3 8.8.8.8
echo "DNS resolution test..."
nslookup google.com
echo "HTTP connectivity test..."
curl -s -o /dev/null -w "%{http_code}\n" http://httpbin.org/get
EOF

chmod +x /opt/lab/scripts/test-connectivity.sh

# Set up log rotation for lab logs
echo "Configuring log rotation..."
cat > /etc/logrotate.d/lab << 'EOF'
/opt/lab/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    notifempty
    create 0644 labuser labuser
}
EOF

# Configure timezone (if not already set)
echo "Setting timezone to UTC..."
timedatectl set-timezone UTC

# Enable chronyd for time synchronization
systemctl enable chronyd
systemctl start chronyd

# Install additional monitoring tools
echo "Installing monitoring tools..."
dnf install -y \
    iotop \
    iftop \
    nethogs \
    glances

# Create a system info script
cat > /opt/lab/scripts/sysinfo.sh << 'EOF'
#!/bin/bash
echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "OS: $(cat /etc/redhat-release)"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime)"
echo "Load Average: $(cat /proc/loadavg)"
echo "Memory: $(free -h | grep Mem)"
echo "Disk Usage: $(df -h / | tail -1)"
echo "Network Interfaces:"
ip -brief addr show
echo "Docker Status: $(systemctl is-active docker)"
echo "=== End System Information ==="
EOF

chmod +x /opt/lab/scripts/sysinfo.sh

# Final system cleanup
echo "Performing final cleanup..."
dnf clean all
rm -rf /tmp/*
rm -rf /var/tmp/*

# Update locate database
updatedb

# Generate SSH host keys if they don't exist
ssh-keygen -A

# Final status check
echo "=========================================="
echo "Post-installation script completed successfully!"
echo "Completed: $(date)"
echo "=========================================="

echo "Services status:"
systemctl is-active sshd docker chronyd

echo "Network configuration:"
ip -brief addr show

echo "Available space:"
df -h /

echo "System is ready for use!"
echo "Log file: $LOG_FILE"

# Create a completion marker
touch /opt/lab/.postinstall-completed
echo "$(date): Post-installation completed" > /opt/lab/.postinstall-completed

exit 0
