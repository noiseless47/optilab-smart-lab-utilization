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

get_cpu_iowait() {
    # Get CPU I/O wait percentage
    if command_exists mpstat; then
        # Use mpstat to get iowait (from sysstat package)
        mpstat 1 1 | awk '/Average/ {print $(NF-3)}'
    elif [[ -f /proc/stat ]]; then
        # Linux: Calculate iowait from /proc/stat
        local cpu_line1=($(grep '^cpu ' /proc/stat))
        sleep 1
        local cpu_line2=($(grep '^cpu ' /proc/stat))
        
        # iowait is the 5th field (index 5)
        local iowait1=${cpu_line1[5]:-0}
        local iowait2=${cpu_line2[5]:-0}
        
        local total1=0
        local total2=0
        for val in "${cpu_line1[@]:1}"; do total1=$((total1 + val)); done
        for val in "${cpu_line2[@]:1}"; do total2=$((total2 + val)); done
        
        local iowait_delta=$((iowait2 - iowait1))
        local total_delta=$((total2 - total1))
        
        if [[ $total_delta -gt 0 ]]; then
            awk "BEGIN {printf \"%.2f\", 100 * $iowait_delta / $total_delta}"
        else
            echo "0.00"
        fi
    else
        echo "null"
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
        # Fallback: sample /proc/diskstats (most reliable)
        # Find the main disk device
        local disk_device=$(lsblk -d -o name | grep -E "^(sda|vda|nvme0n1)" | head -1)
        
        # Default to common disk names if lsblk doesn't work
        if [[ -z "$disk_device" ]]; then
            for dev in sda vda nvme0n1; do
                if grep -q "^.*$dev " /proc/diskstats 2>/dev/null; then
                    disk_device="$dev"
                    break
                fi
            done
        fi
        
        if [[ -z "$disk_device" ]]; then
            echo "0.00 0.00"
            return
        fi
        
        # Read initial values
        local disk_line1=($(grep -w "$disk_device" /proc/diskstats | head -1))
        local sectors_read1=${disk_line1[5]:-0}
        local sectors_written1=${disk_line1[9]:-0}
        
        # Wait and read again
        sleep 2
        
        local disk_line2=($(grep -w "$disk_device" /proc/diskstats | head -1))
        local sectors_read2=${disk_line2[5]:-0}
        local sectors_written2=${disk_line2[9]:-0}
        
        # Calculate deltas (ensure we don't get negative values from counter rollover)
        local sectors_read_delta=$((sectors_read2 - sectors_read1))
        local sectors_written_delta=$((sectors_written2 - sectors_written1))
        
        # If delta is negative, it means counter rolled over or error - return 0
        if [[ $sectors_read_delta -lt 0 ]]; then
            sectors_read_delta=0
        fi
        if [[ $sectors_written_delta -lt 0 ]]; then
            sectors_written_delta=0
        fi
        
        # Convert sectors (512 bytes each) to MB/s over the 2-second interval
        local read_mb=$(awk "BEGIN {printf \"%.2f\", $sectors_read_delta * 512 / 1024 / 1024 / 2}")
        local write_mb=$(awk "BEGIN {printf \"%.2f\", $sectors_written_delta * 512 / 1024 / 1024 / 2}")
        
        echo "$read_mb $write_mb"
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

get_context_switch_rate() {
    # Get context switch rate (switches per second)
    if command_exists sar; then
        # Use sar -w for context switches
        sar -w 1 1 2>/dev/null | awk '/Average/ {print int($2)}'
    elif command_exists vmstat; then
        # Fallback to vmstat (use second line)
        vmstat 1 2 2>/dev/null | tail -1 | awk '{print int($12)}'
    else
        echo "null"
    fi
}

get_swap_rates() {
    # Get swap in/out rates (pages per second)
    if command_exists sar; then
        # Use sar -W for swap activity
        local swap_data=$(sar -W 1 1 2>/dev/null | awk '/Average/ {print $2, $3}')
        if [[ -n "$swap_data" ]]; then
            echo "$swap_data"
        else
            echo "null null"
        fi
    elif command_exists vmstat; then
        # Fallback to vmstat (si = swap in, so = swap out)
        vmstat 1 2 2>/dev/null | tail -1 | awk '{printf "%.2f %.2f", $7, $8}'
    else
        echo "null null"
    fi
}

get_page_fault_rates() {
    # Get page fault rates (faults per second)
    if command_exists sar; then
        # Use sar -B for paging statistics
        local paging_data=$(sar -B 1 1 2>/dev/null | awk '/Average/ {print $2, $3}')
        if [[ -n "$paging_data" ]]; then
            echo "$paging_data"
        else
            echo "null null"
        fi
    elif [[ -f /proc/vmstat ]]; then
        # Fallback: calculate from /proc/vmstat
        local pgfault1=$(grep '^pgfault ' /proc/vmstat 2>/dev/null | awk '{print $2}')
        local pgmajfault1=$(grep '^pgmajfault ' /proc/vmstat 2>/dev/null | awk '{print $2}')
        
        sleep 1
        
        local pgfault2=$(grep '^pgfault ' /proc/vmstat 2>/dev/null | awk '{print $2}')
        local pgmajfault2=$(grep '^pgmajfault ' /proc/vmstat 2>/dev/null | awk '{print $2}')
        
        if [[ -n "$pgfault1" && -n "$pgfault2" ]]; then
            local fault_rate=$((pgfault2 - pgfault1))
            local majfault_rate=$((pgmajfault2 - pgmajfault1))
            echo "$fault_rate $majfault_rate"
        else
            echo "null null"
        fi
    else
        echo "null null"
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
        # Get GPU utilization percentage
        local gpu_util=$(rocm-smi --showuse 2>/dev/null | grep -oP 'GPU use \(%\):\s+\K\d+' | head -1)
        
        # Get GPU memory used in MB
        local gpu_mem_mb=$(rocm-smi --showmeminfo vram 2>/dev/null | grep -oP 'GPU memory use \(MB\):\s+\K\d+' | head -1)
        
        # Get GPU temperature in Celsius
        local gpu_temp=$(rocm-smi --showtemp 2>/dev/null | grep -oP 'Temperature \(Sensor edge\) \(C\):\s+\K[\d.]+' | head -1)
        
        # Convert memory from MB to GB
        if [[ -n "$gpu_mem_mb" && "$gpu_mem_mb" != "0" ]]; then
            local gpu_mem=$(awk "BEGIN {printf \"%.2f\", $gpu_mem_mb / 1024}")
        else
            local gpu_mem="0.00"
        fi
        
        # Set defaults if any value is missing
        gpu_util=${gpu_util:-0}
        gpu_temp=${gpu_temp:-null}
        
        echo "$gpu_util $gpu_mem $gpu_temp"
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
    local cpu_iowait=$(get_cpu_iowait)
    
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
    
    # CFRS-relevant advanced metrics
    local context_switches=$(get_context_switch_rate)
    local swap_rates=($(get_swap_rates))
    local swap_in=${swap_rates[0]:-null}
    local swap_out=${swap_rates[1]:-null}
    local page_faults=($(get_page_fault_rates))
    local page_fault_rate=${page_faults[0]:-null}
    local major_page_fault_rate=${page_faults[1]:-null}
    
    # Output in JSON format
    cat << EOF
{
  "timestamp": "$timestamp",
  "hostname": "$hostname",
  "uptime_seconds": $uptime,
  "logged_in_users": $logged_users,
  "cpu_percent": $cpu_percent,
  "cpu_temperature": $cpu_temp,
  "cpu_iowait_percent": $cpu_iowait,
  "ram_percent": $ram_percent,
  "disk_percent": $disk_percent,
  "disk_read_mbps": $disk_read_mbps,
  "disk_write_mbps": $disk_write_mbps,
  "network_sent_mbps": $network_sent_mbps,
  "network_recv_mbps": $network_recv_mbps,
  "gpu_percent": $gpu_percent,
  "gpu_memory_used_gb": $gpu_memory_gb,
  "gpu_temperature": $gpu_temp,
  "context_switch_rate": $context_switches,
  "swap_in_rate": $swap_in,
  "swap_out_rate": $swap_out,
  "page_fault_rate": $page_fault_rate,
  "major_page_fault_rate": $major_page_fault_rate
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
