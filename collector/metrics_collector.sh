#!/bin/bash

################################################################################
# OptiLab Metrics Collector
# Purpose: Collects system metrics (CPU, RAM, Disk, Network, GPU) on target systems
# Usage: ./metrics_collector.sh
# Note: This script runs ON the target system being monitored
################################################################################

set -e  # Exit on error

# Output format: JSON for easy parsing
OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"

################################################################################
# Utility Functions
################################################################################

# Check if command exists
command_exists() {
    command -v "$1" &> /dev/null
}

# Get timestamp in ISO 8601 format
get_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

################################################################################
# System Information Collection
################################################################################

# Get hostname
get_hostname() {
    hostname 2>/dev/null || echo "unknown"
}

# Get uptime in seconds
get_uptime() {
    if [[ -f /proc/uptime ]]; then
        awk '{print int($1)}' /proc/uptime
    else
        # macOS/BSD fallback
        sysctl -n kern.boottime 2>/dev/null | awk '{print int(systime() - $4)}'
    fi
}

# Get logged in users count
get_logged_in_users() {
    who | wc -l | tr -d ' '
}

################################################################################
# CPU Metrics
################################################################################

get_cpu_percent() {
    if command_exists mpstat; then
        # Use mpstat for accurate CPU usage (from sysstat package)
        mpstat 1 1 | awk '/Average/ {print 100 - $NF}'
    elif [[ -f /proc/stat ]]; then
        # Linux: Calculate from /proc/stat
        local cpu_line1=($(grep '^cpu ' /proc/stat))
        sleep 1
        local cpu_line2=($(grep '^cpu ' /proc/stat))
        
        local idle1=${cpu_line1[4]}
        local idle2=${cpu_line2[4]}
        
        local total1=0
        local total2=0
        for val in "${cpu_line1[@]:1}"; do total1=$((total1 + val)); done
        for val in "${cpu_line2[@]:1}"; do total2=$((total2 + val)); done
        
        local idle_delta=$((idle2 - idle1))
        local total_delta=$((total2 - total1))
        
        local cpu_percent=$(awk "BEGIN {printf \"%.2f\", 100 * ($total_delta - $idle_delta) / $total_delta}")
        echo "$cpu_percent"
    elif command_exists top; then
        # macOS/BSD fallback using top
        top -l 2 -n 0 -F | grep "CPU usage" | tail -1 | awk '{print $3}' | sed 's/%//'
    else
        echo "0.00"
    fi
}

get_cpu_temperature() {
    # Try multiple methods to get CPU temperature
    
    # Method 1: sensors (lm-sensors package)
    if command_exists sensors; then
        sensors 2>/dev/null | grep -i "core 0" | awk '{print $3}' | sed 's/+//;s/°C//' | head -1
        return
    fi
    
    # Method 2: thermal zone (Linux)
    if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
        awk '{printf "%.2f", $1/1000}' /sys/class/thermal/thermal_zone0/temp
        return
    fi
    
    # Method 3: vcgencmd (Raspberry Pi)
    if command_exists vcgencmd; then
        vcgencmd measure_temp 2>/dev/null | sed 's/temp=//' | sed "s/'C//"
        return
    fi
    
    echo "null"
}

################################################################################
# Memory Metrics
################################################################################

