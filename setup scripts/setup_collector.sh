#!/bin/bash

################################################################################
# OptiLab Collector Setup Script
# Purpose: Copy OptiLab and SSH keys from bastion to one or more collectors
# Usage: ./setup_collector.sh [collector_ips_csv] [collector_user] [bastion_ip]
# Example: ./setup_collector.sh 192.168.0.2,192.168.0.3 rvce 192.168.0.1
################################################################################

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$REPO_ROOT")"

COLLECTOR_IPS_INPUT="${1:-192.168.0.2,192.168.0.3}"
COLLECTOR_USER="${2:-rvce}"
BASTION_IP="${3:-192.168.0.1}"

IFS=',' read -ra COLLECTOR_IPS_RAW <<< "$COLLECTOR_IPS_INPUT"
COLLECTOR_IPS=()
for ip in "${COLLECTOR_IPS_RAW[@]}"; do
    cleaned_ip="${ip//[[:space:]]/}"
    if [[ -n "$cleaned_ip" ]]; then
        COLLECTOR_IPS+=("$cleaned_ip")
    fi
done

if [[ ${#COLLECTOR_IPS[@]} -eq 0 ]]; then
    echo "No collector IPs provided."
    exit 1
fi

if ! compgen -G "$HOME/.ssh/bastion_key*" > /dev/null; then
    echo "Missing bastion key files in $HOME/.ssh (expected bastion_key and bastion_key.pub)."
    exit 1
fi

if ! sudo test -f "/home/jump/.ssh/target_key.pub"; then
    echo "Missing /home/jump/.ssh/target_key.pub. Generate target key on bastion first."
    exit 1
fi

if ! sudo test -f "/home/jump/.ssh/target_key"; then
    echo "Missing /home/jump/.ssh/target_key. Generate target key on bastion first."
    exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "=========================================="
echo "  OptiLab Collector Setup"
echo "=========================================="
echo
log_info "Collectors: ${COLLECTOR_IPS_INPUT}"
log_info "Collector user: ${COLLECTOR_USER}"
log_info "Bastion IP: ${BASTION_IP}"
log_info "Project path: ${REPO_ROOT}"
echo

setup_single_collector() {
    local collector_ip="$1"

    log_info "Setting up collector ${COLLECTOR_USER}@${collector_ip}"

    if ! ping -c 1 -W 2 "$collector_ip" &>/dev/null; then
        log_error "Cannot reach ${collector_ip}. Skipping this collector."
        return 1
    fi

    if ! ssh "${COLLECTOR_USER}@${collector_ip}" "mkdir -p ~/.ssh && chmod 700 ~/.ssh"; then
        log_error "Failed to prepare ~/.ssh on ${collector_ip}."
        return 1
    fi

    log_info "Copying bastion keys to ${collector_ip}"
    if ! scp "$HOME"/.ssh/bastion_key* "${COLLECTOR_USER}@${collector_ip}:~/.ssh/"; then
        log_error "Failed to copy bastion keys to ${collector_ip}."
        return 1
    fi

    if ! ssh "${COLLECTOR_USER}@${collector_ip}" "chmod 600 ~/.ssh/bastion_key ~/.ssh/bastion_key.pub"; then
        log_warning "Could not set key permissions on ${collector_ip}."
    fi

    log_info "Copying OptiLab project to ${collector_ip}"
    if ! scp -r "$REPO_ROOT" "${COLLECTOR_USER}@${collector_ip}:~/"; then
        log_error "Failed to copy project to ${collector_ip}."
        return 1
    fi

    log_info "Copying target SSH key pair to ${collector_ip}"
    if ! sudo cat /home/jump/.ssh/target_key | ssh "${COLLECTOR_USER}@${collector_ip}" "cat > ~/.ssh/target_key"; then
        log_error "Failed to copy target_key to ${collector_ip}."
        return 1
    fi

    if ! sudo cat /home/jump/.ssh/target_key.pub | ssh "${COLLECTOR_USER}@${collector_ip}" "cat > ~/.ssh/target_key.pub"; then
        log_error "Failed to copy target_key.pub to ${collector_ip}."
        return 1
    fi

    if ! ssh "${COLLECTOR_USER}@${collector_ip}" "chmod 600 ~/.ssh/target_key && chmod 644 ~/.ssh/target_key.pub && cp ~/.ssh/target_key.pub ~/target_key.pub"; then
        log_error "Failed to apply target key permissions on ${collector_ip}."
        return 1
    fi

    log_info "Creating setup instructions on ${collector_ip}"
    if ! ssh "${COLLECTOR_USER}@${collector_ip}" "cat > ~/SETUP_INSTRUCTIONS.txt" << EOF
OptiLab Collector Setup Instructions
====================================

1. Verify bastion keys are present:
    ls -lh ~/.ssh/bastion_key* ~/.ssh/target_key*

2. Set correct permissions:
    chmod 600 ~/.ssh/bastion_key ~/.ssh/target_key
    chmod 644 ~/.ssh/bastion_key.pub ~/.ssh/target_key.pub

3. Test bastion connection:
   ssh -i ~/.ssh/bastion_key jump@${BASTION_IP} "echo 'Bastion works!'"

4. Configure OptiLab:
   cd ~/${PROJECT_NAME}/collector
   nano bastion_config.sh

   Ensure these settings:
   BASTION_ENABLED="true"
   BASTION_HOST="${BASTION_IP}"
   BASTION_USER="jump"
   BASTION_KEY="\$HOME/.ssh/bastion_key"

5. Test bastion config:
   ./bastion_config.sh

6. Add target keys to lab computers:
   The public key is in ~/target_key.pub

   On each target system, run:
   mkdir -p ~/.ssh && echo "PASTE_KEY_HERE" >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys

7. Test end-to-end connection:
    ssh -i ~/.ssh/bastion_key -i ~/.ssh/target_key -J jump@${BASTION_IP}:22 <target-user>@<target-ip> "hostname"

8. Run metrics collection:
   cd ~/${PROJECT_NAME}/collector
    SSH_USER=<target-user> SSH_KEY=~/.ssh/target_key ./ssh_script.sh --single <target-ip>
    SSH_USER=<target-user> SSH_KEY=~/.ssh/target_key ./ssh_script.sh --all

Target Public Key:
------------------
EOF
    then
        log_error "Failed to create SETUP_INSTRUCTIONS.txt on ${collector_ip}."
        return 1
    fi

    if ! sudo cat /home/jump/.ssh/target_key.pub | ssh "${COLLECTOR_USER}@${collector_ip}" "cat >> ~/SETUP_INSTRUCTIONS.txt"; then
        log_error "Failed to append target public key in instructions on ${collector_ip}."
        return 1
    fi

    log_success "Collector ${collector_ip} configured"
    return 0
}

SUCCESS_COLLECTORS=()
FAILED_COLLECTORS=()

for collector_ip in "${COLLECTOR_IPS[@]}"; do
    echo
    if setup_single_collector "$collector_ip"; then
        SUCCESS_COLLECTORS+=("$collector_ip")
    else
        FAILED_COLLECTORS+=("$collector_ip")
    fi
done

echo
echo "=========================================="
echo "Collector setup summary"
echo "=========================================="

if [[ ${#SUCCESS_COLLECTORS[@]} -gt 0 ]]; then
    log_success "Configured collectors: ${SUCCESS_COLLECTORS[*]}"
fi

if [[ ${#FAILED_COLLECTORS[@]} -gt 0 ]]; then
    log_error "Failed collectors: ${FAILED_COLLECTORS[*]}"
fi

echo
if [[ ${#SUCCESS_COLLECTORS[@]} -gt 0 ]]; then
    echo "For each configured collector, next steps are:"
    echo "  1. ssh <collector_user>@<collector_ip>"
    echo "  2. cat ~/SETUP_INSTRUCTIONS.txt"
    echo "  3. cd ~/${PROJECT_NAME}/collector && ./ssh_script.sh --all"
fi

if [[ ${#FAILED_COLLECTORS[@]} -gt 0 ]]; then
    exit 1
fi

exit 0
