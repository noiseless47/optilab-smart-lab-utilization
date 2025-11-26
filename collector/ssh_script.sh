#!/bin/bash

################################################################################
# OptiLab SSH Collection Script
# Purpose: Connects to target systems via SSH, transfers metrics_collector.sh,
#          executes it, and stores results in database
# Usage: ./ssh_script.sh [options]
################################################################################

set -e  # Exit on error

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-optilab}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-your_password}"

# SSH Configuration
SSH_USER="${SSH_USER:-admin}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_PORT="${SSH_PORT:-22}"
SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
SSH_OPTIONS="-o StrictHostKeyChecking=no -o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes"

# Script paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METRICS_COLLECTOR_SCRIPT="$SCRIPT_DIR/metrics_collector.sh"
REMOTE_SCRIPT_PATH="/tmp/metrics_collector.sh"

# Collection mode
COLLECTION_MODE="${COLLECTION_MODE:-all}"  # all|single|lab|dept
TARGET_IP="${TARGET_IP:-}"
LAB_ID="${LAB_ID:-}"
DEPT_ID="${DEPT_ID:-}"

# Message Queue Configuration (for future integration)
QUEUE_ENABLED="${QUEUE_ENABLED:-false}"
QUEUE_HOST="${QUEUE_HOST:-localhost}"
QUEUE_PORT="${QUEUE_PORT:-5672}"
QUEUE_NAME="${QUEUE_NAME:-metrics_queue}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [options]

Collection Modes:
    -a, --all              Collect from all active systems
    -s, --single IP        Collect from single system
    -l, --lab LAB_ID       Collect from all systems in a lab
    -d, --dept DEPT_ID     Collect from all systems in a department

SSH Options:
    -u, --user USER        SSH username (default: admin)
    -k, --key PATH         SSH private key path (default: ~/.ssh/id_rsa)
    -p, --port PORT        SSH port (default: 22)

Database Options:
    --db-host HOST         Database host (default: localhost)
    --db-port PORT         Database port (default: 5432)
    --db-name NAME         Database name (default: optilab)
    --db-user USER         Database user (default: postgres)
    --db-password PASS     Database password

Message Queue Options:
    --queue-enabled        Enable message queue integration
    --queue-host HOST      Queue host (default: localhost)
    --queue-port PORT      Queue port (default: 5672)

Examples:
    # Collect from all systems
    $0 --all

    # Collect from single system
    $0 --single 10.30.5.10

    # Collect from specific lab
    $0 --lab 5

    # Collect from department with custom SSH key
    $0 --dept 1 --user labuser --key /path/to/key
    
    # Enable message queue
    $0 --all --queue-enabled

Environment Variables:
    DB_PASSWORD, SSH_USER, SSH_KEY, QUEUE_ENABLED, etc.
EOF
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -a|--all)
                COLLECTION_MODE="all"
                shift
                ;;
            -s|--single)
                COLLECTION_MODE="single"
                TARGET_IP="$2"
                shift 2
                ;;
            -l|--lab)
                COLLECTION_MODE="lab"
                LAB_ID="$2"
                shift 2
                ;;
            -d|--dept)
                COLLECTION_MODE="dept"
                DEPT_ID="$2"
                shift 2
                ;;
            -u|--user)
                SSH_USER="$2"
                shift 2
                ;;
            -k|--key)
                SSH_KEY="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            --db-host)
                DB_HOST="$2"
                shift 2
                ;;
            --db-port)
                DB_PORT="$2"
                shift 2
                ;;
            --db-name)
                DB_NAME="$2"
                shift 2
                ;;
            --db-user)
                DB_USER="$2"
                shift 2
                ;;
            --db-password)
                DB_PASSWORD="$2"
                shift 2
                ;;
            --queue-enabled)
                QUEUE_ENABLED="true"
                shift
                ;;
            --queue-host)
                QUEUE_HOST="$2"
                shift 2
                ;;
            --queue-port)
                QUEUE_PORT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v ssh &> /dev/null; then
        missing_deps+=("ssh")
    fi
    
    if ! command -v scp &> /dev/null; then
        missing_deps+=("scp")
    fi
    
    if ! command -v psql &> /dev/null; then
        missing_deps+=("postgresql-client (psql)")
    fi
    
    if [[ ! -f "$METRICS_COLLECTOR_SCRIPT" ]]; then
        log_error "Metrics collector script not found: $METRICS_COLLECTOR_SCRIPT"
        exit 1
    fi
    
    if [[ ! -f "$SSH_KEY" ]]; then
        log_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies:"
        printf '  - %s\n' "${missing_deps[@]}"
        exit 1
    fi
}

# Execute SQL query
exec_sql() {
    local query="$1"
    PGPASSWORD="$DB_PASSWORD" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "$query" 2>&1
}