get_ram_percent() {
    if [[ -f /proc/meminfo ]]; then
        # Linux
        local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        local mem_used=$((mem_total - mem_available))
        awk "BEGIN {printf \"%.2f\", 100 * $mem_used / $mem_total}"
    elif command_exists vm_stat; then
        # macOS
        local page_size=$(pagesize 2>/dev/null || echo 4096)
        local vm_output=$(vm_stat)
        
        local pages_wired=$(echo "$vm_output" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
        local pages_active=$(echo "$vm_output" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
        local pages_free=$(echo "$vm_output" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
        
        local mem_used=$(( (pages_wired + pages_active) * page_size / 1024 / 1024 ))
        local mem_total=$(sysctl -n hw.memsize | awk '{print $1/1024/1024}')
        
        awk "BEGIN {printf \"%.2f\", 100 * $mem_used / $mem_total}"
    else
        echo "0.00"
    fi
}

################################################################################
# Disk Metrics
################################################################################

get_disk_percent() {
    # Get disk usage for root partition
    df -h / | awk 'NR==2 {print $5}' | sed 's/%//'
}

get_disk_io() {
    # Returns disk read/write in MB/s
    
    if [[ -f /proc/diskstats ]]; then
        # Linux: Use iostat if available
        if command_exists iostat; then
            local io_output=$(iostat -d -x 1 2 | tail -n +4 | awk '{if(NR==1) {read1=$6; write1=$7} else if(NR==2) {read2=$6; write2=$7}} END {printf "%.2f %.2f", read2-read1, write2-write1}')
            echo "$io_output"
        else
            # Fallback: sample /proc/diskstats
            local disk_line1=($(grep -w "sda\|vda\|nvme0n1" /proc/diskstats | head -1))
            sleep 1
            local disk_line2=($(grep -w "sda\|vda\|nvme0n1" /proc/diskstats | head -1))
            
            local sectors_read1=${disk_line1[5]:-0}
            local sectors_written1=${disk_line1[9]:-0}
            local sectors_read2=${disk_line2[5]:-0}
            local sectors_written2=${disk_line2[9]:-0}
            
            local read_mb=$(awk "BEGIN {printf \"%.2f\", ($sectors_read2 - $sectors_read1) * 512 / 1024 / 1024}")
            local write_mb=$(awk "BEGIN {printf \"%.2f\", ($sectors_written2 - $sectors_written1) * 512 / 1024 / 1024}")
            
            echo "$read_mb $write_mb"
        fi
    else
        echo "0.00 0.00"
    fi
}

################################################################################
# Network Metrics
################################################################################

get_network_io() {
    # Returns network sent/received in Mbps
    
    # Find primary network interface
    local interface=""
    
    if command_exists ip; then
        interface=$(ip route | grep default | awk '{print $5}' | head -1)
    elif command_exists route; then
        interface=$(route -n | grep '^0.0.0.0' | awk '{print $NF}' | head -1)
    elif command_exists netstat; then
        interface=$(netstat -rn | grep default | awk '{print $NF}' | head -1)
    fi
    
    # Default to eth0 or en0 if not found
    [[ -z "$interface" ]] && interface="eth0"
    [[ ! -d "/sys/class/net/$interface" ]] && interface="en0"
    
    if [[ -f "/sys/class/net/$interface/statistics/tx_bytes" ]]; then
        # Linux
        local tx1=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        local rx1=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        
        sleep 1
        
        local tx2=$(cat /sys/class/net/$interface/statistics/tx_bytes)
        local rx2=$(cat /sys/class/net/$interface/statistics/rx_bytes)
        
        local tx_mbps=$(awk "BEGIN {printf \"%.2f\", ($tx2 - $tx1) * 8 / 1000000}")
        local rx_mbps=$(awk "BEGIN {printf \"%.2f\", ($rx2 - $rx1) * 8 / 1000000}")
        
        echo "$tx_mbps $rx_mbps"
    elif command_exists netstat; then
        # macOS/BSD fallback
        local net1=($(netstat -ibn | grep -w "$interface" | head -1 | awk '{print $7, $10}'))
        sleep 1
        local net2=($(netstat -ibn | grep -w "$interface" | head -1 | awk '{print $7, $10}'))
        
        local tx_mbps=$(awk "BEGIN {printf \"%.2f\", (${net2[0]:-0} - ${net1[0]:-0}) * 8 / 1000000}")
        local rx_mbps=$(awk "BEGIN {printf \"%.2f\", (${net2[1]:-0} - ${net1[1]:-0}) * 8 / 1000000}")
        
        echo "$tx_mbps $rx_mbps"
    else
        echo "0.00 0.00"
    fi
}

################################################################################
# GPU Metrics
################################################################################

get_gpu_metrics() {
    # Check for NVIDIA GPU
    if command_exists nvidia-smi; then
        # Get GPU utilization, memory used, and temperature
        local gpu_output=$(nvidia-smi --query-gpu=utilization.gpu,memory.used,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
        
        if [[ -n "$gpu_output" ]]; then
            local gpu_util=$(echo "$gpu_output" | awk -F',' '{print $1}' | tr -d ' ')
            local gpu_mem=$(echo "$gpu_output" | awk -F',' '{print $2}' | tr -d ' ')
            local gpu_temp=$(echo "$gpu_output" | awk -F',' '{print $3}' | tr -d ' ')
            
            # Convert memory from MB to GB
            gpu_mem=$(awk "BEGIN {printf \"%.2f\", $gpu_mem / 1024}")
            
            echo "$gpu_util $gpu_mem $gpu_temp"
            return
        fi
    fi
    
    # Check for AMD GPU (rocm-smi)
    if command_exists rocm-smi; then
        local gpu_output=$(rocm-smi --showuse --showmeminfo vram --showtemp | grep -E "GPU\[0\]")
        # Parse output (format varies)
        # Simplified: return placeholder
        echo "0.00 0.00 null"
        return
    fi
    
    # No GPU found
    echo "null null null"
}

################################################################################
# Main Collection Function
################################################################################

collect_metrics() {
    local timestamp=$(get_timestamp)
    local hostname=$(get_hostname)
    local uptime=$(get_uptime)
    local logged_users=$(get_logged_in_users)
    
    # CPU metrics
    local cpu_percent=$(get_cpu_percent)
    local cpu_temp=$(get_cpu_temperature)
    
    # Memory metrics
    local ram_percent=$(get_ram_percent)
    
    # Disk metrics
    local disk_percent=$(get_disk_percent)
    local disk_io=($(get_disk_io))
    local disk_read_mbps=${disk_io[0]:-0.00}
    local disk_write_mbps=${disk_io[1]:-0.00}
    
    # Network metrics
    local network_io=($(get_network_io))
    local network_sent_mbps=${network_io[0]:-0.00}
    local network_recv_mbps=${network_io[1]:-0.00}
    
    # GPU metrics
    local gpu_metrics=($(get_gpu_metrics))
    local gpu_percent=${gpu_metrics[0]:-null}
    local gpu_memory_gb=${gpu_metrics[1]:-null}
    local gpu_temp=${gpu_metrics[2]:-null}
    
    # Output in JSON format
    cat << EOF
{
  "timestamp": "$timestamp",
  "hostname": "$hostname",
  "uptime_seconds": $uptime,
  "logged_in_users": $logged_users,
  "cpu_percent": $cpu_percent,
  "cpu_temperature": $cpu_temp,
  "ram_percent": $ram_percent,
  "disk_percent": $disk_percent,
  "disk_read_mbps": $disk_read_mbps,
  "disk_write_mbps": $disk_write_mbps,
  "network_sent_mbps": $network_sent_mbps,
  "network_recv_mbps": $network_recv_mbps,
  "gpu_percent": $gpu_percent,
  "gpu_memory_used_gb": $gpu_memory_gb,
  "gpu_temperature": $gpu_temp
}
EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    # Check if running with sufficient privileges (warn if not root for some metrics)
    if [[ $EUID -ne 0 ]] && [[ ! -f /proc/stat ]]; then
        >&2 echo "Warning: Some metrics may require root privileges for accuracy"
    fi
    
    # Collect and output metrics
    collect_metrics
}

# Run main
main
