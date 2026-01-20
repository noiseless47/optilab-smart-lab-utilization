-- ============================================================================
-- TimescaleDB Setup & Configuration
-- ============================================================================
-- Purpose: Convert regular tables to hypertables for time-series optimization
-- Requires: TimescaleDB extension installed
-- ============================================================================

-- Enable TimescaleDB extension
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- ============================================================================
-- Convert metrics to Hypertable
-- ============================================================================

-- First, check if metrics table exists and has data
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics') THEN
        -- Create metrics table if it doesn't exist
        CREATE TABLE metrics (
            timestamp TIMESTAMPTZ NOT NULL,
            system_id TEXT NOT NULL,
            cpu_percent DOUBLE PRECISION,
            ram_percent DOUBLE PRECISION,
            gpu_utilization DOUBLE PRECISION,
            disk_io_wait_percent DOUBLE PRECISION,
            disk_read_mb_s DOUBLE PRECISION,
            disk_write_mb_s DOUBLE PRECISION,
            swap_percent DOUBLE PRECISION,
            load_avg_1min DOUBLE PRECISION,
            hostname TEXT
        );
    END IF;
END $$;

-- Convert the metrics table to a hypertable
-- This enables automatic partitioning by time for efficient queries
SELECT create_hypertable(
    'metrics',
    'timestamp',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
    -- Remove migrate_data parameter for safety
);

-- Set compression policy for older data
-- Compress chunks older than 7 days to save space
ALTER TABLE metrics SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'system_id',
    timescaledb.compress_orderby = 'timestamp DESC'
);

SELECT add_compression_policy('metrics', INTERVAL '7 days', if_not_exists => TRUE);

-- Set retention policy (optional)
-- Automatically drop data older than 1 year
SELECT add_retention_policy('metrics', INTERVAL '1 year', if_not_exists => TRUE);


-- ============================================================================
-- Continuous Aggregates for Performance
-- ============================================================================

-- Drop existing continuous aggregates if they exist
DROP MATERIALIZED VIEW IF EXISTS hourly_performance_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS daily_performance_stats CASCADE;

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
    APPROX_PERCENTILE(0.95, percentile_agg(cpu_percent)) AS p95_cpu_percent,
    
    -- RAM Statistics
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    APPROX_PERCENTILE(0.95, percentile_agg(ram_percent)) AS p95_ram_percent,
    
    -- GPU Statistics
    AVG(gpu_percent) AS avg_gpu_percent,
    MAX(gpu_percent) AS max_gpu_percent,
    
    -- Disk Statistics
    AVG(disk_percent) AS avg_disk_io_wait,
    SUM(COALESCE(disk_read_mbps, 0) * 300 / 1024.0) AS total_disk_read_gb, -- Convert MB/s to GB (5min intervals)
    SUM(COALESCE(disk_write_mbps, 0) * 300 / 1024.0) AS total_disk_write_gb,
    
    -- Uptime Statistics
    AVG(uptime_seconds) AS avg_uptime_seconds,
    
    -- Count
    COUNT(*) AS metric_count
    
FROM metrics
GROUP BY system_id, hour_bucket;

-- Add refresh policy with proper window sizes
SELECT add_continuous_aggregate_policy('hourly_performance_stats',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE);

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
    APPROX_PERCENTILE(0.95, percentile_agg(cpu_percent)) AS p95_cpu_percent,
    SUM(CASE WHEN cpu_percent > 80 THEN 1 ELSE 0 END) * 5 AS cpu_above_80_minutes, -- Assuming 5-min intervals
    
    -- RAM Statistics
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    APPROX_PERCENTILE(0.95, percentile_agg(ram_percent)) AS p95_ram_percent,
    
    -- GPU Statistics
    AVG(gpu_percent) AS avg_gpu_percent,
    MAX(gpu_percent) AS max_gpu_percent,
    SUM(CASE WHEN COALESCE(gpu_percent, 0) < 10 THEN 1 ELSE 0 END) * 5 AS gpu_idle_minutes,
    
    -- Disk Statistics
    AVG(disk_percent) AS avg_disk_io_wait,
    SUM(COALESCE(disk_read_mbps, 0) * 300 / 1024.0) AS total_disk_read_gb, -- 5-min intervals
    SUM(COALESCE(disk_write_mbps, 0) * 300 / 1024.0) AS total_disk_write_gb,
    
    -- Utilization Flags
    CASE 
        WHEN AVG(COALESCE(cpu_percent, 0)) < 30 AND AVG(COALESCE(ram_percent, 0)) < 30 THEN TRUE 
        ELSE FALSE 
    END AS is_underutilized,
    
    CASE 
        WHEN APPROX_PERCENTILE(0.95, percentile_agg(COALESCE(cpu_percent, 0))) > 90 
            OR APPROX_PERCENTILE(0.95, percentile_agg(COALESCE(ram_percent, 0))) > 90 
        THEN TRUE 
        ELSE FALSE 
    END AS is_overutilized,
    
    -- Count
    COUNT(*) AS metric_count
    
