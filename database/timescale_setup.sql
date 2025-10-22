-- ============================================================================
-- TimescaleDB Setup & Configuration
-- ============================================================================
-- Purpose: Convert regular tables to hypertables for time-series optimization
-- Requires: TimescaleDB extension installed
-- ============================================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================================================
-- Convert usage_metrics to Hypertable
-- ============================================================================

-- Convert the usage_metrics table to a hypertable
-- This enables automatic partitioning by time for efficient queries
SELECT create_hypertable(
    'usage_metrics',
    'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE,
    migrate_data => TRUE
);

-- Set compression policy for older data
-- Compress chunks older than 7 days to save space
ALTER TABLE usage_metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('usage_metrics', INTERVAL '7 days');

-- Set retention policy (optional)
-- Automatically drop data older than 1 year
SELECT add_retention_policy('usage_metrics', INTERVAL '1 year');

-- ============================================================================
-- Convert alert_logs to Hypertable
-- ============================================================================

SELECT create_hypertable(
    'alert_logs',
    'triggered_at',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE,
    migrate_data => TRUE
);

ALTER TABLE alert_logs SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',
    timescaledb.compress_orderby = 'triggered_at DESC'
);

SELECT add_compression_policy('alert_logs', INTERVAL '30 days');
SELECT add_retention_policy('alert_logs', INTERVAL '2 years');

-- ============================================================================
-- Convert process_snapshots to Hypertable
-- ============================================================================

SELECT create_hypertable(
    'process_snapshots',
    'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE,
    migrate_data => TRUE
);

ALTER TABLE process_snapshots SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('process_snapshots', INTERVAL '14 days');
SELECT add_retention_policy('process_snapshots', INTERVAL '90 days');

-- ============================================================================
-- Continuous Aggregates for Performance
-- ============================================================================

-- Continuous Aggregate: Hourly Performance Summaries
-- Automatically maintains materialized view with hourly stats
CREATE MATERIALIZED VIEW hourly_performance_stats
WITH (timescaledb.continuous) AS
SELECT
    system_id,
    time_bucket('1 hour', timestamp) AS hour_bucket,
    
    -- CPU Statistics
    AVG(cpu_percent) AS avg_cpu_percent,
    MAX(cpu_percent) AS max_cpu_percent,
    MIN(cpu_percent) AS min_cpu_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent) AS p95_cpu_percent,
    
    -- RAM Statistics
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent) AS p95_ram_percent,
    
    -- GPU Statistics
    AVG(gpu_utilization) AS avg_gpu_percent,
    MAX(gpu_utilization) AS max_gpu_percent,
    
    -- Disk Statistics
    AVG(disk_io_wait_percent) AS avg_disk_io_wait,
    SUM(disk_read_mb_s * 60 / 1024.0) AS total_disk_read_gb, -- Convert to GB
    SUM(disk_write_mb_s * 60 / 1024.0) AS total_disk_write_gb,
    
    -- Load Statistics
    AVG(load_avg_1min) AS avg_load_1min,
    
    -- Count
    COUNT(*) AS metric_count
    
FROM usage_metrics
GROUP BY system_id, hour_bucket;

-- Add refresh policy (refresh every hour, covering last 2 hours)
SELECT add_continuous_aggregate_policy('hourly_performance_stats',
    start_offset => INTERVAL '2 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour');

-- ============================================================================

-- Continuous Aggregate: Daily Performance Summaries
CREATE MATERIALIZED VIEW daily_performance_stats
WITH (timescaledb.continuous) AS
SELECT
    system_id,
    time_bucket('1 day', timestamp) AS day_bucket,
    
    -- CPU Statistics
    AVG(cpu_percent) AS avg_cpu_percent,
    MAX(cpu_percent) AS max_cpu_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent) AS p95_cpu_percent,
    SUM(CASE WHEN cpu_percent > 80 THEN 1 ELSE 0 END) * 5 AS cpu_above_80_minutes, -- Assuming 5-min intervals
    
    -- RAM Statistics
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent) AS p95_ram_percent,
    SUM(CASE WHEN swap_percent > 0 THEN 1 ELSE 0 END) * 5 AS swap_used_minutes,
    
    -- GPU Statistics
    AVG(gpu_utilization) AS avg_gpu_percent,
    MAX(gpu_utilization) AS max_gpu_percent,
    SUM(CASE WHEN gpu_utilization < 10 THEN 1 ELSE 0 END) * 5 AS gpu_idle_minutes,
    
    -- Disk Statistics
    AVG(disk_io_wait_percent) AS avg_disk_io_wait,
    SUM(disk_read_mb_s * 300 / 1024.0) AS total_disk_read_gb, -- 5-min intervals
    SUM(disk_write_mb_s * 300 / 1024.0) AS total_disk_write_gb,
    
    -- Utilization Flags
    CASE 
        WHEN AVG(cpu_percent) < 30 AND AVG(ram_percent) < 30 THEN TRUE 
        ELSE FALSE 
    END AS is_underutilized,
    
    CASE 
        WHEN PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent) > 90 
            OR PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent) > 90 
        THEN TRUE 
        ELSE FALSE 
    END AS is_overutilized,
    
    -- Count
    COUNT(*) AS metric_count
    
