# Database Setup Guide

This guide provides step-by-step instructions for setting up the OptiLab Smart Lab Utilization database system.

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

### 1. Check Schema Creation

```sql
-- Verify tables exist
\dt

-- Check TimescaleDB setup
SELECT * FROM timescaledb_information.hypertables;

-- Verify continuous aggregates
SELECT * FROM timescaledb_information.continuous_aggregates;
```

### 2. Run Health Check

Execute the health check script:

```bash
psql -U postgres -d lab_resource_monitor -f database/health_check.sql
```

This will provide a comprehensive status report of your database.

## Sample Data

The schema.sql includes sample data for testing:

```sql
-- Check sample departments
SELECT * FROM departments;

-- Check sample systems
SELECT * FROM systems;

-- Check sample metrics
SELECT * FROM metrics LIMIT 10;
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

### Common Issues

**1. TimescaleDB Extension Not Found**
```sql
-- Check if extension exists
SELECT * FROM pg_available_extensions WHERE name = 'timescaledb';

-- If missing, install TimescaleDB
```

**2. Permission Denied**
```sql
-- Grant permissions
GRANT ALL PRIVILEGES ON DATABASE lab_resource_monitor TO lab_monitor;
GRANT ALL ON SCHEMA public TO lab_monitor;
```

**3. Hypertable Creation Failed**
```sql
-- Check if table exists and has data
SELECT COUNT(*) FROM metrics;

-- Drop and recreate if needed
DROP TABLE metrics CASCADE;
-- Then re-run schema.sql and setup_timescaledb.sql
```

**4. Continuous Aggregate Errors**
```sql
-- Check aggregate status
SELECT * FROM timescaledb_information.continuous_aggregates;

-- Refresh manually if needed
SELECT refresh_continuous_aggregate('hourly_performance_stats', NULL, NULL);
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
| `README.md` | This documentation |

---

**Last Updated:** November 2025
**Database Version:** 1.0