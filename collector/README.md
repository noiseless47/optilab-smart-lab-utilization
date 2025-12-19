# OptiLab Collector Scripts

This directory contains the core collection infrastructure for OptiLab - network scanning, metrics collection, and SSH-based remote monitoring.

## 📁 Directory Contents

```
collector/
├── scanner.sh                    # Network scanner for system discovery
├── metrics_collector.sh          # Actual metrics collection script (runs on target)
├── ssh_script.sh                # SSH wrapper for remote collection
├── bastion_config.sh            # 🆕 Bastion host configuration
├── ssh_bastion_wrapper.sh       # 🆕 SSH/SCP wrapper utility
├── queue_consumer.py            # Message queue consumer (optional)
├── queue_setup.sh               # Queue initialization script
└── README.md                    # This file
```

## 🔍 Script Overview

### 1. scanner.sh - Network Discovery

**Purpose**: Discovers alive systems in a network by scanning IP ranges.

**Features**:
- Ping sweep across CIDR ranges
- Records discoveries in `network_scans` table
- Registers systems in `systems` table
- Optional nmap/arp-scan integration
- Database logging of scan results

**Usage**:
```bash
# Basic ping scan
./scanner.sh 10.30.5.0/24 1

# Using nmap (faster, more accurate)
./scanner.sh 10.30.5.0/24 1 nmap

# Larger network scan
./scanner.sh 10.30.0.0/16 1 ping

# With database credentials
DB_HOST=db.example.com DB_PASSWORD=secret ./scanner.sh 192.168.1.0/24 2
```

**Arguments**:
- `subnet_cidr` - IP range in CIDR notation (e.g., 10.30.5.0/24)
- `dept_id` - Department ID from database
- `scan_type` - Type of scan: `ping` (default), `nmap`, or `arp`

**Output**: Creates entry in `network_scans` table, registers discovered systems in `systems` table.

---

### 2. metrics_collector.sh - System Metrics

**Purpose**: Collects comprehensive system metrics from the LOCAL machine.

**Features**:
- CPU usage and temperature
- RAM utilization
- Disk usage and I/O rates
- Network throughput (sent/received)
- GPU metrics (if available)
- Uptime and logged users
- JSON output format

**Usage**:
```bash
# Run locally
./metrics_collector.sh

# Sample output (JSON)
{
  "timestamp": "2025-11-25T10:30:00Z",
  "hostname": "lab-pc-01",
  "cpu_percent": 45.23,
  "ram_percent": 67.89,
  "disk_percent": 55.12,
  ...
}
```

**Dependencies**:
- Linux: `/proc/stat`, `/proc/meminfo`, `df`, `iostat` (optional)
- GPU: `nvidia-smi` (NVIDIA), `rocm-smi` (AMD)
- Network: `/sys/class/net/` stats

**Note**: This script is designed to be transferred to and executed on target systems.

---

### 3. ssh_script.sh - Remote Collection

**Purpose**: SSH into target systems, transfer `metrics_collector.sh`, execute it, and store results.

**Features**:
- Parallel collection from multiple systems
- Automatic script transfer via SCP
- JSON parsing and database insertion
- Connection pooling support
- Flexible targeting (all/single/lab/dept)
- Optional message queue integration

**Usage**:
```bash
# Collect from all active systems
./ssh_script.sh --all

# Collect from single system
./ssh_script.sh --single 10.30.5.10

# Collect from specific lab
./ssh_script.sh --lab 5

# Collect from department
./ssh_script.sh --dept 1

# Custom SSH credentials
./ssh_script.sh --all \
  --user labadmin \
  --key /path/to/private_key \
  --port 2222

# Enable message queue
./ssh_script.sh --all --queue-enabled --queue-host rabbitmq.local
```

**Arguments**:
- `-a, --all` - Collect from all systems
- `-s, --single IP` - Single system
- `-l, --lab LAB_ID` - All systems in lab
- `-d, --dept DEPT_ID` - All systems in department
- `-u, --user USER` - SSH username (default: admin)
- `-k, --key PATH` - SSH private key path
- `-p, --port PORT` - SSH port (default: 22)
- `--queue-enabled` - Use message queue instead of direct DB writes

**Prerequisites**:
1. SSH key authentication set up on target systems
2. `metrics_collector.sh` in same directory
3. PostgreSQL client (`psql`) installed
4. Target systems must have bash

---

### 4. queue_consumer.py - Message Queue Consumer

**Purpose**: Consumes messages from RabbitMQ/Redis and processes them into the database.

