# OptiLab Setup Checklist

## ✅ Pre-Implementation Checklist

### Infrastructure Requirements
- [ ] PostgreSQL 18+ installed and running
- [ ] TimescaleDB extension available (optional but recommended)
- [ ] Network access to target systems (ICMP, SSH)
- [ ] Bastion/jump host for running scripts
- [ ] SSH access to target lab computers

### Software Dependencies
- [ ] bash (4.0+)
- [ ] psql (PostgreSQL client)
- [ ] ssh, scp (OpenSSH client)
- [ ] ping utility
- [ ] jq (for JSON parsing)
- [ ] Python 3.8+ (for queue consumer)

Optional:
- [ ] nmap (for faster network scanning)
- [ ] arp-scan (for local network scanning)
- [ ] RabbitMQ or Redis (for message queue)

---

## ✅ Installation Checklist

### 1. Database Setup
- [ ] Create database: `CREATE DATABASE optilab;`
- [ ] Run schema: `psql -U postgres -d optilab -f database/schema.sql`
- [ ] Enable TimescaleDB: `psql -U postgres -d optilab -f database/setup_timescaledb.sql`
- [ ] Verify tables: `\dt` in psql
- [ ] Test connection from bastion host

### 2. Script Setup
- [ ] Clone/download repository to bastion host
- [ ] Navigate to collector directory: `cd collector/`
- [ ] Copy environment template: `cp .env.example .env`
- [ ] Edit .env with your credentials
- [ ] Make scripts executable:
  ```bash
  chmod +x scanner.sh
  chmod +x metrics_collector.sh
  chmod +x ssh_script.sh
  chmod +x queue_setup.sh
  ```

### 3. SSH Configuration
- [ ] Generate SSH key pair: `ssh-keygen -t rsa -b 4096 -f ~/.ssh/optilab_key`
- [ ] Set correct permissions: `chmod 600 ~/.ssh/optilab_key`
- [ ] Create SSH user on target systems (e.g., `labmonitor`)
- [ ] Copy public key to target systems:
  ```bash
  for ip in 10.30.5.{10..20}; do
    ssh-copy-id -i ~/.ssh/optilab_key.pub labmonitor@$ip
  done
  ```
- [ ] Test SSH connection: `ssh -i ~/.ssh/optilab_key labmonitor@10.30.5.10`
- [ ] Verify passwordless access works

### 4. Python Dependencies (if using queue)
- [ ] Install Python 3.8+: `python3 --version`
- [ ] Install pip: `sudo apt-get install python3-pip` (Debian/Ubuntu)
- [ ] Install dependencies: `pip3 install -r requirements.txt`
- [ ] Verify installation: `python3 -c "import pika, redis, psycopg2"`

### 5. Message Queue Setup (Optional)
- [ ] Install RabbitMQ:
  ```bash
  docker run -d --name rabbitmq \
    -p 5672:5672 -p 15672:15672 \
    rabbitmq:3-management
  ```
  OR
  ```bash
  sudo apt-get install rabbitmq-server
  sudo systemctl start rabbitmq-server
  ```
- [ ] Access management UI: http://localhost:15672 (guest/guest)
- [ ] Run queue setup: `./queue_setup.sh rabbitmq`
- [ ] Verify queues created

---

## ✅ Testing Checklist

### Test 1: Database Connectivity
```bash
# Set environment variables
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=optilab
export DB_USER=postgres
export DB_PASSWORD=your_password

# Test connection
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "SELECT 1;"
```
- [ ] Connection successful
- [ ] Can query tables

### Test 2: Scanner Script
```bash
# Scan a small subnet (replace with your network)
./scanner.sh 10.30.5.0/28 1 ping
```
- [ ] Script runs without errors
- [ ] Discovers alive systems
- [ ] Creates entry in `network_scans` table
- [ ] Registers systems in `systems` table
- [ ] Check results:
  ```sql
  SELECT * FROM network_scans ORDER BY scan_id DESC LIMIT 1;
  SELECT * FROM systems WHERE dept_id = 1 ORDER BY created_at DESC;
  ```

### Test 3: Metrics Collector (Local)
```bash
# Run locally to test output
./metrics_collector.sh
```
- [ ] Returns valid JSON
- [ ] Contains all expected fields (cpu, ram, disk, network)
- [ ] Values are reasonable (0-100 for percentages)
- [ ] Can parse with jq: `./metrics_collector.sh | jq .`