# Get list of target systems based on collection mode
get_target_systems() {
    local query=""
    
    case "$COLLECTION_MODE" in
        all)
            query="SELECT system_id, hostname, ip_address FROM systems WHERE status = 'active' OR status = 'discovered';"
            ;;
        single)
            if [[ -z "$TARGET_IP" ]]; then
                log_error "Target IP not specified for single mode"
                exit 1
            fi
            query="SELECT system_id, hostname, ip_address FROM systems WHERE ip_address = '$TARGET_IP';"
            ;;
        lab)
            if [[ -z "$LAB_ID" ]]; then
                log_error "Lab ID not specified for lab mode"
                exit 1
            fi
            query="SELECT system_id, hostname, ip_address FROM systems WHERE lab_id = $LAB_ID AND (status = 'active' OR status = 'discovered');"
            ;;
        dept)
            if [[ -z "$DEPT_ID" ]]; then
                log_error "Department ID not specified for dept mode"
                exit 1
            fi
            query="SELECT system_id, hostname, ip_address FROM systems WHERE dept_id = $DEPT_ID AND (status = 'active' OR status = 'discovered');"
            ;;
        *)
            log_error "Invalid collection mode: $COLLECTION_MODE"
            exit 1
            ;;
    esac
    
    local result=$(exec_sql "$query")
    echo "$result"
}

