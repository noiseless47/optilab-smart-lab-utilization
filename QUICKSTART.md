# OptiLab Quick Start Guide

Get OptiLab up and running in 15 minutes!

## 🚀 Prerequisites

- PostgreSQL installed and running
- Bash shell (Linux/macOS)
- SSH access to target systems
- Network access to lab computers

## 📦 Installation (5 minutes)

### Step 1: Database Setup
```bash
# Create database
psql -U postgres -c "CREATE DATABASE optilab;"

# Load schema
psql -U postgres -d optilab -f database/schema.sql

# Verify
psql -U postgres -d optilab -c "\dt"
```

### Step 2: Configure Scripts
```bash
# Navigate to collector directory
cd collector/

# Copy and edit configuration
cp .env.example .env
nano .env  # Update DB_PASSWORD, SSH_USER, SSH_KEY

# Make scripts executable
chmod +x *.sh
```

### Step 3: SSH Key Setup
```bash
# Generate key (if you don't have one)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/optilab_key

# Copy to target systems (replace IPs)
for ip in 10.30.5.{10..20}; do
  ssh-copy-id -i ~/.ssh/optilab_key.pub admin@$ip
done

# Test connection
ssh -i ~/.ssh/optilab_key admin@10.30.5.10 "echo 'Success!'"
```

## 🔍 First Run (5 minutes)

### Test 1: Discover Systems
```bash
# Scan your network (adjust subnet for your environment)
./scanner.sh 10.30.5.0/24 1 ping

# Expected output:
# [INFO] Starting ping scan on 10.30.5.0/24
# [SUCCESS] ✓ 10.30.5.10 is alive
# [SUCCESS] ✓ 10.30.5.11 is alive
# ...
# [SUCCESS] Scan complete: 15/254 systems alive
```

### Test 2: Collect Metrics from One System
```bash
# Collect from single system
./ssh_script.sh --single 10.30.5.10 \
  --user admin \
  --key ~/.ssh/optilab_key

# Expected output:
# [INFO] Collecting from: lab-pc-01 (10.30.5.10)
# [INFO]   └─ Transferring collector script...
# [INFO]   └─ Executing collector script...
# [SUCCESS]   └─ Metrics collected successfully
```

### Test 3: Collect from All Systems
```bash
# Collect from all discovered systems
./ssh_script.sh --all \
  --user admin \
  --key ~/.ssh/optilab_key

# Expected output:
# [INFO] Found 15 system(s) to collect from
# [INFO] Collecting from: lab-pc-01 (10.30.5.10)
# [SUCCESS]   └─ Metrics collected successfully
# ...
# [SUCCESS] === Collection Complete ===
# [INFO] Total: 15 | Success: 14 | Failed: 1
```

## 📊 Verify Data (2 minutes)

### Check Discovered Systems
```bash
psql -U postgres -d optilab -c "
SELECT system_id, hostname, ip_address, status, created_at 
FROM systems 
ORDER BY created_at DESC 
LIMIT 10;"
```

### Check Collected Metrics
```bash
psql -U postgres -d optilab -c "
SELECT s.hostname, m.timestamp, m.cpu_percent, m.ram_percent, m.disk_percent
FROM metrics m
JOIN systems s ON m.system_id = s.system_id
ORDER BY m.timestamp DESC
LIMIT 10;"
```

### Check Scan History
```bash
psql -U postgres -d optilab -c "
SELECT scan_id, scan_type, target_range, systems_found, 
       scan_start, duration_seconds 
FROM network_scans 
ORDER BY scan_start DESC 
LIMIT 5;"
```

## 🤖 Automate (3 minutes)

### Set Up Cron Jobs
```bash
# Edit crontab
crontab -e

# Add these lines (adjust paths):

# Scan network daily at 2 AM
0 2 * * * cd /path/to/dbms/collector && ./scanner.sh 10.30.5.0/24 1 >> /var/log/optilab/scanner.log 2>&1

# Collect metrics every 5 minutes
*/5 * * * * cd /path/to/dbms/collector && ./ssh_script.sh --all --user admin --key ~/.ssh/optilab_key >> /var/log/optilab/collector.log 2>&1
```

### Create Log Directory
```bash
sudo mkdir -p /var/log/optilab
sudo chown $USER:$USER /var/log/optilab
```

## ✅ Success!

You now have:
- ✅ Systems automatically discovered
- ✅ Metrics collected every 5 minutes
- ✅ Data stored in TimescaleDB
- ✅ Automated monitoring running

## 📈 Next Steps

