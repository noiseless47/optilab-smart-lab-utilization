-- ============================================================================
-- Update TimescaleDB Continuous Aggregates
-- ============================================================================
-- This script updates the continuous aggregates to match the actual metrics schema
-- Run this after the initial TimescaleDB setup or when schema changes occur
-- ============================================================================

-- Enable TimescaleDB Toolkit extension for percentile functions
CREATE EXTENSION IF NOT EXISTS timescaledb_toolkit;

-- Drop existing continuous aggregates if they exist
DROP MATERIALIZED VIEW IF EXISTS hourly_performance_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS daily_performance_stats CASCADE;

-- ============================================================================
-- Continuous Aggregate: Hourly Performance Summaries
-- ============================================================================
CREATE MATERIALIZED VIEW hourly_performance_stats
WITH (timescaledb.continuous) AS
SELECT
    system_id,
    time_bucket('1 hour', timestamp) AS hour_bucket,
    
    -- CPU Statistics
    AVG(cpu_percent) AS avg_cpu_percent,
    MAX(cpu_percent) AS max_cpu_percent,
    MIN(cpu_percent) AS min_cpu_percent,
    percentile_agg(cpu_percent) AS p95_cpu_percent_agg, -- Store aggregate for percentile
    
    -- RAM Statistics
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    percentile_agg(ram_percent) AS p95_ram_percent_agg,
    
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

-- Add refresh policy
SELECT add_continuous_aggregate_policy('hourly_performance_stats',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE);

-- ============================================================================
-- Continuous Aggregate: Daily Performance Summaries
-- ============================================================================
CREATE MATERIALIZED VIEW daily_performance_stats
WITH (timescaledb.continuous) AS
SELECT
    system_id,
    time_bucket('1 day', timestamp) AS day_bucket,
    
    -- CPU Statistics
    AVG(cpu_percent) AS avg_cpu_percent,
    MAX(cpu_percent) AS max_cpu_percent,
    percentile_agg(cpu_percent) AS p95_cpu_percent_agg,
    SUM(CASE WHEN cpu_percent > 80 THEN 1 ELSE 0 END) * 5 AS cpu_above_80_minutes, -- Assuming 5-min intervals
    
    -- RAM Statistics
    AVG(ram_percent) AS avg_ram_percent,
    MAX(ram_percent) AS max_ram_percent,
    percentile_agg(ram_percent) AS p95_ram_percent_agg,
    
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
        WHEN AVG(COALESCE(cpu_percent, 0)) > 90 OR AVG(COALESCE(ram_percent, 0)) > 90
        THEN TRUE 
        ELSE FALSE 
    END AS is_overutilized,
    
    -- Count
    COUNT(*) AS metric_count
    
FROM metrics
GROUP BY system_id, day_bucket;

-- Add refresh policy
SELECT add_continuous_aggregate_policy('daily_performance_stats',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 day',
    if_not_exists => TRUE);

-- ============================================================================
-- Verification
-- ============================================================================
SELECT 'Continuous aggregates created successfully!' AS status;

-- View the continuous aggregates
SELECT view_name, materialized_only, compression_enabled
FROM timescaledb_information.continuous_aggregates
WHERE view_name LIKE '%performance_stats';

-- ============================================================================
-- END
-- ============================================================================