FROM usage_metrics
GROUP BY system_id, day_bucket;

-- Add refresh policy (refresh daily, covering last 2 days)
SELECT add_continuous_aggregate_policy('daily_performance_stats',
    start_offset => INTERVAL '2 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day');

-- ============================================================================
-- Optimize Continuous Aggregates
-- ============================================================================

-- Enable compression for continuous aggregates
ALTER MATERIALIZED VIEW hourly_performance_stats SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',
    timescaledb.compress_orderby = 'hour_bucket DESC'
);

SELECT add_compression_policy('hourly_performance_stats', INTERVAL '30 days');

ALTER MATERIALIZED VIEW daily_performance_stats SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',
    timescaledb.compress_orderby = 'day_bucket DESC'
);

SELECT add_compression_policy('daily_performance_stats', INTERVAL '90 days');

-- ============================================================================
-- Helpful TimescaleDB Views
-- ============================================================================

-- View to check hypertable status
CREATE VIEW timescaledb_info AS
SELECT 
    h.table_name,
    h.compression_state,
    pg_size_pretty(hypertable_size(format('%I.%I', h.table_schema, h.table_name)::regclass)) AS total_size,
    pg_size_pretty(
        hypertable_size(format('%I.%I', h.table_schema, h.table_name)::regclass) - 
        hypertable_compression_stats(format('%I.%I', h.table_schema, h.table_name)::regclass)
    ) AS compressed_size
FROM timescaledb_information.hypertables h;

-- View to monitor chunk compression status
CREATE VIEW chunk_compression_status AS
SELECT
    h.table_name,
    c.chunk_name,
    c.range_start,
    c.range_end,
    c.is_compressed,
    pg_size_pretty(c.total_bytes) AS chunk_size,
    pg_size_pretty(c.compressed_total_bytes) AS compressed_size
FROM timescaledb_information.chunks c
JOIN timescaledb_information.hypertables h ON c.hypertable_name = h.table_name
ORDER BY h.table_name, c.range_start DESC;

-- ============================================================================
-- Manual Maintenance Commands (for reference)
-- ============================================================================

-- Manually refresh continuous aggregate:
-- SELECT refresh_continuous_aggregate('hourly_performance_stats', NULL, NULL);

-- Manually compress a specific chunk:
-- SELECT compress_chunk(chunk_name) FROM timescaledb_information.chunks WHERE ...;

-- Manually decompress a chunk (if needed for updates):
-- SELECT decompress_chunk(chunk_name);

-- Check compression statistics:
-- SELECT * FROM hypertable_compression_stats('usage_metrics');

-- ============================================================================
-- Performance Tuning Settings (adjust postgresql.conf)
-- ============================================================================

/*
# Recommended PostgreSQL settings for TimescaleDB

# Memory
shared_buffers = 4GB                    # 25% of total RAM
effective_cache_size = 12GB             # 75% of total RAM
work_mem = 32MB
maintenance_work_mem = 512MB

# TimescaleDB specific
timescaledb.max_background_workers = 8
max_worker_processes = 16
max_parallel_workers_per_gather = 4
max_parallel_workers = 8

# Checkpoints
checkpoint_timeout = 15min
max_wal_size = 2GB
min_wal_size = 512MB

# Write-ahead log
wal_buffers = 16MB
wal_compression = on

# Query planner
random_page_cost = 1.1                  # For SSD
effective_io_concurrency = 200          # For SSD
*/

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Check if TimescaleDB is properly installed
SELECT default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'timescaledb';

-- List all hypertables
SELECT * FROM timescaledb_information.hypertables;

-- Check compression policies
SELECT * FROM timescaledb_information.jobs 
WHERE proc_name LIKE '%compress%';

-- Check retention policies
SELECT * FROM timescaledb_information.jobs 
WHERE proc_name LIKE '%retention%';

-- View continuous aggregates
SELECT * FROM timescaledb_information.continuous_aggregates;

-- ============================================================================
-- END OF TIMESCALEDB SETUP
-- ============================================================================
