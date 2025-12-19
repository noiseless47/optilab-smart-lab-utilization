#!/bin/bash

################################################################################
# OptiLab Network Scanner
# Purpose: Scans IP range to discover alive systems using ping
# Usage: ./scanner.sh <subnet_cidr> <dept_id> [scan_type]
# Example: ./scanner.sh 10.30.5.0/24 1 ping
################################################################################

set -e  # Exit on error

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source bastion host configuration (for SSH-based hostname resolution)
if [[ -f "$SCRIPT_DIR/bastion_config.sh" ]]; then
    source "$SCRIPT_DIR/bastion_config.sh"
else
    echo "Warning: bastion_config.sh not found, bastion host support disabled"
    BASTION_ENABLED=false
fi

# Configuration
DB_HOST="${DB_HOST:-localhost}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-optilab}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-your_password}"

# Script parameters
SUBNET_CIDR="${1:-}"
DEPT_ID="${2:-}"
SCAN_TYPE="${3:-ping}"
PING_TIMEOUT=1
PING_COUNT=2

# SSH configuration for enhanced discovery
SSH_USER="${SSH_USER:-admin}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_PORT="${SSH_PORT:-22}"

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
Usage: $0 <subnet_cidr> <dept_id> [scan_type]

Arguments:
    subnet_cidr     IP range in CIDR notation (e.g., 10.30.5.0/24)
    dept_id         Department ID from database
    scan_type       Type of scan (default: ping, options: ping|nmap|arp)

Environment Variables:
    DB_HOST         Database host (default: localhost)
    DB_PORT         Database port (default: 5432)
    DB_NAME         Database name (default: optilab)
    DB_USER         Database user (default: postgres)
    DB_PASSWORD     Database password

Examples:
    $0 10.30.5.0/24 1
    $0 192.168.1.0/24 2 nmap
    DB_PASSWORD=mypass $0 10.30.0.0/16 1 ping
EOF
    exit 1
}

# Validate inputs
validate_inputs() {
    if [[ -z "$SUBNET_CIDR" ]] || [[ -z "$DEPT_ID" ]]; then
        log_error "Missing required arguments"
        usage
    fi

    # Validate CIDR format (basic check)
    if ! [[ "$SUBNET_CIDR" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/[0-9]+$ ]]; then
        log_error "Invalid CIDR format: $SUBNET_CIDR"
        exit 1
    fi

    # Validate dept_id is numeric
    if ! [[ "$DEPT_ID" =~ ^[0-9]+$ ]]; then
        log_error "Department ID must be numeric: $DEPT_ID"
        exit 1
    fi
}