### Test 4: SSH Collection (Single System)
```bash
# Collect from one system
./ssh_script.sh --single 10.30.5.10 \
  --user labmonitor \
  --key ~/.ssh/optilab_key
```
- [ ] SSH connection successful
- [ ] Script transferred
- [ ] Metrics collected
- [ ] JSON parsed correctly
- [ ] Data inserted into `metrics` table
- [ ] Check results:
  ```sql
  SELECT * FROM metrics 
  WHERE system_id = (SELECT system_id FROM systems WHERE ip_address = '10.30.5.10')
  ORDER BY timestamp DESC LIMIT 1;
  ```

### Test 5: SSH Collection (All Systems)
```bash
# Collect from all discovered systems
./ssh_script.sh --all \
  --user labmonitor \
  --key ~/.ssh/optilab_key
```
- [ ] Iterates through all systems
- [ ] Handles failures gracefully
- [ ] Updates system status (active/offline)
- [ ] Inserts metrics for successful collections
- [ ] Shows summary at end

### Test 6: Queue Integration (Optional)
```bash
# Start consumer in background
python3 queue_consumer.py metrics &
CONSUMER_PID=$!

# Collect with queue enabled
./ssh_script.sh --single 10.30.5.10 --queue-enabled

# Wait a moment for processing
sleep 5

# Check database for metrics
# Stop consumer
kill $CONSUMER_PID
```
- [ ] Consumer starts without errors
- [ ] Messages published to queue
- [ ] Consumer processes messages
- [ ] Data appears in database
- [ ] Queue depth returns to zero

---

## ✅ Production Readiness Checklist

### Security Hardening
- [ ] Change default database password
- [ ] Use dedicated database user with limited privileges:
  ```sql
  CREATE USER optilab_collector WITH PASSWORD 'strong_password';
  GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO optilab_collector;
  ```
- [ ] Restrict SSH key permissions: `chmod 600 ~/.ssh/optilab_key`
- [ ] Enable SSH strict host key checking (edit scripts)
- [ ] Use firewall rules to limit SSH access
- [ ] Enable database SSL/TLS connections
- [ ] Rotate SSH keys periodically

### Monitoring & Logging
- [ ] Set up log directory: `sudo mkdir -p /var/log/optilab`
- [ ] Configure log rotation: `/etc/logrotate.d/optilab`
- [ ] Monitor script execution (cron emails)
- [ ] Set up alerts for failed collections
- [ ] Monitor queue depth (if using queue)
- [ ] Track database growth

### Automation
- [ ] Create cron jobs for regular collection:
  ```bash
  # Scan network daily at 2 AM
  0 2 * * * cd /opt/optilab/collector && ./scanner.sh 10.30.5.0/24 1 >> /var/log/optilab/scanner.log 2>&1
  
  # Collect metrics every 5 minutes
  */5 * * * * cd /opt/optilab/collector && ./ssh_script.sh --all >> /var/log/optilab/collector.log 2>&1
  ```
- [ ] Create systemd service for queue consumer:
  ```bash
  sudo cp /opt/optilab/systemd/optilab-consumer.service /etc/systemd/system/
  sudo systemctl enable optilab-consumer
  sudo systemctl start optilab-consumer
  ```
- [ ] Set up automatic restarts on failure
- [ ] Configure email notifications for errors

### Performance Optimization
- [ ] Index verification: Check EXPLAIN ANALYZE on queries
- [ ] Enable TimescaleDB compression for old metrics
- [ ] Set up data retention policy (archive old metrics)
- [ ] Configure connection pooling for database
- [ ] Consider parallel SSH collection for large deployments
- [ ] Optimize scan frequency based on needs

### Backup & Recovery
- [ ] Set up automated database backups:
  ```bash
  pg_dump -U postgres optilab > /backups/optilab_$(date +%Y%m%d).sql
  ```
- [ ] Test restore procedure
- [ ] Backup SSH keys securely
- [ ] Document recovery procedures
- [ ] Store backups off-site

### Documentation
- [ ] Document network topology (subnets, VLANs)
- [ ] List all monitored systems
- [ ] Document SSH key locations
- [ ] Create runbook for common issues
- [ ] Train team members on usage
- [ ] Document escalation procedures

---

## ✅ Post-Deployment Verification