**Features**:
- Supports RabbitMQ and Redis
- Processes discovery, metrics, and alert messages
- Automatic reconnection on failure
- Graceful shutdown handling
- Database transaction management

**Usage**:
```bash
# Install dependencies
pip install psycopg2-binary pika redis

# Start consumer for metrics queue
python3 queue_consumer.py metrics

# Start consumer for discovery queue
python3 queue_consumer.py discovery

# With environment variables
DB_PASSWORD=secret QUEUE_TYPE=rabbitmq python3 queue_consumer.py metrics
```

**Environment Variables**:
```bash
# Database
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=optilab
export DB_USER=postgres
export DB_PASSWORD=your_password

# Queue
export QUEUE_TYPE=rabbitmq  # or redis
export QUEUE_HOST=localhost
export QUEUE_PORT=5672      # 5672 for RabbitMQ, 6379 for Redis
export QUEUE_USER=guest
export QUEUE_PASSWORD=guest
```

---

### 5. queue_setup.sh - Queue Initialization

**Purpose**: Initialize message queues and exchanges.

**Usage**:
```bash
# Setup RabbitMQ queues
./queue_setup.sh rabbitmq

# Setup Redis lists
./queue_setup.sh redis

# Generate Docker Compose file
./queue_setup.sh docker
```

---

## 🚀 Quick Start

### Step 1: Discover Systems

```bash
# Scan your network (replace with your subnet)
./scanner.sh 10.30.5.0/24 1 ping
```

This creates entries in the `network_scans` and `systems` tables.

### Step 2: Set Up SSH Keys

```bash
# Generate SSH key pair (if not exists)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/optilab_key

# Copy public key to target systems
ssh-copy-id -i ~/.ssh/optilab_key.pub admin@10.30.5.10

# Test connection
ssh -i ~/.ssh/optilab_key admin@10.30.5.10 "echo 'Connection successful'"
```

### Step 3: Collect Metrics

```bash
# Collect from all discovered systems
./ssh_script.sh --all --user admin --key ~/.ssh/optilab_key

# Or collect from specific lab
./ssh_script.sh --lab 1 --user admin --key ~/.ssh/optilab_key
```

### Step 4 (Optional): Enable Message Queue

```bash
# Start RabbitMQ
docker run -d --name rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  rabbitmq:3-management

# Setup queues
./queue_setup.sh rabbitmq

# Start consumer
python3 queue_consumer.py metrics &

# Collect with queue enabled
./ssh_script.sh --all --queue-enabled
```

---

## 🏗️ Architecture

### Without Message Queue (Direct DB Write)
```
Scanner/Collector → Database
                    (Direct INSERT)
```

### With Message Queue (Recommended for Production)
```
Scanner/Collector → RabbitMQ/Redis → Consumer → Database
                    (Async)          (Workers)   (Batch INSERT)
```

**Benefits of Message Queue**:
- ✅ Non-blocking collection (faster scans)
- ✅ Fault tolerance (messages persist)
- ✅ Load balancing (multiple consumers)
- ✅ Retry logic (automatic requeue on failure)
- ✅ Scalability (add more workers)

See [MESSAGE_QUEUE.md](../docs/MESSAGE_QUEUE.md) for detailed architecture.

---

## 📊 Database Schema

### network_scans Table
Stores scan history and results.

```sql
SELECT scan_id, dept_id, scan_type, target_range, 
       systems_found, scan_start, duration_seconds
FROM network_scans
WHERE status = 'completed'
ORDER BY scan_start DESC;
```

### systems Table
Registered discovered systems.

```sql
SELECT system_id, hostname, ip_address, dept_id, 
       status, created_at
FROM systems
WHERE status IN ('discovered', 'active')
ORDER BY created_at DESC;
```

### metrics Table
Time-series metrics data.

```sql
SELECT system_id, timestamp, 
       cpu_percent, ram_percent, disk_percent
FROM metrics
WHERE system_id = 1
  AND timestamp > NOW() - INTERVAL '1 hour'
ORDER BY timestamp DESC;
```

---

## 🔐 Security Best Practices