# Test SSH connection to a system
test_ssh_connection() {
    local ip="$1"
    
    if ssh $SSH_OPTIONS -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${ip}" "exit" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Collect metrics from a single system
collect_from_system() {
    local system_id="$1"
    local hostname="$2"
    local ip="$3"
    
    log_info "Collecting from: $hostname ($ip) [ID: $system_id]"
    
    # Test SSH connection
    if ! test_ssh_connection "$ip"; then
        log_warning "  └─ SSH connection failed, skipping"
        update_system_status "$system_id" "offline"
        return 1
    fi
    
    # Transfer metrics collector script
    log_info "  └─ Transferring collector script..."
    if ! scp $SSH_OPTIONS -i "$SSH_KEY" -P "$SSH_PORT" "$METRICS_COLLECTOR_SCRIPT" "${SSH_USER}@${ip}:${REMOTE_SCRIPT_PATH}" &>/dev/null; then
        log_error "  └─ Failed to transfer script"
        return 1
    fi
    
    # Execute collector script and capture output
    log_info "  └─ Executing collector script..."
    local metrics_output=$(ssh $SSH_OPTIONS -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${ip}" "bash $REMOTE_SCRIPT_PATH" 2>/dev/null)
    
    if [[ -z "$metrics_output" ]]; then
        log_error "  └─ Failed to collect metrics (empty output)"
        return 1
    fi
    
    # Cleanup remote script
    ssh $SSH_OPTIONS -i "$SSH_KEY" -p "$SSH_PORT" "${SSH_USER}@${ip}" "rm -f $REMOTE_SCRIPT_PATH" &>/dev/null || true
    
    # Parse JSON output
    if ! echo "$metrics_output" | jq . &>/dev/null; then
        log_error "  └─ Invalid JSON output"
        return 1
    fi
    
    # Send to message queue if enabled
    if [[ "$QUEUE_ENABLED" == "true" ]]; then
        send_to_queue "$system_id" "$metrics_output"
    fi
    
    # Insert metrics into database
    insert_metrics "$system_id" "$metrics_output"
    
    # Update system status to active
    update_system_status "$system_id" "active"
    
    log_success "  └─ Metrics collected successfully"
    return 0
}

# Insert metrics into database
insert_metrics() {
    local system_id="$1"
    local json_data="$2"
    
    # Parse JSON fields
    local cpu_percent=$(echo "$json_data" | jq -r '.cpu_percent // "NULL"')
    local cpu_temp=$(echo "$json_data" | jq -r '.cpu_temperature // "NULL"')
    local ram_percent=$(echo "$json_data" | jq -r '.ram_percent // "NULL"')
    local disk_percent=$(echo "$json_data" | jq -r '.disk_percent // "NULL"')
    local disk_read=$(echo "$json_data" | jq -r '.disk_read_mbps // "NULL"')
    local disk_write=$(echo "$json_data" | jq -r '.disk_write_mbps // "NULL"')
    local net_sent=$(echo "$json_data" | jq -r '.network_sent_mbps // "NULL"')
    local net_recv=$(echo "$json_data" | jq -r '.network_recv_mbps // "NULL"')
    local gpu_percent=$(echo "$json_data" | jq -r '.gpu_percent // "NULL"')
    local gpu_mem=$(echo "$json_data" | jq -r '.gpu_memory_used_gb // "NULL"')
    local gpu_temp=$(echo "$json_data" | jq -r '.gpu_temperature // "NULL"')
    local uptime=$(echo "$json_data" | jq -r '.uptime_seconds // "NULL"')
    local logged_users=$(echo "$json_data" | jq -r '.logged_in_users // "NULL"')
    
    # Handle null values for PostgreSQL
    [[ "$cpu_percent" == "null" ]] && cpu_percent="NULL"
    [[ "$cpu_temp" == "null" ]] && cpu_temp="NULL"
    [[ "$ram_percent" == "null" ]] && ram_percent="NULL"
    [[ "$disk_percent" == "null" ]] && disk_percent="NULL"
    [[ "$disk_read" == "null" ]] && disk_read="NULL"
    [[ "$disk_write" == "null" ]] && disk_write="NULL"
    [[ "$net_sent" == "null" ]] && net_sent="NULL"
    [[ "$net_recv" == "null" ]] && net_recv="NULL"
    [[ "$gpu_percent" == "null" ]] && gpu_percent="NULL"
    [[ "$gpu_mem" == "null" ]] && gpu_mem="NULL"
    [[ "$gpu_temp" == "null" ]] && gpu_temp="NULL"
    [[ "$uptime" == "null" ]] && uptime="NULL"
    [[ "$logged_users" == "null" ]] && logged_users="NULL"
    
    # Insert query
    local query="INSERT INTO metrics (
        system_id, timestamp, 
        cpu_percent, cpu_temperature,
        ram_percent,
        disk_percent, disk_read_mbps, disk_write_mbps,
        network_sent_mbps, network_recv_mbps,
        gpu_percent, gpu_memory_used_gb, gpu_temperature,
        uptime_seconds, logged_in_users
    ) VALUES (
        $system_id, NOW(),
        $cpu_percent, $cpu_temp,
        $ram_percent,
        $disk_percent, $disk_read, $disk_write,
        $net_sent, $net_recv,
        $gpu_percent, $gpu_mem, $gpu_temp,
        $uptime, $logged_users
    );"
    
    if exec_sql "$query" &>/dev/null; then
        log_info "  └─ Metrics stored in database"
    else
        log_error "  └─ Failed to insert metrics into database"
        return 1
    fi
}

# Update system status
update_system_status() {
    local system_id="$1"
    local status="$2"
    
    local query="UPDATE systems SET status = '$status', updated_at = NOW() WHERE system_id = $system_id;"
    exec_sql "$query" &>/dev/null
}

# Send metrics to message queue (RabbitMQ/Redis)
send_to_queue() {
    local system_id="$1"
    local metrics_json="$2"
    
    # Create message with metadata
    local message=$(jq -n \
        --arg sid "$system_id" \
        --argjson metrics "$metrics_json" \
        '{system_id: $sid, metrics: $metrics, collected_at: (now | todate)}')
    
    # Send to queue (simplified - needs actual queue client)
    # This is a placeholder for future implementation
    log_info "  └─ Message queued for processing"
    
    # Example with curl to RabbitMQ HTTP API (requires management plugin)
    # curl -u guest:guest -H "Content-Type: application/json" -X POST \
    #   -d "{\"properties\":{},\"routing_key\":\"$QUEUE_NAME\",\"payload\":\"$message\",\"payload_encoding\":\"string\"}" \
    #   "http://$QUEUE_HOST:15672/api/exchanges/%2F/amq.default/publish"
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "=== OptiLab SSH Metrics Collection ==="
    log_info "Mode: $COLLECTION_MODE"
    log_info "SSH User: $SSH_USER"
    log_info "SSH Key: $SSH_KEY"
    log_info "Message Queue: $([[ "$QUEUE_ENABLED" == "true" ]] && echo "Enabled" || echo "Disabled")"
    echo
    
    # Check dependencies
    check_dependencies
    
    # Get target systems
    log_info "Fetching target systems from database..."
    local systems=$(get_target_systems)
    
    if [[ -z "$systems" ]]; then
        log_warning "No systems found for collection"
        exit 0
    fi
    
    local total_systems=$(echo "$systems" | wc -l | tr -d ' ')
    log_info "Found $total_systems system(s) to collect from"
    echo
    
    # Collect metrics from each system
    local success_count=0
    local fail_count=0
    
    while IFS='|' read -r system_id hostname ip; do
        # Trim whitespace
        system_id=$(echo "$system_id" | tr -d ' ')
        hostname=$(echo "$hostname" | tr -d ' ')
        ip=$(echo "$ip" | tr -d ' ')
        
        if collect_from_system "$system_id" "$hostname" "$ip"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
        echo
    done <<< "$systems"
    
    # Summary
    log_success "=== Collection Complete ==="
    log_info "Total: $total_systems | Success: $success_count | Failed: $fail_count"
}

# Parse arguments
parse_args "$@"

# Run main
main
