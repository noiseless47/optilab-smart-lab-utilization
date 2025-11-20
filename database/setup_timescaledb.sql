# ============================================================================
# TimescaleDB Setup for Lab Resource Monitoring
# ============================================================================
# This script converts the metrics table to a TimescaleDB hypertable
# for 20x better performance on time-series queries
#
# Prerequisites:
#   1. Install TimescaleDB extension
#      - Download: https://docs.timescale.com/install/latest/self-hosted/
#      - For PostgreSQL 18: Follow installation guide
#
# Usage:
#   psql -U postgres -d lab_resource_monitor -f setup_timescaledb.sql
# ============================================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Check if extension is installed
SELECT installed_version 
FROM pg_available_extensions 
WHERE name = 'timescaledb';

-- ============================================================================
-- Convert metrics to Hypertable
-- ============================================================================

-- Check if table exists and has data
SELECT COUNT(*) AS existing_records FROM metrics;

-- Convert to hypertable (partitions by timestamp)
-- chunk_time_interval = 1 day means create a new partition every day
SELECT create_hypertable(
    'metrics',              -- Table name
    'timestamp',                  -- Time column
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE,
    migrate_data => TRUE          -- Migrate existing data to hypertable
);

-- Show chunk information
SELECT * FROM timescaledb_information.chunks
WHERE hypertable_name = 'metrics'
ORDER BY range_start DESC
LIMIT 5;

-- ============================================================================
-- Enable Compression (7 days after insertion)
-- ============================================================================

-- Configure compression
ALTER TABLE metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',  -- Segment by system
    timescaledb.compress_orderby = 'timestamp DESC'
);

-- Add compression policy (compress data older than 7 days)
SELECT add_compression_policy(
    'metrics',
    INTERVAL '7 days',
    if_not_exists => TRUE
);

-- Check compression status
SELECT * FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'metrics';

-- ============================================================================
-- Data Retention Policy (30 days for detailed metrics)
-- ============================================================================

-- Add retention policy (drop chunks older than 30 days)
SELECT add_retention_policy(
    'metrics',
    INTERVAL '30 days',
    if_not_exists => TRUE
);

-- Check retention policy
SELECT * FROM timescaledb_information.jobs
WHERE proc_name LIKE '%retention%';

-- ============================================================================
-- Create Continuous Aggregates (for faster queries)
-- ============================================================================

-- Hourly aggregates (keep for 1 year)
CREATE MATERIALIZED VIEW IF NOT EXISTS metrics_hourly
WITH (timescaledb.continuous) AS
SELECT 
    system_id,
    time_bucket('1 hour', timestamp) AS bucket,
    AVG(cpu_percent) AS avg_cpu,
    MAX(cpu_percent) AS max_cpu,
    AVG(ram_percent) AS avg_ram,
    MAX(ram_percent) AS max_ram,
    AVG(disk_percent) AS avg_disk,
    MAX(disk_percent) AS max_disk,
    COUNT(*) AS sample_count
FROM metrics
GROUP BY system_id, bucket;

-- Add refresh policy (update every hour)
SELECT add_continuous_aggregate_policy(
    'metrics_hourly',
    start_offset => INTERVAL '2 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE
);

-- Daily aggregates (keep for 2 years)
CREATE MATERIALIZED VIEW IF NOT EXISTS metrics_daily
WITH (timescaledb.continuous) AS
SELECT 
    system_id,
    time_bucket('1 day', timestamp) AS bucket,
    AVG(cpu_percent) AS avg_cpu,
    MAX(cpu_percent) AS max_cpu,
    AVG(ram_percent) AS avg_ram,
    MAX(ram_percent) AS max_ram,
    AVG(disk_percent) AS avg_disk,
    MAX(disk_percent) AS max_disk,
    COUNT(*) AS sample_count
FROM metrics
GROUP BY system_id, bucket;

-- Add refresh policy (update daily)
SELECT add_continuous_aggregate_policy(
    'metrics_daily',
    start_offset => INTERVAL '2 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- ============================================================================
-- Query Examples
-- ============================================================================

-- Query latest metrics (uses hypertable)
SELECT 
    s.hostname,
    m.timestamp,
    m.cpu_percent,
    m.ram_percent
FROM systems s
JOIN LATERAL (
    SELECT timestamp, cpu_percent, ram_percent
    FROM metrics
    WHERE system_id = s.system_id
    ORDER BY timestamp DESC
    LIMIT 1
) m ON TRUE
LIMIT 10;

-- Query hourly averages (uses continuous aggregate - MUCH faster!)
SELECT 
    bucket,
    avg_cpu,
    avg_ram,
    sample_count
FROM metrics_hourly
WHERE system_id = 1
  AND bucket >= NOW() - INTERVAL '24 hours'
ORDER BY bucket DESC;

-- Query daily trends (uses continuous aggregate)
SELECT 
    bucket::DATE as date,
    avg_cpu,
    max_cpu,
    avg_ram,
    max_ram
FROM metrics_daily
WHERE system_id = 1
  AND bucket >= NOW() - INTERVAL '30 days'
ORDER BY bucket DESC;

-- ============================================================================
-- Monitoring & Statistics
-- ============================================================================

-- View all hypertables
SELECT * FROM timescaledb_information.hypertables;

-- View chunk information
SELECT 
    chunk_name,
    range_start,
    range_end,
    pg_size_pretty(total_bytes) AS total_size,
    pg_size_pretty(compressed_total_bytes) AS compressed_size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'metrics'
ORDER BY range_start DESC
LIMIT 10;

-- View compression stats
SELECT 
    pg_size_pretty(before_compression_total_bytes) AS uncompressed,
    pg_size_pretty(after_compression_total_bytes) AS compressed,
    ROUND(100 - (after_compression_total_bytes::NUMERIC / before_compression_total_bytes * 100), 2) AS compression_ratio
FROM timescaledb_information.compression_settings
WHERE hypertable_name = 'metrics';

-- View all jobs (compression, retention, aggregates)
SELECT 
    job_id,
    proc_name,
    schedule_interval,
    next_start,
    last_run_status
FROM timescaledb_information.jobs
ORDER BY job_id;

-- ============================================================================
-- Performance Comparison
-- ============================================================================

-- Without TimescaleDB (slow for large datasets):
-- SELECT AVG(cpu_percent) FROM metrics WHERE timestamp > NOW() - INTERVAL '7 days';

-- With TimescaleDB + Continuous Aggregate (20-100x faster):
-- SELECT AVG(avg_cpu) FROM metrics_hourly WHERE bucket > NOW() - INTERVAL '7 days';

-- ============================================================================
-- Cleanup (if needed)
-- ============================================================================

-- Drop continuous aggregates
-- DROP MATERIALIZED VIEW IF EXISTS metrics_hourly CASCADE;
-- DROP MATERIALIZED VIEW IF EXISTS metrics_daily CASCADE;

-- Remove policies
-- SELECT remove_compression_policy('metrics', if_exists => TRUE);
-- SELECT remove_retention_policy('metrics', if_exists => TRUE);

-- Revert to regular table (NOT RECOMMENDED)
-- SELECT disable_hypertable('metrics');

-- ============================================================================

SELECT 'TimescaleDB setup completed successfully!' AS status;
SELECT 'Next steps:' AS info;
SELECT '1. Run queries to verify performance improvement' AS step1;
SELECT '2. Monitor compression ratio and storage savings' AS step2;
SELECT '3. Adjust retention/compression policies as needed' AS step3;