### SSH Key Management
1. **Generate dedicated keys** for OptiLab (don't reuse personal keys)
2. **Restrict permissions**: `chmod 600 ~/.ssh/optilab_key`
3. **Use passphrase** for additional security
4. **Rotate keys** periodically (every 90 days)

### Database Credentials
1. **Never hardcode passwords** in scripts
2. **Use environment variables**: `DB_PASSWORD=secret ./script.sh`
3. **Restrict database user** to only required tables
4. **Use SSL/TLS** for database connections in production

### Network Security
1. **Scan only authorized networks**
2. **Use VPN** for remote scanning
3. **Rate limit** scans to avoid DoS detection
4. **Log all activities** for audit trail

---

## 🐛 Troubleshooting

### Scanner Issues

**Problem**: "No systems found" on known active network
```bash
# Check network connectivity
ping 10.30.5.1

# Try different scan type
./scanner.sh 10.30.5.0/24 1 nmap

# Check firewall rules (ICMP must be allowed)
```

**Problem**: "Database connection failed"
```bash
# Test database connectivity
psql -h localhost -U postgres -d optilab -c "SELECT 1;"

# Check environment variables
echo $DB_HOST $DB_PORT $DB_NAME $DB_USER
```

### SSH Collection Issues

**Problem**: "SSH connection failed"
```bash
# Test SSH manually
ssh -i ~/.ssh/optilab_key admin@10.30.5.10

# Check key permissions
chmod 600 ~/.ssh/optilab_key

# Check SSH agent
eval $(ssh-agent)
ssh-add ~/.ssh/optilab_key
```

**Problem**: "Permission denied" on target system
```bash
# Ensure user has necessary permissions
ssh admin@10.30.5.10 "cat /proc/stat"  # Should work
ssh admin@10.30.5.10 "sudo iotop"      # Requires sudo

# Grant sudo without password (optional, security risk)
# On target: sudo visudo
# Add: admin ALL=(ALL) NOPASSWD: ALL
```

### Metrics Collection Issues

**Problem**: Metrics show all zeros
```bash
# Run collector locally to debug
./metrics_collector.sh

# Check dependencies
command -v iostat  # Install sysstat if missing
command -v nvidia-smi  # For GPU metrics
```

**Problem**: JSON parsing error
```bash
# Validate JSON output
./metrics_collector.sh | jq .

# Install jq if needed
sudo apt-get install jq  # Debian/Ubuntu
```

### Queue Issues

**Problem**: Messages not being consumed
```bash
# Check queue depth
curl -u guest:guest http://localhost:15672/api/queues/%2F/metrics_queue

# Restart consumer
pkill -f queue_consumer.py
python3 queue_consumer.py metrics &

# Check consumer logs
tail -f /var/log/optilab/consumer.log
```

---

## 📈 Performance Optimization

### Scanner Performance
- **Parallel pings**: Use nmap for faster scanning
- **Smaller subnets**: Split /16 into multiple /24 scans
- **Skip network/broadcast**: Already implemented

### Collection Performance
- **Batch collections**: Use `--lab` or `--dept` modes
- **Connection pooling**: Reuse SSH connections
- **Parallel execution**: Run multiple collectors (be careful with DB writes)

### Database Performance
- **Indexes**: Already created on key columns
- **Partitioning**: Consider time-based partitioning for metrics table
- **Archival**: Move old metrics to archive table

---

## 🔄 Automation

### Cron Jobs

```bash
# Edit crontab
crontab -e

# Scan network daily at 2 AM
0 2 * * * cd /path/to/dbms/collector && ./scanner.sh 10.30.5.0/24 1 >> /var/log/optilab/scanner.log 2>&1

# Collect metrics every 5 minutes
*/5 * * * * cd /path/to/dbms/collector && ./ssh_script.sh --all >> /var/log/optilab/collector.log 2>&1

# Start queue consumer on reboot
@reboot cd /path/to/dbms/collector && python3 queue_consumer.py metrics >> /var/log/optilab/consumer.log 2>&1
```

### Systemd Services

See [INSTALLATION.md](../docs/INSTALLATION.md) for systemd service configuration.

---

## 📚 See Also

- [ARCHITECTURE.md](../docs/ARCHITECTURE.md) - System architecture
- [MESSAGE_QUEUE.md](../docs/MESSAGE_QUEUE.md) - Queue integration guide
- [API_REFERENCE.md](../docs/API_REFERENCE.md) - API endpoints
- [INSTALLATION.md](../docs/INSTALLATION.md) - Installation guide
- [Schema.sql](../database/schema.sql) - Database schema

---

## 🤝 Contributing

When adding new metrics or modifying scripts:

1. **Test thoroughly** in isolated environment
2. **Update documentation** (this README)
3. **Add error handling** for edge cases
4. **Follow existing code style**
5. **Log all actions** for debugging

---

## 📝 License

MIT License - See [LICENSE](../LICENSE) file for details.