# Check if required commands are available
check_dependencies() {
    local missing_deps=()
    
    if ! command -v psql &> /dev/null; then
        missing_deps+=("postgresql-client (psql)")
    fi
    
    if ! command -v ping &> /dev/null; then
        missing_deps+=("ping")
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

# Create scan record in database
create_scan_record() {
    log_info "Creating scan record in database..."
    
    local query="INSERT INTO network_scans (dept_id, scan_type, target_range, scan_start, status)
                 VALUES ($DEPT_ID, '$SCAN_TYPE', '$SUBNET_CIDR', NOW(), 'running')
                 RETURNING scan_id;"
    
    SCAN_ID=$(exec_sql "$query" | tr -d ' ')
    
    if [[ -z "$SCAN_ID" ]] || ! [[ "$SCAN_ID" =~ ^[0-9]+$ ]]; then
        log_error "Failed to create scan record"
        exit 1
    fi
    
    log_success "Scan ID: $SCAN_ID"
}

# Update scan record with results
update_scan_record() {
    local status="$1"
    local systems_found="$2"
    local error_msg="${3:-NULL}"
    
    if [[ "$error_msg" == "NULL" ]]; then
        error_msg="NULL"
    else
        error_msg="'${error_msg//\'/\'\'}'"  # Escape single quotes
    fi
    
    local query="UPDATE network_scans 
                 SET scan_end = NOW(),
                     status = '$status',
                     systems_found = $systems_found,
                     error_message = $error_msg
                 WHERE scan_id = $SCAN_ID;"
    
    exec_sql "$query" > /dev/null
}

# Convert CIDR to IP range
cidr_to_ip_list() {
    local cidr="$1"
    local base_ip=$(echo "$cidr" | cut -d'/' -f1)
    local prefix=$(echo "$cidr" | cut -d'/' -f2)
    
    # Calculate number of hosts
    local num_hosts=$((2**(32-prefix) - 2))
    
    # Extract octets
    IFS='.' read -r -a octets <<< "$base_ip"
    
    # Convert to integer
    local ip_int=$((octets[0] * 256**3 + octets[1] * 256**2 + octets[2] * 256 + octets[3]))
    
    # Network address (first IP + 1 to skip network address)
    local start_ip=$((ip_int + 1))
    local end_ip=$((start_ip + num_hosts - 1))
    
    # Generate IP list
    for ((i=start_ip; i<=end_ip; i++)); do
        local o1=$((i / 256**3 % 256))
        local o2=$((i / 256**2 % 256))
        local o3=$((i / 256 % 256))
        local o4=$((i % 256))
        echo "$o1.$o2.$o3.$o4"
    done
}

# Ping scan implementation
ping_scan() {
    log_info "Starting ping scan on $SUBNET_CIDR"
    log_info "Generating IP addresses..."
    
    local alive_systems=0
    local total_ips=0
    local alive_ips_file="/tmp/optilab_scan_${SCAN_ID}_alive.txt"
    
    > "$alive_ips_file"  # Clear file
    
    # Get IP list
    local ip_list=($(cidr_to_ip_list "$SUBNET_CIDR"))
    total_ips=${#ip_list[@]}
    
    log_info "Scanning $total_ips IP addresses..."
    
    # Progress counter
    local count=0
    local progress_interval=$((total_ips / 10))
    [[ $progress_interval -lt 1 ]] && progress_interval=1
    
    # Scan each IP
    for ip in "${ip_list[@]}"; do
        count=$((count + 1))
        
        # Show progress every N hosts
        if (( count % progress_interval == 0 )); then
            log_info "Progress: $count/$total_ips (Found: $alive_systems alive)"
        fi
        
        # Ping the IP (suppress output)
        if ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$ip" &> /dev/null; then
            alive_systems=$((alive_systems + 1))
            echo "$ip" >> "$alive_ips_file"
            log_success "✓ $ip is alive"
            
            # Try to get hostname (non-blocking)
            hostname=$(get_hostname_for_ip "$ip")
            
            # Insert/update system in database (discovered state)
            insert_discovered_system "$ip" "$hostname"
        fi
    done
    
    log_success "Scan complete: $alive_systems/$total_ips systems alive"
    
    # Display alive systems
    if [[ $alive_systems -gt 0 ]]; then
        log_info "Alive systems:"
        cat "$alive_ips_file"
    fi
    
    echo "$alive_systems"
}

# Get hostname for IP address (tries DNS and SSH via bastion)
get_hostname_for_ip() {
    local ip="$1"
    local hostname="unknown"
    
    # Try DNS lookup first
    hostname=$(timeout 2 host "$ip" 2>/dev/null | awk '{print $NF}' | sed 's/\.$//' || echo "")
    
    # If DNS fails, try SSH to get hostname (via bastion if enabled)
    if [[ -z "$hostname" ]] || [[ "$hostname" == "unknown" ]]; then
        if [[ -f "$SSH_KEY" ]]; then
            local ssh_cmd="ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o BatchMode=yes -i $SSH_KEY -p $SSH_PORT"
            
            # Add bastion ProxyJump if enabled
            if is_bastion_enabled; then
                ssh_cmd="$ssh_cmd -J ${BASTION_USER}@${BASTION_HOST}:${BASTION_PORT}"
            fi
            
            # Try to get hostname via SSH
            hostname=$($ssh_cmd "${SSH_USER}@${ip}" "hostname" 2>/dev/null || echo "unknown")
        fi
    fi
    
    echo "$hostname"
}

# Insert discovered system into database
insert_discovered_system() {
    local ip="$1"
    local hostname="$2"
    
    # Sanitize hostname
    hostname="${hostname//\'/\'\'}"
    
    # Use ON CONFLICT to update if IP already exists
    local query="INSERT INTO systems (hostname, ip_address, dept_id, lab_id, status, created_at)
                 VALUES ('$hostname', '$ip', $DEPT_ID, NULL, 'discovered', NOW())
                 ON CONFLICT (ip_address) 
                 DO UPDATE SET 
                     hostname = EXCLUDED.hostname,
                     dept_id = EXCLUDED.dept_id,
                     status = 'discovered',
                     updated_at = NOW()
                 RETURNING system_id;"
    
    local result=$(exec_sql "$query" 2>&1)
    
    if [[ $? -eq 0 ]]; then
        log_info "  └─ Registered system: $hostname ($ip)"
    else
        log_warning "  └─ Could not register system $ip: $result"
    fi
}

# Nmap scan (if available)
nmap_scan() {
    if ! command -v nmap &> /dev/null; then
        log_warning "nmap not installed, falling back to ping scan"
        ping_scan
        return
    fi
    
    log_info "Starting nmap scan on $SUBNET_CIDR"
    
    # Quick ping scan with nmap
    local nmap_output=$(nmap -sn -n --max-retries 2 --host-timeout 3s "$SUBNET_CIDR" 2>/dev/null)
    local alive_systems=$(echo "$nmap_output" | grep -c "Host is up" || echo "0")
    
    # Extract IPs and insert into database
    echo "$nmap_output" | grep -oP '\d+\.\d+\.\d+\.\d+' | while read -r ip; do
        hostname=$(timeout 2 host "$ip" 2>/dev/null | awk '{print $NF}' | sed 's/\.$//' || echo "unknown")
        insert_discovered_system "$ip" "$hostname"
    done
    
    log_success "Scan complete: $alive_systems systems found"
    echo "$alive_systems"
}

# ARP scan (if available and on local network)
arp_scan() {
    if ! command -v arp-scan &> /dev/null; then
        log_warning "arp-scan not installed, falling back to ping scan"
        ping_scan
        return
    fi
    
    log_info "Starting ARP scan on $SUBNET_CIDR"
    log_warning "ARP scan requires root/sudo privileges"
    
    # Run arp-scan
    local arp_output=$(sudo arp-scan --interface=eth0 --localnet "$SUBNET_CIDR" 2>/dev/null || echo "")
    local alive_systems=$(echo "$arp_output" | grep -c "^[0-9]" || echo "0")
    
    # Parse and insert systems
    echo "$arp_output" | grep "^[0-9]" | awk '{print $1}' | while read -r ip; do
        hostname=$(timeout 2 host "$ip" 2>/dev/null | awk '{print $NF}' | sed 's/\.$//' || echo "unknown")
        insert_discovered_system "$ip" "$hostname"
    done
    
    log_success "Scan complete: $alive_systems systems found"
    echo "$alive_systems"
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "=== OptiLab Network Scanner ==="
    log_info "Subnet: $SUBNET_CIDR"
    log_info "Department ID: $DEPT_ID"
    log_info "Scan Type: $SCAN_TYPE"
    echo
    
    # Validate inputs
    validate_inputs
    
    # Check dependencies
    check_dependencies
    
    # Create scan record
    create_scan_record
    
    # Perform scan based on type
    local systems_found=0
    local scan_status="completed"
    local error_message="NULL"
    
    case "$SCAN_TYPE" in
        ping)
            systems_found=$(ping_scan)
            ;;
        nmap)
            systems_found=$(nmap_scan)
            ;;
        arp)
            systems_found=$(arp_scan)
            ;;
        *)
            error_message="Unknown scan type: $SCAN_TYPE"
            scan_status="failed"
            log_error "$error_message"
            ;;
    esac
    
    # Update scan record
    update_scan_record "$scan_status" "$systems_found" "$error_message"
    
    if [[ "$scan_status" == "completed" ]]; then
        log_success "=== Scan Complete ==="
        log_info "Scan ID: $SCAN_ID"
        log_info "Systems Found: $systems_found"
        log_info "Results stored in database"
    else
        log_error "=== Scan Failed ==="
        exit 1
    fi
}

# Trap errors
trap 'update_scan_record "failed" 0 "Script interrupted or error occurred"' ERR INT TERM

# Run main
main
