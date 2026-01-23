#!/bin/bash

################################################################################
# OptiLab Bastion Host Setup Script
# Purpose: Configure this system as a bastion/jump host
# Usage: sudo ./bastion_host_setup.sh
################################################################################

set -e

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root (use sudo)" 
   exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=========================================="
echo "  OptiLab Bastion Host Setup"
echo "=========================================="
echo

# Get configuration from user
read -p "Enter the bastion username (default: jump): " BASTION_USER
BASTION_USER=${BASTION_USER:-jump}

read -p "Enter SSH port (default: 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

read -p "Enter allowed collector server IP: " COLLECTOR_IP
if [[ -z "$COLLECTOR_IP" ]]; then
    log_error "Collector IP is required!"
    exit 1
fi

read -p "Enter target network CIDR (e.g., 10.30.0.0/16): " TARGET_NETWORK
if [[ -z "$TARGET_NETWORK" ]]; then
    log_error "Target network CIDR is required!"
    exit 1
fi

echo
log_info "Configuration Summary:"
echo "  Bastion User: $BASTION_USER"
echo "  SSH Port: $SSH_PORT"
echo "  Allowed Collector: $COLLECTOR_IP"
echo "  Target Network: $TARGET_NETWORK"
echo
read -p "Continue with this configuration? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "Setup cancelled."
    exit 0
fi

################################################################################
# 1. Install Required Packages (if not already installed)
################################################################################

log_info "Step 1: Installing required packages (if needed)..."
apt-get install -y openssh-server ufw fail2ban auditd 2>/dev/null || log_warning "Some packages may already be installed"
log_success "Required packages checked"

################################################################################
# 2. Create Bastion User
################################################################################

log_info "Step 2: Creating bastion user..."
if id "$BASTION_USER" &>/dev/null; then
    log_warning "User $BASTION_USER already exists, skipping creation"
else
    useradd -m -s /bin/bash "$BASTION_USER"
    mkdir -p /home/$BASTION_USER/.ssh
    chmod 700 /home/$BASTION_USER/.ssh
    touch /home/$BASTION_USER/.ssh/authorized_keys
    chmod 600 /home/$BASTION_USER/.ssh/authorized_keys
    chown -R $BASTION_USER:$BASTION_USER /home/$BASTION_USER/.ssh
    log_success "User $BASTION_USER created"
fi

################################################################################
# 3. Configure SSH (Hardened)
################################################################################

log_info "Step 3: Configuring SSH for security..."

# Backup original config
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)

# Apply hardened SSH configuration
cat > /etc/ssh/sshd_config.d/bastion.conf << EOF
# OptiLab Bastion Host SSH Configuration
# Generated: $(date)

# Port configuration
Port $SSH_PORT

# Authentication
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes

# Only allow specific user
AllowUsers $BASTION_USER

# Security hardening
Protocol 2
HostKey /etc/ssh/ssh_host_ed25519_key
HostKey /etc/ssh/ssh_host_rsa_key

# Key exchange algorithms
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256

# Connection settings
MaxAuthTries 3
MaxSessions 10
ClientAliveInterval 300
ClientAliveCountMax 2
LoginGraceTime 60

# Logging
LogLevel VERBOSE
SyslogFacility AUTH

# Disable forwarding (can enable if needed)
AllowTcpForwarding yes
AllowStreamLocalForwarding no
GatewayPorts no
PermitTunnel no

# Disable unused features
X11Forwarding no
PrintMotd no
PrintLastLog yes
TCPKeepAlive yes
Compression no

# Banner
Banner /etc/ssh/bastion_banner
EOF

# Create banner
cat > /etc/ssh/bastion_banner << 'EOF'
***************************************************************************
                    AUTHORIZED ACCESS ONLY
        This is an OptiLab Bastion Host (Jump Server)
        
        All connections are monitored and logged.
        Unauthorized access attempts will be prosecuted.
        
        For support, contact your system administrator.
***************************************************************************
EOF

log_success "SSH configured"

################################################################################
# 4. Configure Firewall (UFW)
################################################################################

log_info "Step 4: Configuring firewall..."

# Reset UFW
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow SSH from collector only
ufw allow from $COLLECTOR_IP to any port $SSH_PORT proto tcp comment "Collector to Bastion SSH"

# Allow SSH to target network
ufw allow out to $TARGET_NETWORK port 22 proto tcp comment "Bastion to Target SSH"

# Enable firewall
ufw --force enable

log_success "Firewall configured"

################################################################################
# 5. Configure Fail2Ban
################################################################################

log_info "Step 5: Configuring fail2ban..."

cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
destemail = root@localhost
sendername = Fail2Ban

[sshd]
enabled = true
port = $SSH_PORT
logpath = /var/log/auth.log
maxretry = 3
bantime = 7200
EOF

systemctl enable fail2ban
systemctl restart fail2ban

log_success "Fail2ban configured"

################################################################################
# 6. Configure Audit Logging
################################################################################

log_info "Step 6: Configuring audit logging..."

cat > /etc/audit/rules.d/bastion.rules << EOF
# OptiLab Bastion Host Audit Rules

# Monitor SSH connections
-w /var/log/auth.log -p wa -k ssh_access
-w /etc/ssh/sshd_config -p wa -k ssh_config

