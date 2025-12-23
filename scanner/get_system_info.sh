#!/bin/bash

################################################################################
# OptiLab System Details Collector
# Purpose: Collects detailed system information and outputs to stdout
# Usage: ./get_system_info.sh [--json]
################################################################################

# Check if JSON output is requested - do this FIRST before any output
JSON_OUTPUT=0
if [[ "$1" == "--json" ]]; then
    JSON_OUTPUT=1
fi

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_section() {
    if [[ $JSON_OUTPUT -eq 0 ]]; then
        echo -e "\n${BLUE}=== $1 ===${NC}"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Convert human-readable size to GB
convert_to_gb() {
    local size="$1"
    case "$size" in
        *G) echo "${size%G}" ;;
        *M) awk "BEGIN {printf \"%.2f\", ${size%M} / 1024}" ;;
        *T) awk "BEGIN {printf \"%.2f\", ${size%T} * 1024}" ;;
        *K) awk "BEGIN {printf \"%.2f\", ${size%K} / 1024 / 1024}" ;;
        *) echo "$size" ;;
    esac
}

################################################################################
# Network Information
################################################################################

print_section "Network Information"

# Hostname
HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
[[ $JSON_OUTPUT -eq 0 ]] && echo "Hostname: $HOSTNAME"

# IP Address
IP_ADDRESS=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
[[ $JSON_OUTPUT -eq 0 ]] && echo "IP Address: ${IP_ADDRESS:-N/A}"

# MAC Address
MAC_ADDRESS=$(ip link show | grep -oP '(?<=link/ether\s)[0-9a-f:]+' | head -1)
[[ $JSON_OUTPUT -eq 0 ]] && echo "MAC Address: ${MAC_ADDRESS:-N/A}"

################################################################################
# CPU Information
################################################################################

print_section "CPU Information"

# CPU Model
CPU_MODEL=$(lscpu | grep "Model name:" | sed 's/Model name:\s*//')
[[ $JSON_OUTPUT -eq 0 ]] && echo "CPU Model: ${CPU_MODEL:-N/A}"

# CPU Cores
CPU_CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo)
[[ $JSON_OUTPUT -eq 0 ]] && echo "CPU Cores: ${CPU_CORES:-N/A}"

# CPU Architecture
CPU_ARCH=$(uname -m)
[[ $JSON_OUTPUT -eq 0 ]] && echo "CPU Architecture: ${CPU_ARCH:-N/A}"

################################################################################
# Memory Information
################################################################################

print_section "Memory Information"

# Total RAM in GB
RAM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
RAM_TOTAL_GB=$(awk "BEGIN {printf \"%.2f\", $RAM_TOTAL_KB / 1024 / 1024}")
[[ $JSON_OUTPUT -eq 0 ]] && echo "RAM Total: ${RAM_TOTAL_GB} GB"

################################################################################
# Disk Information
################################################################################

print_section "Disk Information"

# Disk Total in GB
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_TOTAL_GB=$(convert_to_gb "$DISK_TOTAL")
[[ $JSON_OUTPUT -eq 0 ]] && echo "Disk Total: ${DISK_TOTAL}"

# Disk Used
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
[[ $JSON_OUTPUT -eq 0 ]] && echo "Disk Used: ${DISK_USED}"

# Disk Available
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
[[ $JSON_OUTPUT -eq 0 ]] && echo "Disk Available: ${DISK_AVAIL}"

# Disk Usage Percentage
DISK_PERCENT=$(df -h / | awk 'NR==2 {print $5}')
[[ $JSON_OUTPUT -eq 0 ]] && echo "Disk Usage: ${DISK_PERCENT}"

################################################################################
# GPU Information
################################################################################

print_section "GPU Information"

# Initialize GPU variables
GPU_MODEL="null"
GPU_MEMORY_GB="null"

# Check for NVIDIA GPU
if command_exists nvidia-smi; then
    GPU_MODEL=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)
    GPU_MEMORY=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    
    if [[ -n "$GPU_MEMORY" ]]; then
        GPU_MEMORY_GB=$(awk "BEGIN {printf \"%.2f\", $GPU_MEMORY / 1024}")
    else
        GPU_MEMORY_GB="null"
    fi
    
    [[ $JSON_OUTPUT -eq 0 ]] && echo "GPU Model: ${GPU_MODEL:-N/A}"
    [[ $JSON_OUTPUT -eq 0 ]] && echo "GPU Memory: ${GPU_MEMORY_GB} GB"
    
