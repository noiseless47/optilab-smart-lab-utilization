#!/bin/bash

################################################################################
# OptiLab Collector Setup Script
# Purpose: Copy OptiLab and SSH keys from bastion to collector
# Usage: ./setup_collector.sh <collector_ip> <collector_user>
################################################################################

set -e

COLLECTOR_IP="${1:-192.168.0.13}"
COLLECTOR_USER="${2:-Aayush}"

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

echo "=========================================="
echo "  OptiLab Collector Setup"
echo "=========================================="
echo
log_info "Collector: ${COLLECTOR_USER}@${COLLECTOR_IP}"
echo

# Check if we can reach the collector
log_info "Testing connection to collector..."
if ! ping -c 1 -W 2 "$COLLECTOR_IP" &>/dev/null; then
    echo "Cannot reach $COLLECTOR_IP. Please check the IP and network."
    exit 1
fi
log_success "Collector is reachable"

# Copy bastion SSH keys
log_info "Copying bastion SSH keys..."
scp ~/.ssh/bastion_key* ${COLLECTOR_USER}@${COLLECTOR_IP}:~/.ssh/ || {
    echo "Failed to copy keys. Trying to create .ssh directory first..."
    ssh ${COLLECTOR_USER}@${COLLECTOR_IP} "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    scp ~/.ssh/bastion_key* ${COLLECTOR_USER}@${COLLECTOR_IP}:~/.ssh/
}
log_success "Bastion keys copied"

# Copy OptiLab project
log_info "Copying OptiLab project (this may take a moment)..."
scp -r /home/rvce/Desktop/optilab-smart-lab-utilization-main ${COLLECTOR_USER}@${COLLECTOR_IP}:~/
log_success "OptiLab project copied"

# Copy target public key for reference
log_info "Copying target public key..."
sudo cat /home/jump/.ssh/target_key.pub | ssh ${COLLECTOR_USER}@${COLLECTOR_IP} "cat > ~/target_key.pub"
log_success "Target key copied"

# Create setup instructions on collector
log_info "Creating setup instructions on collector..."
ssh ${COLLECTOR_USER}@${COLLECTOR_IP} "cat > ~/SETUP_INSTRUCTIONS.txt" << 'EOF'
OptiLab Collector Setup Instructions
=====================================

1. Verify bastion keys are present:
   ls -lh ~/.ssh/bastion_key*

2. Set correct permissions:
   chmod 600 ~/.ssh/bastion_key

3. Test bastion connection:
   ssh -i ~/.ssh/bastion_key jump@192.168.0.12 "echo 'Bastion works!'"

4. Configure OptiLab:
   cd ~/optilab-smart-lab-utilization-main/collector
   nano bastion_config.sh
   
   Ensure these settings:
   BASTION_ENABLED="true"
   BASTION_HOST="192.168.0.12"
   BASTION_USER="jump"
   BASTION_KEY="$HOME/.ssh/bastion_key"

5. Test bastion config:
   ./bastion_config.sh

6. Add target keys to lab computers (0.10 and 0.11):
   The public key is in ~/target_key.pub
   
   On each target (0.10, 0.11), run:
   mkdir -p ~/.ssh && echo "PASTE_KEY_HERE" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

7. Test end-to-end connection:
   ssh -i ~/.ssh/bastion_key -J jump@192.168.0.12:22 admin@192.168.0.10 "hostname"

8. Run metrics collection:
   cd ~/optilab-smart-lab-utilization-main/collector
   ./ssh_script.sh --single 192.168.0.10
   ./ssh_script.sh --all

Target Public Key (for 0.10 and 0.11):
---------------------------------------
EOF

# Append the actual key
sudo cat /home/jump/.ssh/target_key.pub | ssh ${COLLECTOR_USER}@${COLLECTOR_IP} "cat >> ~/SETUP_INSTRUCTIONS.txt"

log_success "Setup instructions created"

echo
echo "=========================================="
log_success "Collector Setup Complete!"
echo "=========================================="
echo
echo "Files copied to ${COLLECTOR_USER}@${COLLECTOR_IP}:"
echo "  • ~/.ssh/bastion_key*"
echo "  • ~/optilab-smart-lab-utilization-main/"
echo "  • ~/target_key.pub"
echo "  • ~/SETUP_INSTRUCTIONS.txt"
echo
echo "Next steps:"
echo "  1. SSH to collector: ssh ${COLLECTOR_USER}@${COLLECTOR_IP}"
echo "  2. Read instructions: cat ~/SETUP_INSTRUCTIONS.txt"
echo "  3. Test bastion: ssh -i ~/.ssh/bastion_key jump@192.168.0.12"
echo "  4. Add target keys to 0.10 and 0.11"
echo "  5. Run collection: cd ~/optilab-smart-lab-utilization-main/collector && ./ssh_script.sh --all"
echo
echo "Target key to add on 0.10 and 0.11:"
sudo cat /home/jump/.ssh/target_key.pub
echo