### View Real-Time Metrics
```sql
-- Top 5 systems by CPU usage (last hour)
SELECT s.hostname, AVG(m.cpu_percent) as avg_cpu
FROM metrics m
JOIN systems s ON m.system_id = s.system_id
WHERE m.timestamp > NOW() - INTERVAL '1 hour'
GROUP BY s.hostname
ORDER BY avg_cpu DESC
LIMIT 5;

-- Systems with high RAM usage
SELECT s.hostname, m.ram_percent, m.timestamp
FROM metrics m
JOIN systems s ON m.system_id = s.system_id
WHERE m.ram_percent > 80
ORDER BY m.timestamp DESC
LIMIT 10;
```

### Optional: Enable Message Queue
```bash
# Install RabbitMQ
docker run -d --name rabbitmq \
  -p 5672:5672 -p 15672:15672 \
  rabbitmq:3-management

# Setup queues
./queue_setup.sh rabbitmq

# Install Python dependencies
pip3 install -r ../requirements.txt

# Start consumer
python3 queue_consumer.py metrics &

# Collect with queue enabled
./ssh_script.sh --all --queue-enabled
```

## 🐛 Troubleshooting

### Scanner finds no systems
```bash
# Test network connectivity
ping 10.30.5.1

# Try with nmap (faster)
./scanner.sh 10.30.5.0/24 1 nmap
```

### SSH collection fails
```bash
# Test SSH manually
ssh -i ~/.ssh/optilab_key admin@10.30.5.10

# Check key permissions
chmod 600 ~/.ssh/optilab_key

# Verify user exists on target
```

### Database connection error
```bash
# Test connection
psql -h localhost -U postgres -d optilab -c "SELECT 1;"

# Check credentials in .env file
cat .env | grep DB_
```

## 📚 Documentation

- **Full Documentation**: See `collector/README.md`
- **Architecture**: See `docs/ARCHITECTURE_DIAGRAMS.md`
- **Setup Checklist**: See `SETUP_CHECKLIST.md`
- **Implementation Summary**: See `IMPLEMENTATION_SUMMARY.md`

## 🎯 Usage Patterns

### Daily Operations
```bash
# Check system status
psql -U postgres -d optilab -c "
SELECT status, COUNT(*) 
FROM systems 
GROUP BY status;"

# View recent collections
tail -f /var/log/optilab/collector.log
```

### Weekly Maintenance
```bash
# Scan for new systems
./scanner.sh 10.30.5.0/24 1

# Review offline systems
psql -U postgres -d optilab -c "
SELECT hostname, ip_address, updated_at 
FROM systems 
WHERE status = 'offline' 
ORDER BY updated_at DESC;"
```

### Monthly Analysis
```sql
-- Monthly utilization trends
SELECT 
  DATE_TRUNC('day', timestamp) as day,
  AVG(cpu_percent) as avg_cpu,
  AVG(ram_percent) as avg_ram,
  AVG(disk_percent) as avg_disk
FROM metrics
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY day
ORDER BY day;
```

## 🔒 Security Reminders

- ✅ Never commit `.env` file to git
- ✅ Use strong database passwords
- ✅ Rotate SSH keys regularly
- ✅ Restrict SSH access with firewall rules
- ✅ Keep scripts in secure location (chmod 700)

## 🚨 Common Issues

**Issue**: "Permission denied (publickey)"
**Fix**: Ensure SSH key is copied to target: `ssh-copy-id -i ~/.ssh/optilab_key.pub admin@target`

**Issue**: "Database connection refused"
**Fix**: Check PostgreSQL is running: `sudo systemctl status postgresql`

**Issue**: "Scan finds 0 systems"
**Fix**: Verify ICMP is allowed: `ping 10.30.5.10`

**Issue**: "Metrics show all zeros"
**Fix**: Check dependencies on target: `ssh admin@target 'command -v iostat'`

## 💡 Pro Tips

1. **Start small**: Test with a /28 subnet (14 IPs) before scanning /24 (254 IPs)
2. **Monitor logs**: Use `tail -f /var/log/optilab/*.log` to watch in real-time
3. **Queue for scale**: Enable message queue when monitoring > 50 systems
4. **Backup regularly**: Schedule `pg_dump` for database backups
5. **Document changes**: Keep notes on customizations in git

## 🎉 You're All Set!

OptiLab is now monitoring your lab computers. The system will:
- Discover new systems daily
- Collect metrics every 5 minutes
- Store data in PostgreSQL/TimescaleDB
- Track system status automatically

Need help? Check the full documentation in `/docs/` directory.

Happy monitoring! 📊🚀