FROM metrics
GROUP BY system_id, day_bucket;

-- Add refresh policy with proper window sizes
SELECT add_continuous_aggregate_policy('daily_performance_stats',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

-- ============================================================================
-- Add Indexes for Better Performance
-- ============================================================================

-- Index for common query patterns
CREATE INDEX IF NOT EXISTS idx_metrics_system_timestamp ON metrics (system_id, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON metrics (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_hourly_stats_bucket ON hourly_performance_stats (system_id, hour_bucket DESC);
CREATE INDEX IF NOT EXISTS idx_daily_stats_bucket ON daily_performance_stats (system_id, day_bucket DESC);

-- ============================================================================
-- Insert Sample Data for Testing
-- ============================================================================

-- Insert some sample data to test the setup
INSERT INTO metrics (timestamp, system_id, cpu_percent, ram_percent, gpu_utilization, disk_io_wait_percent, hostname) 
SELECT 
    NOW() - (interval '1 minute' * (seq * 5)),
    'system-' || ((seq % 3) + 1)::text,
    (random() * 100)::double precision,
    (random() * 100)::double precision,
    (random() * 100)::double precision,
    (random() * 10)::double precision,
    'host-' || ((seq % 3) + 1)::text
FROM generate_series(1, 100) AS seq;

-- ============================================================================
-- Verification Queries
-- ============================================================================

-- Check if TimescaleDB is properly installed
SELECT default_version, installed_version
FROM pg_available_extensions
WHERE name = 'timescaledb';

-- List hypertables
SELECT 
    hypertable_schema,
    hypertable_name,
    owner,
    num_chunks,
    compression_enabled,
    is_distributed
FROM timescaledb_information.hypertables
WHERE hypertable_name = 'metrics';

-- Check chunks information
SELECT 
    chunk_schema,
    chunk_name,
    range_start,
    range_end,
    is_compressed,
    chunk_size,
    compressed_chunk_size
FROM timescaledb_information.chunks
WHERE hypertable_name = 'metrics'
ORDER BY range_start DESC
LIMIT 5;

-- Check compression and retention policies
SELECT 
    job_id,
    application_name,
    schedule_interval,
    last_run_started_at,
    total_runs,
    total_successes,
    total_failures
FROM timescaledb_information.job_stats
WHERE hypertable_name = 'metrics';

-- View continuous aggregates
SELECT 
    view_name,
    materialized_only,
    compression_enabled
FROM timescaledb_information.continuous_aggregates
WHERE view_name LIKE '%performance_stats';

-- Test query on continuous aggregates
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_percent,
    max_cpu_percent,
    p95_cpu_percent,
    metric_count
FROM hourly_performance_stats
ORDER BY hour_bucket DESC, system_id
LIMIT 10;

-- ============================================================================
-- Setup Completion Message
-- ============================================================================

DO $$ 
BEGIN
    RAISE NOTICE 'TimescaleDB setup completed successfully!';
    RAISE NOTICE 'Hypertable: metrics';
    RAISE NOTICE 'Continuous Aggregates: hourly_performance_stats, daily_performance_stats';
    RAISE NOTICE 'Compression: Enabled (7+ days old)';
    RAISE NOTICE 'Retention: 1 year';
END $$;

-- ============================================================================
-- END OF TIMESCALEDB SETUP
-- ============================================================================