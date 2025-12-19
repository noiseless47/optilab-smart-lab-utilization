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
-- Create Continuous Aggregates for Performance
-- ============================================================================

-- Hourly Performance Summaries
CREATE MATERIALIZED VIEW IF NOT EXISTS hourly_performance_stats
WITH (timescaledb.continuous) AS
SELECT
    system_id,
    time_bucket('1 hour', timestamp) AS hour_bucket,
    AVG(cpu_percent) AS avg_cpu_percent,
    MAX(cpu_percent) AS max_cpu_percent,
    MIN(cpu_percent) AS min_cpu_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent) AS p95_cpu_percent,
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent) AS p95_ram_percent,
    AVG(gpu_percent) AS avg_gpu_percent,
    MAX(gpu_percent) AS max_gpu_percent,
    AVG(disk_percent) AS avg_disk_percent,
    MAX(disk_percent) AS max_disk_percent,
    COUNT(*) AS metric_count
FROM metrics
GROUP BY system_id, hour_bucket;

-- Add refresh policy (refresh every hour, covering last 2 hours)
SELECT add_continuous_aggregate_policy('hourly_performance_stats',
    start_offset => INTERVAL '2 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE);

-- Daily Performance Summaries
CREATE MATERIALIZED VIEW IF NOT EXISTS daily_performance_stats
WITH (timescaledb.continuous) AS
SELECT
    system_id,
    time_bucket('1 day', timestamp) AS day_bucket,
    AVG(cpu_percent) AS avg_cpu_percent,
    MAX(cpu_percent) AS max_cpu_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent) AS p95_cpu_percent,
    SUM(CASE WHEN cpu_percent > 80 THEN 1 ELSE 0 END) * 5 AS cpu_above_80_minutes,
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent) AS p95_ram_percent,
    SUM(CASE WHEN ram_percent > 80 THEN 1 ELSE 0 END) * 5 AS ram_above_80_minutes,
    AVG(gpu_percent) AS avg_gpu_percent,
    MAX(gpu_percent) AS max_gpu_percent,
    AVG(disk_percent) AS avg_disk_percent,
    MAX(disk_percent) AS max_disk_percent,
    COUNT(*) AS metric_count
FROM metrics
GROUP BY system_id, day_bucket;

-- Add refresh policy (refresh daily, covering last 2 days)
SELECT add_continuous_aggregate_policy('daily_performance_stats',
    start_offset => INTERVAL '2 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

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

-- Query hourly performance stats (uses continuous aggregate - MUCH faster!)
SELECT
    hour_bucket,
    avg_cpu_percent,
    max_cpu_percent,
    p95_cpu_percent,
    metric_count
FROM hourly_performance_stats
WHERE system_id = 1
  AND hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY hour_bucket DESC;

-- Query daily performance trends (uses continuous aggregate)
SELECT
    day_bucket::DATE as date,
    avg_cpu_percent,
    max_cpu_percent,
    p95_cpu_percent,
    cpu_above_80_minutes
FROM daily_performance_stats
WHERE system_id = 1
  AND day_bucket >= NOW() - INTERVAL '30 days'
ORDER BY day_bucket DESC;

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
-- SELECT AVG(avg_cpu_percent) FROM hourly_performance_stats WHERE hour_bucket > NOW() - INTERVAL '7 days';

-- ============================================================================
-- Cleanup (if needed)
-- ============================================================================

-- Drop continuous aggregates
-- DROP MATERIALIZED VIEW IF EXISTS hourly_performance_stats CASCADE;
-- DROP MATERIALIZED VIEW IF EXISTS daily_performance_stats CASCADE;

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
