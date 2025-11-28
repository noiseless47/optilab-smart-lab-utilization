# Database Setup Guide

This guide provides step-by-step instructions for setting up the OptiLab Smart Lab Utilization database system.

Start postgresql 16
sudo systemctl restart postgresql@16-main

## Overview

The system uses PostgreSQL with TimescaleDB extension for time-series data optimization. The database consists of:

- **Core Schema**: Department, lab, and system management
- **Time-Series Metrics**: Performance monitoring data
- **Maintenance Logs**: System maintenance tracking
- **Performance Summaries**: Aggregated analytics

## Prerequisites

### 1. PostgreSQL Installation

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**macOS (with Homebrew):**
```bash
brew install postgresql
brew services start postgresql
```

**Windows:**
Download from [postgresql.org](https://www.postgresql.org/download/windows/)

### 2. TimescaleDB Installation

**Ubuntu/Debian:**
```bash
# Add TimescaleDB repository
sudo apt install gnupg postgresql-common apt-transport-https lsb-release wget
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh

# Add TimescaleDB repository
sudo sh -c "echo 'deb [signed-by=/usr/share/keyrings/timescale.key] https://packagecloud.io/timescale/timescale-ts/ubuntu/ $(lsb_release -c -s) main' > /etc/apt/sources.list.d/timescale.list"
wget --quiet -O - https://packagecloud.io/timescale/timescale-ts/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/timescale.key

sudo apt update
sudo apt install timescaledb-2-postgresql-15

# Enable TimescaleDB
sudo timescaledb-tune --quiet --yes
sudo systemctl restart postgresql
```

**macOS:**
```bash
brew install timescaledb
```

**Windows:**
Follow instructions at [docs.timescale.com](https://docs.timescale.com/install/latest/)

### 3. Verify Installation

```bash
# Check PostgreSQL version
psql --version

# Check TimescaleDB installation
psql -c "SELECT default_version, installed_version FROM pg_available_extensions WHERE name = 'timescaledb';"
```

## Database Setup

### Schema Update Modes

The database supports two update modes:

1. **Clean Recreation**: Drop all existing tables and recreate from scratch
   - Useful for major schema changes or development resets
   - Requires uncommenting the DROP section in `schema.sql`

2. **Incremental Update**: Update existing schema without data loss
   - Default behavior with DROP section commented out
   - Safe for production updates and minor changes

### 1. Create Database

```bash
# Connect as postgres user
sudo -u postgres psql

# Or if you have a password:
psql -U postgres
```

```sql
-- Create database
CREATE DATABASE lab_resource_monitor;

-- Create user (optional, for security)
CREATE USER lab_monitor WITH PASSWORD 'secure_password';
GRANT ALL PRIVILEGES ON DATABASE lab_resource_monitor TO lab_monitor;

-- Exit
\q
```

### 2. Connect to Database

```bash
# Connect to the database
psql -U postgres -d lab_resource_monitor

# Or with the created user:
psql -U lab_monitor -d lab_resource_monitor
```

### 3. Run Schema Setup

Execute the schema creation script:

```bash
psql -U postgres -d lab_resource_monitor -f database/schema.sql
```

**For Clean Schema Updates:**
If you need to recreate the schema from scratch (development/updates), uncomment the DROP TABLES section at the beginning of `schema.sql`:

```sql
-- Uncomment these lines in schema.sql before running:
/*
DROP VIEW IF EXISTS v_systems_overview CASCADE;
DROP VIEW IF EXISTS v_latest_metrics CASCADE;
...
DROP TABLE IF EXISTS performance_summaries CASCADE;
-- etc.
*/
```

Then run the schema script. This will drop all existing tables and recreate them cleanly.

**For Incremental Updates:**
Keep the DROP section commented out. The script uses `CREATE TABLE IF NOT EXISTS` and `CREATE OR REPLACE` statements, so it will only create missing tables/views and update existing ones.

This will create:
- All tables (departments, systems, metrics, etc.)
- Indexes for performance
- Views for easy querying
- Helper functions
- Sample data

### 4. Configure TimescaleDB

Execute the TimescaleDB setup script:

```bash
psql -U postgres -d lab_resource_monitor -f database/setup_timescaledb.sql
```

This will:
- Enable TimescaleDB extension
- Convert metrics table to hypertable
- Set up compression policies
- Create continuous aggregates for performance
- Configure data retention

### 5. Alternative TimescaleDB Setup

If you prefer the alternative setup:

```bash
psql -U postgres -d lab_resource_monitor -f database/timescale_setup.sql
```

## Verification

### 1. Comprehensive Schema Verification

Run these commands to verify all components are properly created:

```bash
# Connect to database
psql -U postgres -d lab_resource_monitor -c "

-- 1. Check all tables exist
SELECT schemaname, tablename, tableowner
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- 2. Verify TimescaleDB extension
SELECT name, default_version, installed_version, comment
FROM pg_available_extensions
WHERE name = 'timescaledb';

-- 3. Check hypertables
SELECT hypertable_name, num_chunks, compression_state
FROM timescaledb_information.hypertables;

-- 4. Verify continuous aggregates
SELECT view_name, materialization_hypertable_name, refresh_interval
FROM timescaledb_information.continuous_aggregates;

-- 5. Check compression policies
SELECT hypertable_name, policy_name, compress_after
FROM timescaledb_information.compression_settings;

-- 6. Check retention policies
SELECT hypertable_name, policy_name, drop_after
FROM timescaledb_information.retention_policies;

-- 7. Verify views exist
SELECT viewname, viewowner, definition
FROM pg_views
WHERE schemaname = 'public' AND viewname LIKE 'v_%'
ORDER BY viewname;

-- 8. Check indexes
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
ORDER BY tablename, indexname;
"
```

### 2. TimescaleDB Functionality Test

Test that TimescaleDB features work correctly:

```bash
# Test TimescaleDB functionality
psql -U postgres -d lab_resource_monitor -c "

-- 1. Test hypertable creation
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.hypertables
        WHERE hypertable_name = 'metrics'
    ) THEN
        RAISE EXCEPTION 'Hypertable metrics not found!';
    END IF;
    RAISE NOTICE '✓ Hypertable metrics exists';
END \$\$;

-- 2. Test continuous aggregates
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.continuous_aggregates
        WHERE view_name = 'hourly_performance_stats'
    ) THEN
        RAISE EXCEPTION 'Continuous aggregate hourly_performance_stats not found!';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.continuous_aggregates
        WHERE view_name = 'daily_performance_stats'
    ) THEN
        RAISE EXCEPTION 'Continuous aggregate daily_performance_stats not found!';
    END IF;
    RAISE NOTICE '✓ Continuous aggregates exist';
END \$\$;

-- 3. Test compression policy
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.compression_settings
        WHERE hypertable_name = 'metrics'
    ) THEN
        RAISE EXCEPTION 'Compression policy for metrics not found!';
    END IF;
    RAISE NOTICE '✓ Compression policy exists';
END \$\$;

-- 4. Test retention policy
DO \$\$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM timescaledb_information.retention_policies
        WHERE hypertable_name = 'metrics'
    ) THEN
        RAISE EXCEPTION 'Retention policy for metrics not found!';
    END IF;
    RAISE NOTICE '✓ Retention policy exists';
END \$\$;

SELECT 'All TimescaleDB features verified successfully!' as status;
"
```

### 3. Sample Data Insertion & Verification

Test the database with sample data:

```bash
# Insert sample data and verify
psql -U postgres -d lab_resource_monitor -c "

-- 1. Insert sample HOD
INSERT INTO hods (hod_name, hod_email) VALUES ('Dr. Smith', 'smith@rvce.edu.in')
ON CONFLICT (hod_email) DO NOTHING;

-- 2. Insert sample department
INSERT INTO departments (dept_name, dept_code, vlan_id, subnet_cidr, hod_id)
SELECT 'Computer Science', 'CSE', 31, '10.31.0.0/16'::cidr, hod_id
FROM hods WHERE hod_email = 'smith@rvce.edu.in'
ON CONFLICT (dept_name) DO NOTHING;

-- 3. Insert sample lab
INSERT INTO labs (lab_dept, lab_number)
SELECT dept_id, 101 FROM departments WHERE dept_code = 'CSE'
ON CONFLICT DO NOTHING;

-- 4. Insert sample system
INSERT INTO systems (system_number, lab_id, dept_id, hostname, ip_address, mac_address, cpu_model, cpu_cores, ram_total_gb, disk_total_gb, status)
SELECT 1, l.lab_id, l.lab_dept, 'labpc-101-01', '192.168.1.101'::inet, '00:11:22:33:44:55'::macaddr, 'Intel i7', 8, 16, 512, 'active'
FROM labs l
JOIN departments d ON l.lab_dept = d.dept_id
WHERE d.dept_code = 'CSE' AND l.lab_number = 101
ON CONFLICT (ip_address) DO NOTHING;

-- 5. Insert sample metrics (multiple entries to test aggregation)
DO \$\$
DECLARE
    sys_id INTEGER;
    i INTEGER := 0;
BEGIN
    SELECT system_id INTO sys_id FROM systems WHERE hostname = 'labpc-101-01' LIMIT 1;

    IF sys_id IS NOT NULL THEN
        -- Insert metrics for the last 2 hours (every 5 minutes)
        FOR i IN 0..23 LOOP
            INSERT INTO metrics (
                system_id, cpu_percent, ram_percent, disk_percent,
                network_sent_mbps, network_recv_mbps, gpu_percent,
                uptime_seconds, logged_in_users, collection_method
            ) VALUES (
                sys_id,
                20 + (random() * 60)::numeric(5,2),  -- CPU: 20-80%
                30 + (random() * 50)::numeric(5,2),  -- RAM: 30-80%
                10 + (random() * 30)::numeric(5,2),  -- Disk: 10-40%
                random() * 100,                      -- Network sent
                random() * 200,                      -- Network recv
                random() * 50,                       -- GPU
                3600 + (i * 300),                    -- Uptime
                (random() * 5)::integer,             -- Users
                'wmi'
            );
        END LOOP;
    END IF;
END \$\$;

-- 6. Verify data insertion
SELECT 'Sample data inserted successfully!' as status;
"
```

### 4. Aggregation Verification

Test that continuous aggregates work:

```bash
# Verify aggregations work
psql -U postgres -d lab_resource_monitor -c "

-- Wait a moment for aggregations to process (in production this happens automatically)
SELECT pg_sleep(2);

-- 1. Check raw metrics count
SELECT COUNT(*) as raw_metrics_count FROM metrics;

-- 2. Check hourly aggregations
SELECT
    system_id,
    COUNT(*) as hourly_records,
    MIN(hour_bucket) as earliest_hour,
    MAX(hour_bucket) as latest_hour
FROM hourly_performance_stats
GROUP BY system_id;

-- 3. Check daily aggregations
SELECT
    system_id,
    COUNT(*) as daily_records,
    MIN(day_bucket)::date as earliest_day,
    MAX(day_bucket)::date as latest_day
FROM daily_performance_stats
GROUP BY system_id;

-- 4. Verify aggregation calculations
SELECT
    system_id,
    hour_bucket,
    avg_cpu_percent,
    max_cpu_percent,
    p95_cpu_percent,
    metric_count
FROM hourly_performance_stats
WHERE system_id IN (SELECT system_id FROM systems WHERE hostname = 'labpc-101-01')
ORDER BY hour_bucket DESC
LIMIT 5;

-- 5. Test retention policy
SELECT
    hypertable_name,
    pg_size_pretty(total_bytes) as total_size,
    pg_size_pretty(compressed_total_bytes) as compressed_size
FROM (
    SELECT
        hypertable_name,
        SUM(total_bytes) as total_bytes,
        SUM(compressed_total_bytes) as compressed_total_bytes
    FROM timescaledb_information.chunks
    WHERE hypertable_name = 'metrics'
    GROUP BY hypertable_name
) stats;

SELECT 'Aggregation verification completed!' as status;
"
```

### 5. Run Health Check

Execute the health check script:

```bash
psql -U postgres -d lab_resource_monitor -f database/health_check.sql
```

This will provide a comprehensive status report of your database.

## Sample Data & Testing

### Quick Verification Script

Run this comprehensive test script to verify everything works:

```bash
#!/bin/bash
# Comprehensive database verification script

DB_NAME="lab_resource_monitor"
DB_USER="postgres"

echo "=== OptiLab Database Verification ==="
echo

# Function to run psql command
run_psql() {
    psql -U $DB_USER -d $DB_NAME -c "$1" 2>/dev/null
}

echo "1. Checking database connection..."
if run_psql "SELECT 'Database connected successfully!' as status;"; then
    echo "✓ Database connection OK"
else
    echo "✗ Database connection failed"
    exit 1
fi

echo
echo "2. Verifying core tables..."
TABLES=("hods" "departments" "labs" "systems" "metrics" "maintenance_logs" "performance_summaries")
for table in "${TABLES[@]}"; do
    if run_psql "SELECT COUNT(*) as count FROM $table;" >/dev/null 2>&1; then
        COUNT=$(run_psql "SELECT COUNT(*) as count FROM $table;" | grep -E '^[0-9]+$' | head -1)
        echo "✓ Table $table exists ($COUNT records)"
    else
        echo "✗ Table $table missing or inaccessible"
    fi
done

echo
echo "3. Checking TimescaleDB features..."
if run_psql "SELECT COUNT(*) FROM timescaledb_information.hypertables WHERE hypertable_name = 'metrics';" | grep -q "1"; then
    echo "✓ Hypertable 'metrics' configured"
else
    echo "✗ Hypertable 'metrics' not found"
fi

if run_psql "SELECT COUNT(*) FROM timescaledb_information.continuous_aggregates WHERE view_name IN ('hourly_performance_stats', 'daily_performance_stats');" | grep -q "2"; then
    echo "✓ Continuous aggregates configured"
else
    echo "✗ Continuous aggregates missing"
fi

echo
echo "4. Testing data insertion..."
# Insert test data
run_psql "
DO \$\$
DECLARE
    hod_id_val INTEGER;
    dept_id_val INTEGER;
    lab_id_val INTEGER;
    sys_id_val INTEGER;
BEGIN
    -- Insert test HOD
    INSERT INTO hods (hod_name, hod_email) VALUES ('Test HOD', 'test@rvce.edu.in')
    ON CONFLICT (hod_email) DO NOTHING
    RETURNING hod_id INTO hod_id_val;

    -- Insert test department
    INSERT INTO departments (dept_name, dept_code, hod_id) VALUES ('Test Dept', 'TST', hod_id_val)
    ON CONFLICT (dept_name) DO NOTHING
    RETURNING dept_id INTO dept_id_val;

    -- Insert test lab
    INSERT INTO labs (lab_dept, lab_number) VALUES (dept_id_val, 999)
    ON CONFLICT DO NOTHING
    RETURNING lab_id INTO lab_id_val;

    -- Insert test system
    INSERT INTO systems (system_number, lab_id, dept_id, hostname, ip_address, mac_address, status)
    VALUES (999, lab_id_val, dept_id_val, 'test-system', '192.168.999.999'::inet, 'FF:FF:FF:FF:FF:FF'::macaddr, 'active')
    ON CONFLICT (ip_address) DO NOTHING
    RETURNING system_id INTO sys_id_val;

    -- Insert test metrics
    IF sys_id_val IS NOT NULL THEN
        INSERT INTO metrics (system_id, cpu_percent, ram_percent, disk_percent, collection_method)
        VALUES (sys_id_val, 50.0, 60.0, 30.0, 'test');
    END IF;

    RAISE NOTICE 'Test data insertion completed';
END \$\$;
"

echo "✓ Test data insertion completed"

echo
echo "5. Verifying data relationships..."
# Check referential integrity
RELATIONSHIP_CHECKS=(
    "Systems with valid departments: SELECT COUNT(*) FROM systems s JOIN departments d ON s.dept_id = d.dept_id;"
    "Labs with valid departments: SELECT COUNT(*) FROM labs l JOIN departments d ON l.lab_dept = d.dept_id;"
    "Systems with valid labs: SELECT COUNT(*) FROM systems s LEFT JOIN labs l ON s.lab_id = l.lab_id WHERE s.lab_id IS NOT NULL;"
)

for check in "${RELATIONSHIP_CHECKS[@]}"; do
    if run_psql "$check" >/dev/null 2>&1; then
        echo "✓ Relationship check passed"
    else
        echo "✗ Relationship check failed: $check"
    fi
done

echo
echo "6. Testing TimescaleDB aggregations..."
# Test that aggregations work
if run_psql "SELECT COUNT(*) FROM hourly_performance_stats;" >/dev/null 2>&1; then
    HOURLY_COUNT=$(run_psql "SELECT COUNT(*) FROM hourly_performance_stats;" 2>/dev/null | grep -E '^[0-9]+$' | head -1)
    echo "✓ Hourly aggregations working ($HOURLY_COUNT records)"
else
    echo "✗ Hourly aggregations not working"
fi

if run_psql "SELECT COUNT(*) FROM daily_performance_stats;" >/dev/null 2>&1; then
    DAILY_COUNT=$(run_psql "SELECT COUNT(*) FROM daily_performance_stats;" 2>/dev/null | grep -E '^[0-9]+$' | head -1)
    echo "✓ Daily aggregations working ($DAILY_COUNT records)"
else
    echo "✗ Daily aggregations not working"
fi

echo
echo "=== Verification Complete ==="
echo "If all checks show ✓, your database is properly configured!"
```

### Sample Data Queries

After running the verification script, check the inserted data:

```bash
# Check all tables have data
psql -U postgres -d lab_resource_monitor -c "
SELECT 'HODs: ' || COUNT(*) FROM hods
UNION ALL
SELECT 'Departments: ' || COUNT(*) FROM departments
UNION ALL
SELECT 'Labs: ' || COUNT(*) FROM labs
UNION ALL
SELECT 'Systems: ' || COUNT(*) FROM systems
UNION ALL
SELECT 'Metrics: ' || COUNT(*) FROM metrics;
"

# Check TimescaleDB aggregations
psql -U postgres -d lab_resource_monitor -c "
SELECT 'Hourly aggregates: ' || COUNT(*) FROM hourly_performance_stats
UNION ALL
SELECT 'Daily aggregates: ' || COUNT(*) FROM daily_performance_stats;
"
```

## Database Structure

### Core Tables

| Table | Purpose |
|-------|---------|
| `hods` | Head of Departments information |
| `departments` | Academic departments with network config |
| `labs` | Laboratory information |
| `lab_assistants` | Lab assistant details |
| `systems` | Discovered computer systems |
| `network_scans` | Network discovery scan history |
| `collection_credentials` | Encrypted access credentials |
| `metrics` | Time-series performance data |
| `maintenance_logs` | System maintenance records |
| `performance_summaries` | Aggregated performance statistics |

### Key Views

| View | Purpose |
|------|---------|
| `v_systems_overview` | Systems with department info |
| `v_latest_metrics` | Latest metrics per system |
| `v_department_stats` | Department-level statistics |

### TimescaleDB Features

- **Hypertable**: `metrics` table partitioned by time
- **Compression**: Automatic compression after 7 days
- **Retention**: Data kept for 30 days (configurable)
- **Continuous Aggregates**:
  - `hourly_performance_stats`: Hourly summaries
  - `daily_performance_stats`: Daily summaries

## Configuration

### PostgreSQL Settings

For optimal performance with TimescaleDB, update `postgresql.conf`:

```ini
# Memory (adjust based on your system)
shared_buffers = 4GB
effective_cache_size = 12GB
work_mem = 32MB
maintenance_work_mem = 512MB

# TimescaleDB
timescaledb.max_background_workers = 8
max_worker_processes = 16
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# WAL
checkpoint_timeout = 15min
max_wal_size = 2GB
min_wal_size = 512MB
wal_buffers = 16MB
wal_compression = on

# Query planning
random_page_cost = 1.1
effective_io_concurrency = 200
```

Restart PostgreSQL after changes:

```bash
sudo systemctl restart postgresql
```

### TimescaleDB Tuning

```bash
# Run tuning script
sudo timescaledb-tune --quiet --yes
sudo systemctl restart postgresql
```

## Backup and Recovery

### Backup

```bash
# Full database backup
pg_dump -U postgres -d lab_resource_monitor > lab_monitor_backup.sql

# Compressed backup
pg_dump -U postgres -d lab_resource_monitor | gzip > lab_monitor_backup.sql.gz
```

### Restore

```bash
# Restore from backup
psql -U postgres -d lab_resource_monitor < lab_monitor_backup.sql

# From compressed backup
gunzip -c lab_monitor_backup.sql.gz | psql -U postgres -d lab_resource_monitor
```

## Monitoring

### Regular Health Checks

Run the health check script weekly:

```bash
psql -U postgres -d lab_resource_monitor -f database/health_check.sql
```

### Key Metrics to Monitor

- Database size growth
- TimescaleDB compression ratios
- Query performance
- System health status
- Data collection status

## Troubleshooting

### Quick Diagnosis Script

Run this script to diagnose common issues:

```bash
#!/bin/bash
# Database diagnosis script

DB_NAME="lab_resource_monitor"
DB_USER="postgres"

echo "=== Database Diagnosis ==="

# Check if database exists
if psql -U $DB_USER -l | grep -q $DB_NAME; then
    echo "✓ Database $DB_NAME exists"
else
    echo "✗ Database $DB_NAME does not exist"
    echo "Run: createdb -U $DB_USER $DB_NAME"
    exit 1
fi

# Check TimescaleDB extension
if psql -U $DB_USER -d $DB_NAME -c "SELECT 1 FROM pg_extension WHERE extname = 'timescaledb';" | grep -q "1"; then
    echo "✓ TimescaleDB extension loaded"
else
    echo "✗ TimescaleDB extension not loaded"
    echo "Run: psql -U $DB_USER -d $DB_NAME -c 'CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;'"
fi

# Check core tables
TABLES=("hods" "departments" "labs" "systems" "metrics")
for table in "${TABLES[@]}"; do
    if psql -U $DB_USER -d $DB_NAME -c "SELECT 1 FROM $table LIMIT 1;" >/dev/null 2>&1; then
        echo "✓ Table $table exists"
    else
        echo "✗ Table $table missing"
    fi
done

# Check TimescaleDB features
if psql -U $DB_USER -d $DB_NAME -c "SELECT 1 FROM timescaledb_information.hypertables WHERE hypertable_name = 'metrics';" | grep -q "1"; then
    echo "✓ Hypertable configured"
else
    echo "✗ Hypertable not configured"
fi

echo "=== Diagnosis Complete ==="
```

### Common Issues

**1. TimescaleDB Extension Not Found**
```bash
# Check if extension exists
psql -U postgres -d lab_resource_monitor -c "SELECT * FROM pg_available_extensions WHERE name = 'timescaledb';"

# If missing, install TimescaleDB and run:
psql -U postgres -d lab_resource_monitor -c "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;"
```

**2. Permission Denied**
```bash
# Grant permissions
psql -U postgres -d lab_resource_monitor -c "
GRANT ALL PRIVILEGES ON DATABASE lab_resource_monitor TO lab_monitor;
GRANT ALL ON SCHEMA public TO lab_monitor;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO lab_monitor;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO lab_monitor;
"
```

**3. Hypertable Creation Failed**
```bash
# Check if table exists and has data
psql -U postgres -d lab_resource_monitor -c "SELECT COUNT(*) FROM metrics;"

# If issues, drop and recreate
psql -U postgres -d lab_resource_monitor -c "
DROP TABLE IF EXISTS metrics CASCADE;
-- Then re-run schema.sql and setup_timescaledb.sql
"
```

**4. Continuous Aggregate Errors**
```bash
# Check aggregate status
psql -U postgres -d lab_resource_monitor -c "SELECT * FROM timescaledb_information.continuous_aggregates;"

# Refresh manually if needed
psql -U postgres -d lab_resource_monitor -c "SELECT refresh_continuous_aggregate('hourly_performance_stats', NULL, NULL);"
psql -U postgres -d lab_resource_monitor -c "SELECT refresh_continuous_aggregate('daily_performance_stats', NULL, NULL);"
```

**5. Aggregation Not Working**
```bash
# Check if background workers are running
psql -U postgres -d lab_resource_monitor -c "SELECT * FROM timescaledb_information.jobs WHERE proc_name LIKE '%continuous%';"

# Manually trigger aggregation
psql -U postgres -d lab_resource_monitor -c "
SELECT refresh_continuous_aggregate('hourly_performance_stats', NOW() - INTERVAL '2 hours', NOW());
SELECT refresh_continuous_aggregate('daily_performance_stats', NOW() - INTERVAL '2 days', NOW());
"
```

### Performance Issues

**Slow Queries:**
- Check if TimescaleDB is properly configured
- Verify indexes are created
- Run `ANALYZE` on tables

**High Disk Usage:**
- Check compression status
- Adjust retention policies
- Monitor chunk sizes

## Security

### Production Setup

1. **Use Strong Passwords**
```sql
ALTER USER lab_monitor PASSWORD 'very_strong_password';
```

2. **Restrict Network Access**
Update `pg_hba.conf` to allow only necessary connections.

3. **Enable SSL**
Configure SSL certificates for encrypted connections.

4. **Regular Updates**
Keep PostgreSQL and TimescaleDB updated with security patches.

## Support

For issues or questions:
1. Check the health check output for diagnostics
2. Review PostgreSQL logs: `/var/log/postgresql/`
3. Consult TimescaleDB documentation: [docs.timescale.com](https://docs.timescale.com)

## File Reference

| File | Purpose |
|------|---------|
| `schema.sql` | Core database schema and sample data |
| `setup_timescaledb.sql` | TimescaleDB configuration and optimization |
| `timescale_setup.sql` | Alternative TimescaleDB setup |
| `health_check.sql` | Database health monitoring script |
| `README.md` | This documentation with setup scripts |

## Quick Setup Commands

For experienced users, here's the complete setup in one go:

```bash
# 1. Install PostgreSQL and TimescaleDB (Ubuntu/Debian)
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo sh -c "echo 'deb [signed-by=/usr/share/keyrings/timescale.key] https://packagecloud.io/timescale/timescale-ts/ubuntu/ $(lsb_release -c -s) main' > /etc/apt/sources.list.d/timescale.list"
wget --quiet -O - https://packagecloud.io/timescale/timescale-ts/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/timescale.key
sudo apt update
sudo apt install timescaledb-2-postgresql-15
sudo timescaledb-tune --quiet --yes
sudo systemctl restart postgresql

# 2. Create database and user
sudo -u postgres psql -c "CREATE DATABASE lab_resource_monitor;"
sudo -u postgres psql -c "CREATE USER lab_monitor WITH PASSWORD 'secure_password';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE lab_resource_monitor TO lab_monitor;"

# 3. Run setup scripts
psql -U postgres -d lab_resource_monitor -f database/schema.sql
psql -U postgres -d lab_resource_monitor -f database/setup_timescaledb.sql

# 4. Verify setup
psql -U postgres -d lab_resource_monitor -c "
SELECT 'Tables: ' || COUNT(*) FROM information_schema.tables WHERE table_schema = 'public'
UNION ALL
SELECT 'Hypertables: ' || COUNT(*) FROM timescaledb_information.hypertables
UNION ALL
SELECT 'Continuous Aggregates: ' || COUNT(*) FROM timescaledb_information.continuous_aggregates;
"

echo "Setup complete! Run the verification script to test everything."
```

---

**Last Updated:** November 2025
**Database Version:** 1.0