### Week 1: Initial Monitoring
- [ ] Verify daily scans complete successfully
- [ ] Check metrics collection rate (should match cron schedule)
- [ ] Monitor database growth rate
- [ ] Verify no SSH failures
- [ ] Check for any error logs
- [ ] Validate data quality (no null values, reasonable ranges)

### Week 2: Performance Review
- [ ] Review query performance
- [ ] Check collection duration trends
- [ ] Verify all systems being monitored
- [ ] Identify any problematic systems
- [ ] Optimize cron timing if needed

### Month 1: Full Audit
- [ ] Review all discovered systems vs expected
- [ ] Analyze metrics coverage (% of time with data)
- [ ] Review and tune alert thresholds
- [ ] Check disk space usage trends
- [ ] Update documentation with lessons learned
- [ ] Plan for scaling if needed

---

## ✅ Troubleshooting Checklist

### If Scanner Fails
- [ ] Check network connectivity: `ping target_ip`
- [ ] Verify database credentials
- [ ] Check CIDR notation is correct
- [ ] Review scanner.log for errors
- [ ] Test manually: `psql -h ... -c "SELECT 1;"`

### If SSH Collection Fails
- [ ] Test SSH manually: `ssh -i key user@ip`
- [ ] Check SSH key permissions: `ls -l ~/.ssh/`
- [ ] Verify target system is reachable: `ping ip`
- [ ] Check if user exists on target
- [ ] Review ssh_script.log for details
- [ ] Check if metrics_collector.sh is readable

### If Metrics Are Invalid
- [ ] Run metrics_collector.sh locally
- [ ] Check for missing dependencies on target
- [ ] Verify sufficient permissions
- [ ] Check system compatibility (Linux vs macOS)
- [ ] Validate JSON output: `./metrics_collector.sh | jq .`

### If Queue Consumer Fails
- [ ] Check queue service is running
- [ ] Verify network connectivity to queue
- [ ] Check consumer logs
- [ ] Test queue connection manually
- [ ] Verify database credentials in consumer
- [ ] Check for message format errors

---

## ✅ Maintenance Checklist (Monthly)

- [ ] Review system status in database
- [ ] Remove decommissioned systems from monitoring
- [ ] Rotate SSH keys if needed
- [ ] Update documentation
- [ ] Review and archive old metrics
- [ ] Check disk space usage
- [ ] Update scripts if needed
- [ ] Review security logs
- [ ] Test backup restoration
- [ ] Update dependencies (pip, apt packages)

---

## ✅ Upgrade Checklist (When Scaling)

### Adding More Systems
- [ ] Verify network access to new systems
- [ ] Deploy SSH keys to new systems
- [ ] Update department/lab mappings in database
- [ ] Run scanner on new subnet
- [ ] Verify collection includes new systems

### Adding More Collectors
- [ ] Deploy scripts to new bastion host
- [ ] Configure with same credentials
- [ ] Partition systems across collectors
- [ ] Set up coordination to avoid duplicates
- [ ] Monitor for conflicts

### Enabling Message Queue
- [ ] Install and configure RabbitMQ/Redis
- [ ] Run queue_setup.sh
- [ ] Start queue consumers
- [ ] Update scripts to use --queue-enabled
- [ ] Monitor queue depth and processing
- [ ] Gradually migrate from direct writes

---

## 📊 Success Criteria

The system is successfully deployed when:

✅ All target systems discovered and registered
✅ Metrics collected every 5 minutes (or your interval)
✅ < 1% collection failure rate
✅ Database queries respond in < 1 second
✅ Automated monitoring runs without intervention
✅ Team can access and understand the data
✅ Alerts trigger for critical issues
✅ Backup and recovery tested and verified

---

## 📞 Support Resources

- **Documentation**: `/docs/` directory
- **Schema Reference**: `database/schema.sql`
- **Architecture**: `docs/ARCHITECTURE_DIAGRAMS.md`
- **Message Queue**: `docs/MESSAGE_QUEUE.md`
- **Collector Guide**: `collector/README.md`
- **Implementation Summary**: `IMPLEMENTATION_SUMMARY.md`

---

## 🎯 Next Steps

After completing this checklist:

1. **Monitor** - Watch the system for first week
2. **Optimize** - Tune based on actual performance
3. **Extend** - Add alerts, dashboards, analytics
4. **Document** - Record any customizations
5. **Train** - Ensure team knows how to use it

Good luck with your OptiLab deployment! 🚀