# Check for AMD GPU (ROCm)
elif command_exists rocm-smi; then
    GPU_MODEL=$(rocm-smi --showproductname 2>/dev/null | grep "GPU" | head -1 | awk -F': ' '{print $2}')
    GPU_MEMORY_MB=$(rocm-smi --showmeminfo vram 2>/dev/null | grep -oP 'Total memory \(MB\):\s+\K\d+' | head -1)
    
    if [[ -n "$GPU_MEMORY_MB" ]]; then
        GPU_MEMORY_GB=$(awk "BEGIN {printf \"%.2f\", $GPU_MEMORY_MB / 1024}")
    else
        GPU_MEMORY_GB="null"
    fi
    
    [[ $JSON_OUTPUT -eq 0 ]] && echo "GPU Model: ${GPU_MODEL:-AMD GPU}"
    [[ $JSON_OUTPUT -eq 0 ]] && echo "GPU Memory: ${GPU_MEMORY_GB} GB"
else
    [[ $JSON_OUTPUT -eq 0 ]] && echo "GPU: Not detected"
fi

################################################################################
# Operating System Information
################################################################################

print_section "Operating System"

# OS Type
OS_TYPE=$(uname -s)
[[ $JSON_OUTPUT -eq 0 ]] && echo "OS Type: ${OS_TYPE}"

# OS Version
if [[ -f /etc/os-release ]]; then
    OS_VERSION=$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)
else
    OS_VERSION=$(uname -r)
fi
[[ $JSON_OUTPUT -eq 0 ]] && echo "OS Version: ${OS_VERSION}"

# Kernel Version
KERNEL=$(uname -r)
[[ $JSON_OUTPUT -eq 0 ]] && echo "Kernel: ${KERNEL}"

################################################################################
# Current Status
################################################################################

print_section "Current Status"

# Uptime
UPTIME_SECONDS=$(awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0)
UPTIME_HOURS=$(awk "BEGIN {printf \"%.2f\", $UPTIME_SECONDS / 3600}")
[[ $JSON_OUTPUT -eq 0 ]] && echo "Uptime: ${UPTIME_HOURS} hours"

# Logged in users
LOGGED_USERS=$(who | wc -l)
[[ $JSON_OUTPUT -eq 0 ]] && echo "Logged in users: ${LOGGED_USERS}"

# Load average
LOAD_AVG=$(uptime | grep -oP 'load average: \K.*')
[[ $JSON_OUTPUT -eq 0 ]] && echo "Load average: ${LOAD_AVG}"

################################################################################
# JSON Output
################################################################################

if [[ $JSON_OUTPUT -eq 1 ]]; then
    # Output only JSON, no other text
    # Convert GPU values to proper JSON types
    GPU_MODEL_JSON="null"
    GPU_MEMORY_JSON="null"
    
    if [[ "$GPU_MODEL" != "null" ]]; then
        GPU_MODEL_JSON="\"$GPU_MODEL\""
    fi
    
    if [[ "$GPU_MEMORY_GB" != "null" ]]; then
        GPU_MEMORY_JSON=$GPU_MEMORY_GB
    fi
    
    cat << EOF
{
  "hostname": "$HOSTNAME",
  "ip_address": "$IP_ADDRESS",
  "mac_address": "$MAC_ADDRESS",
  "cpu_model": "$CPU_MODEL",
  "cpu_cores": $CPU_CORES,
  "ram_total_gb": $RAM_TOTAL_GB,
  "disk_total_gb": $DISK_TOTAL_GB,
  "gpu_model": $GPU_MODEL_JSON,
  "gpu_memory": $GPU_MEMORY_JSON,
  "os_type": "$OS_TYPE",
  "os_version": "$OS_VERSION",
  "kernel": "$KERNEL",
  "uptime_hours": $UPTIME_HOURS,
  "logged_users": $LOGGED_USERS
}
EOF
else
    # Normal output with sections
    print_section "Collection Complete"
fi
