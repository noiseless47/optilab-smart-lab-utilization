-- Debug why Analytics page shows 0%
-- Run these queries to check if data exists

-- 1. Check if raw metrics exist (last 24 hours)
SELECT 
    system_id,
    COUNT(*) as metric_count,
    MIN(timestamp) as earliest,
    MAX(timestamp) as latest,
    ROUND(AVG(cpu_percent)::NUMERIC, 2) as avg_cpu,
    ROUND(AVG(ram_percent)::NUMERIC, 2) as avg_ram
FROM metrics
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY system_id
ORDER BY system_id;

-- 2. Check if hourly_performance_stats has data
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_percent,
    avg_ram_percent,
    avg_disk_percent,
    metric_count,
    AGE(NOW(), hour_bucket) as age
FROM hourly_performance_stats
WHERE hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY hour_bucket DESC
LIMIT 20;

-- 3. Test the exact query the backend uses
SELECT
    hour_bucket as timestamp,
    avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, stddev_cpu_percent,
    avg_ram_percent, max_ram_percent, p95_ram_percent, stddev_ram_percent,
    avg_gpu_percent, max_gpu_percent, stddev_gpu_percent,
    avg_disk_percent, max_disk_percent, stddev_disk_percent,
    metric_count
FROM hourly_performance_stats
WHERE system_id = 1
AND hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY hour_bucket DESC;

-- 4. Check if continuous aggregates need manual refresh
SELECT 
    view_name,
    materialization_hypertable_schema,
    materialization_hypertable_name,
    view_definition
FROM timescaledb_information.continuous_aggregates
WHERE view_name IN ('hourly_performance_stats', 'daily_performance_stats');

-- 5. If aggregates are empty, manually refresh them
CALL refresh_continuous_aggregate('hourly_performance_stats', NOW() - INTERVAL '48 hours', NOW());
CALL refresh_continuous_aggregate('daily_performance_stats', NOW() - INTERVAL '7 days', NOW());

-- 6. Re-check after refresh
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_percent,
    avg_ram_percent,
    metric_count
FROM hourly_performance_stats
WHERE hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY hour_bucket DESC
LIMIT 10;