# Monitor user authentication
-w /etc/passwd -p wa -k passwd_changes
-w /etc/shadow -p wa -k shadow_changes
-w /etc/sudoers -p wa -k sudoers_changes

# Monitor bastion user activity
-w /home/$BASTION_USER/.ssh/authorized_keys -p wa -k bastion_keys
EOF

auditctl -R /etc/audit/rules.d/bastion.rules
systemctl enable auditd
systemctl restart auditd

log_success "Audit logging configured"

################################################################################
# 7. Create SSH Keys Directory for Forwarding
################################################################################

log_info "Step 7: Setting up SSH key forwarding..."

# Allow bastion user to forward SSH keys to targets
mkdir -p /home/$BASTION_USER/.ssh
cat > /home/$BASTION_USER/.ssh/config << EOF
# SSH configuration for forwarding to targets
Host 10.30.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host 10.31.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3

Host 10.32.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    ServerAliveInterval 60
    ServerAliveCountMax 3
EOF

chown -R $BASTION_USER:$BASTION_USER /home/$BASTION_USER/.ssh
chmod 600 /home/$BASTION_USER/.ssh/config

log_success "SSH forwarding configured"

################################################################################
# 8. Restart SSH Service
################################################################################

log_info "Step 8: Restarting SSH service..."
systemctl restart ssh || systemctl restart sshd
log_success "SSH service restarted"

################################################################################
# 9. Display Summary and Next Steps
################################################################################

echo
echo "=========================================="
log_success "Bastion Host Setup Complete!"
echo "=========================================="
echo
echo "📋 CONFIGURATION SUMMARY:"
echo "  • Bastion User: $BASTION_USER"
echo "  • SSH Port: $SSH_PORT"
echo "  • Allowed Collector: $COLLECTOR_IP"
echo "  • Target Network: $TARGET_NETWORK"
echo
echo "🔑 NEXT STEPS:"
echo
echo "1. Add collector's public key to bastion:"
echo "   From collector server, run:"
echo "   ssh-copy-id -i ~/.ssh/bastion_key.pub -p $SSH_PORT $BASTION_USER@$(hostname -I | awk '{print $1}')"
echo
echo "2. Add target SSH key to bastion user:"
echo "   sudo -u $BASTION_USER ssh-keygen -t ed25519 -f /home/$BASTION_USER/.ssh/target_key"
echo "   Then copy this key to all target systems"
echo
echo "3. Test bastion connection from collector:"
echo "   ssh -i ~/.ssh/bastion_key -p $SSH_PORT $BASTION_USER@$(hostname -I | awk '{print $1}')"
echo
echo "4. Test ProxyJump to target:"
echo "   ssh -J $BASTION_USER@$(hostname -I | awk '{print $1}'):$SSH_PORT admin@<target-ip> hostname"
echo
echo "5. Update OptiLab bastion_config.sh:"
echo "   BASTION_HOST=\"$(hostname -I | awk '{print $1}')\""
echo "   BASTION_PORT=\"$SSH_PORT\""
echo "   BASTION_USER=\"$BASTION_USER\""
echo
echo "📊 MONITORING:"
echo "  • View SSH logs: tail -f /var/log/auth.log"
echo "  • View audit logs: ausearch -k ssh_access"
echo "  • View fail2ban: fail2ban-client status sshd"
echo "  • View firewall: ufw status verbose"
echo
echo "⚠️  IMPORTANT SECURITY NOTES:"
echo "  • SSH password authentication is DISABLED"
echo "  • Only key-based authentication is allowed"
echo "  • Only $BASTION_USER can login"
echo "  • All connections are logged and audited"
echo "  • Firewall only allows collector IP: $COLLECTOR_IP"
echo
echo "🔒 Configuration files backed up to:"
echo "  /etc/ssh/sshd_config.backup.*"
echo
echo "=========================================="

# Create setup info file
cat > /root/bastion_setup_info.txt << EOF
OptiLab Bastion Host Setup Information
Generated: $(date)

Configuration:
--------------
Bastion User: $BASTION_USER
SSH Port: $SSH_PORT
Allowed Collector IP: $COLLECTOR_IP
Target Network: $TARGET_NETWORK
Server IP: $(hostname -I | awk '{print $1}')
Hostname: $(hostname)

SSH Key Locations:
------------------
Authorized keys: /home/$BASTION_USER/.ssh/authorized_keys
Target key: /home/$BASTION_USER/.ssh/target_key (create this)

Configuration Files:
--------------------
SSH Config: /etc/ssh/sshd_config.d/bastion.conf
Firewall: /etc/ufw/
Fail2ban: /etc/fail2ban/jail.local
Audit: /etc/audit/rules.d/bastion.rules

Commands:
---------
View SSH logs: tail -f /var/log/auth.log
View audit logs: ausearch -k ssh_access
Check fail2ban: fail2ban-client status sshd
Check firewall: ufw status verbose
Test connection: ssh -p $SSH_PORT $BASTION_USER@localhost

Next Steps:
-----------
1. Add collector's public key
2. Generate and distribute target keys
3. Test connections
4. Update collector's bastion_config.sh
EOF

log_success "Setup information saved to /root/bastion_setup_info.txt"

exit 0
