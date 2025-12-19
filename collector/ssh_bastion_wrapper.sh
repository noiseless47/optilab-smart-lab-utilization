#!/bin/bash

################################################################################
# OptiLab SSH Bastion Wrapper
# Purpose: Wrapper script for SSH/SCP commands that automatically route through bastion host
# Usage: 
#   ./ssh_bastion_wrapper.sh ssh <target_user>@<target_host> <command>
#   ./ssh_bastion_wrapper.sh scp <source> <target_user>@<target_host>:<dest>
################################################################################

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bastion configuration
if [[ -f "$SCRIPT_DIR/bastion_config.sh" ]]; then
    source "$SCRIPT_DIR/bastion_config.sh"
else
    echo "Error: bastion_config.sh not found" >&2
    exit 1
fi

# Command to execute
COMMAND="${1:-}"
shift

if [[ -z "$COMMAND" ]]; then
    echo "Usage: $0 <ssh|scp> [arguments...]"
    exit 1
fi

################################################################################
# SSH Wrapper Function
################################################################################

ssh_via_bastion() {
    local target_user="${1%%@*}"
    local target_host="${1##*@}"
    local ssh_command="${2:-}"
    local target_key="${TARGET_KEY:-$HOME/.ssh/id_rsa}"
    local target_port="${TARGET_PORT:-22}"
    
    if is_bastion_enabled; then
        log_bastion_info "Connecting to $target_host via bastion ${BASTION_HOST}"
        
        # Use ProxyJump to route through bastion
        ssh $BASTION_SSH_OPTIONS \
            -i "$target_key" \
            -p "$target_port" \
            -J "${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}" \
            "${target_user}@${target_host}" \
            "$ssh_command"
    else
        # Direct connection (bastion disabled)
        ssh $BASTION_SSH_OPTIONS \
            -i "$target_key" \
            -p "$target_port" \
            "${target_user}@${target_host}" \
            "$ssh_command"
    fi
}

################################################################################
# SCP Wrapper Function
################################################################################

scp_via_bastion() {
    local source="$1"
    local destination="$2"
    local target_key="${TARGET_KEY:-$HOME/.ssh/id_rsa}"
    local target_port="${TARGET_PORT:-22}"
    
    if is_bastion_enabled; then
        log_bastion_info "Transferring via bastion ${BASTION_HOST}"
        
        # Use ProxyJump for SCP
        scp $BASTION_SSH_OPTIONS \
            -i "$target_key" \
            -P "$target_port" \
            -o "ProxyJump=${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}" \
            "$source" "$destination"
    else
        # Direct SCP
        scp $BASTION_SSH_OPTIONS \
            -i "$target_key" \
            -P "$target_port" \
            "$source" "$destination"
    fi
}

################################################################################
# Main Execution
################################################################################

case "$COMMAND" in
    ssh)
        if [[ $# -lt 1 ]]; then
            echo "Usage: $0 ssh <target_user>@<target_host> [command]"
            exit 1
        fi
        
        target="$1"
        shift
        command="$*"
        
        ssh_via_bastion "$target" "$command"
        ;;
        
    scp)
        if [[ $# -lt 2 ]]; then
            echo "Usage: $0 scp <source> <target_user>@<target_host>:<dest>"
            echo "       $0 scp <target_user>@<target_host>:<source> <dest>"
            exit 1
        fi
        
        source="$1"
        destination="$2"
        
        scp_via_bastion "$source" "$destination"
        ;;
        
    test)
        # Test bastion connectivity
        test_bastion_connection
        ;;
        
    config)
        # Show configuration
        show_bastion_config
        ;;
        
    *)
        echo "Error: Unknown command '$COMMAND'"
        echo "Supported commands: ssh, scp, test, config"
        exit 1
        ;;
esac
