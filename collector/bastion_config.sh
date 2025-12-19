#!/bin/bash

################################################################################
# OptiLab Bastion Host Configuration
# Purpose: Centralized configuration for bastion/jump host settings
# Usage: Source this file in other scripts: source bastion_config.sh
################################################################################

# Bastion Host Configuration
# Set these values according to your infrastructure

# Enable/disable bastion host routing
BASTION_ENABLED="${BASTION_ENABLED:-true}"

# Bastion host connection details
BASTION_HOST="${BASTION_HOST:-192.168.0.12}"
BASTION_PORT="${BASTION_PORT:-22}"
BASTION_USER="${BASTION_USER:-jump}"
BASTION_KEY="${BASTION_KEY:-$HOME/.ssh/bastion_key}"

# Bastion SSH options
BASTION_SSH_OPTIONS="${BASTION_SSH_OPTIONS:--o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes}"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

################################################################################
# Functions
################################################################################

# Log bastion info
log_bastion_info() {
    echo -e "${BLUE}[BASTION]${NC} $1"
}

# Check if bastion is enabled
is_bastion_enabled() {
    if [[ "$BASTION_ENABLED" == "true" ]]; then
        return 0
    else
        return 1
    fi
}

# Get bastion SSH options for ProxyJump
get_bastion_proxy_jump() {
    if is_bastion_enabled; then
        echo "-J ${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}"
    else
        echo ""
    fi
}

# Get complete SSH options with bastion
get_ssh_options_with_bastion() {
    local target_key="${1:-$HOME/.ssh/id_rsa}"
    local base_options="${2:-$SSH_OPTIONS}"
    
    if is_bastion_enabled; then
        # Use ProxyJump for bastion routing
        echo "$base_options -i $target_key -J ${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}"
    else
        echo "$base_options -i $target_key"
    fi
}

# Get complete SCP options with bastion
get_scp_options_with_bastion() {
    local target_key="${1:-$HOME/.ssh/id_rsa}"
    local base_options="${2:-$SSH_OPTIONS}"
    
    if is_bastion_enabled; then
        # SCP with ProxyJump
        echo "$base_options -i $target_key -o ProxyJump=${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}"
    else
        echo "$base_options -i $target_key"
    fi
}

# Test bastion host connectivity
test_bastion_connection() {
    if ! is_bastion_enabled; then
        log_bastion_info "Bastion host disabled, skipping test"
        return 0
    fi
    
    log_bastion_info "Testing connection to bastion host: ${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}"
    
    if ! [[ -f "$BASTION_KEY" ]]; then
        echo -e "${RED}[ERROR]${NC} Bastion key not found: $BASTION_KEY"
        return 1
    fi
    
    if ssh $BASTION_SSH_OPTIONS -i "$BASTION_KEY" -p "$BASTION_PORT" \
        "${BASTION_USER}@${BASTION_HOST}" "exit" 2>/dev/null; then
        echo -e "${GREEN}[SUCCESS]${NC} Bastion host connection successful"
        return 0
    else
        echo -e "${RED}[ERROR]${NC} Failed to connect to bastion host"
        return 1
    fi
}

# Display bastion configuration
show_bastion_config() {
    echo "=== Bastion Host Configuration ==="
    echo "Enabled: $BASTION_ENABLED"
    
    if is_bastion_enabled; then
        echo "Bastion Host: ${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}"
        echo "Bastion Key: $BASTION_KEY"
        echo "SSH Options: $BASTION_SSH_OPTIONS"
    else
        echo "Direct connections (no bastion)"
    fi
    echo "=================================="
}

# Export functions for use in other scripts
export -f is_bastion_enabled
export -f get_bastion_proxy_jump
export -f get_ssh_options_with_bastion
export -f get_scp_options_with_bastion
export -f test_bastion_connection
export -f show_bastion_config
export -f log_bastion_info

# If script is executed directly (not sourced), run tests
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_bastion_config
    echo
    test_bastion_connection
fi
