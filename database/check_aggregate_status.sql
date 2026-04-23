-- ============================================================================
-- CHECK AGGREGATE DATA STATUS AND REFRESH
-- ============================================================================
-- Run these queries in pgAdmin to diagnose why aggregates are stuck on Jan 20
-- ============================================================================

-- 1. Check if RAW metrics are being collected TODAY (Jan 29, 2026)
SELECT 
    COUNT(*) as metrics_today,
    MIN(timestamp) as first_metric,
    MAX(timestamp) as last_metric,
    AGE(MAX(timestamp), MIN(timestamp)) as time_span
FROM metrics
WHERE timestamp >= CURRENT_DATE  -- Today (Jan 29)
AND timestamp < CURRENT_DATE + INTERVAL '1 day';

-- 2. Check latest raw metrics (should show Jan 29 data)
SELECT 
    system_id,
    timestamp,
    cpu_percent,
    ram_percent
FROM metrics
ORDER BY timestamp DESC
LIMIT 10;

-- 3. Check HOURLY aggregate status (this is what you see in the UI)
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_percent,
    metric_count,
    AGE(NOW(), hour_bucket) as age
FROM hourly_performance_stats
ORDER BY hour_bucket DESC
LIMIT 20;

-- 4. Check CFRS hourly aggregate status
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_iowait,
    cnt_cpu_iowait,
    AGE(NOW(), hour_bucket) as age
FROM cfrs_hourly_stats
ORDER BY hour_bucket DESC
LIMIT 20;

-- 5. Check if continuous aggregate policies exist
SELECT 
    application_name as aggregate_name,
    schedule_interval,
    config::json->>'start_offset' as start_offset,
    config::json->>'end_offset' as end_offset,
    next_start
FROM timescaledb_information.jobs
WHERE application_name LIKE '%policy%'
ORDER BY application_name;

-- ============================================================================
-- MANUAL REFRESH (IF NEEDED)
-- ============================================================================
-- If aggregates are stuck, manually refresh them:

-- Refresh hourly_performance_stats for the last 48 hours
CALL refresh_continuous_aggregate(
    'hourly_performance_stats',
    NOW() - INTERVAL '48 hours',
    NOW()
);

-- Refresh daily_performance_stats for the last 7 days
CALL refresh_continuous_aggregate(
    'daily_performance_stats',
    NOW() - INTERVAL '7 days',
    NOW()
);

-- Refresh CFRS aggregates for the last 48 hours
CALL refresh_continuous_aggregate(
    'cfrs_hourly_stats',
    NOW() - INTERVAL '48 hours',
    NOW()
);

-- Refresh CFRS daily aggregates for the last 7 days
CALL refresh_continuous_aggregate(
    'cfrs_daily_stats',
    NOW() - INTERVAL '7 days',
    NOW()
);

-- ============================================================================
-- VERIFY REFRESH WORKED
-- ============================================================================

-- Check if hourly aggregates now show Jan 29 data
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_percent,
    metric_count
FROM hourly_performance_stats
WHERE hour_bucket >= '2026-01-29 00:00:00'
ORDER BY hour_bucket DESC;

-- Check if CFRS hourly aggregates show Jan 29 data
SELECT 
    system_id,
    hour_bucket,
    avg_cpu_iowait,
    cnt_cpu_iowait
FROM cfrs_hourly_stats
WHERE hour_bucket >= '2026-01-29 00:00:00'
ORDER BY hour_bucket DESC;

-- ============================================================================
-- SET UP AUTO-REFRESH POLICIES (IF NOT ALREADY CONFIGURED)
-- ============================================================================
-- These policies make aggregates refresh automatically in the background

-- Add refresh policy for hourly_performance_stats (refresh every 1 hour)
SELECT add_continuous_aggregate_policy(
    'hourly_performance_stats',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);

-- Add refresh policy for daily_performance_stats (refresh every 1 hour)
SELECT add_continuous_aggregate_policy(
    'daily_performance_stats',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 hour'
);

-- Add refresh policy for cfrs_hourly_stats (refresh every 1 hour)
SELECT add_continuous_aggregate_policy(
    'cfrs_hourly_stats',
    start_offset => INTERVAL '3 days',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour'
);

-- Add refresh policy for cfrs_daily_stats (refresh every 1 hour)
SELECT add_continuous_aggregate_policy(
    'cfrs_daily_stats',
    start_offset => INTERVAL '7 days',
    end_offset => INTERVAL '1 day',
    schedule_interval => INTERVAL '1 hour'
);

-- ============================================================================
-- DIAGNOSTIC: Check data gap between Jan 20 and Jan 29
-- ============================================================================

-- Count metrics per day to see the gap
SELECT 
    DATE(timestamp) as day,
    COUNT(*) as metric_count,
    MIN(timestamp) as first_metric,
    MAX(timestamp) as last_metric
FROM metrics
WHERE timestamp >= '2026-01-20'
AND timestamp < '2026-01-30'
GROUP BY DATE(timestamp)
ORDER BY day;

-- Show hourly breakdown for Jan 29
SELECT 
    DATE_TRUNC('hour', timestamp) as hour,
    COUNT(*) as metrics,
    AVG(cpu_percent) as avg_cpu
FROM metrics
WHERE timestamp >= '2026-01-29 00:00:00'
AND timestamp < '2026-01-30 00:00:00'
GROUP BY DATE_TRUNC('hour', timestamp)
ORDER BY hour;
