-- ============================================================================
-- CFRS Support Queries - Quick Reference
-- ============================================================================
-- Common queries for retrieving CFRS component inputs from the database
-- All CFRS computation happens OUTSIDE the database
-- ============================================================================

-- ============================================================================
-- DEVIATION COMPONENT QUERIES
-- ============================================================================

-- Get active baseline for a specific system and metric
SELECT 
    system_id,
    metric_name,
    baseline_mean,
    baseline_stddev,
    baseline_median,
    baseline_p95,
    baseline_start,
    baseline_end,
    sample_count
FROM system_baselines
WHERE system_id = 1 
  AND metric_name = 'cpu_percent'
  AND is_active = TRUE;

-- Get all active baselines for all systems
SELECT 
    system_id,
    metric_name,
    baseline_mean,
    baseline_stddev
FROM system_baselines
WHERE is_active = TRUE
ORDER BY system_id, metric_name;

-- Get current value for deviation computation
SELECT 
    system_id,
    timestamp,
    cpu_percent,
    ram_percent,
    gpu_percent,
    disk_percent
FROM metrics
WHERE system_id = 1
ORDER BY timestamp DESC
LIMIT 1;

-- Compute z-score externally:
-- z_score = (current_value - baseline_mean) / baseline_stddev
-- deviation_component = abs(z_score)

-- ============================================================================
-- VARIANCE COMPONENT QUERIES
-- ============================================================================

-- Get last 24 hours variance (hourly granularity)
SELECT 
    system_id,
    hour_bucket,
    stddev_cpu_percent,
    stddev_ram_percent,
    stddev_gpu_percent,
    stddev_disk_percent,
    metric_count
FROM hourly_performance_stats
WHERE system_id = 1 
  AND hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY hour_bucket DESC;

-- Get last 7 days variance (daily granularity)
SELECT 
    system_id,
    day_bucket::DATE as date,
    stddev_cpu_percent,
    stddev_ram_percent,
    stddev_gpu_percent,
    stddev_disk_percent
FROM daily_performance_stats
WHERE system_id = 1 
  AND day_bucket >= NOW() - INTERVAL '7 days'
ORDER BY day_bucket DESC;

-- Get variance for all systems (recent hour)
SELECT 
    system_id,
    hour_bucket,
    stddev_cpu_percent,
    stddev_ram_percent,
    metric_count
FROM hourly_performance_stats
WHERE hour_bucket = (
    SELECT MAX(hour_bucket) 
    FROM hourly_performance_stats
)
ORDER BY system_id;

-- Average variance over rolling window
SELECT 
    system_id,
    AVG(stddev_cpu_percent) as avg_cpu_variance,
    AVG(stddev_ram_percent) as avg_ram_variance,
    AVG(stddev_gpu_percent) as avg_gpu_variance,
    COUNT(*) as sample_hours
FROM hourly_performance_stats
WHERE system_id = 1 
  AND hour_bucket >= NOW() - INTERVAL '24 hours'
GROUP BY system_id;

-- Compute variance component externally:
-- variance_component = mean(stddev_values)
-- Higher variance = more unstable system

-- ============================================================================
-- TREND COMPONENT QUERIES
-- ============================================================================

-- Get daily trends for last 30 days (for linear regression)
SELECT 
    system_id,
    date,
    avg_cpu_percent,
    avg_ram_percent,
    avg_gpu_percent,
    avg_disk_percent,
    stddev_cpu_percent,
    metric_count
FROM v_daily_resource_trends
WHERE system_id = 1 
  AND date >= NOW() - INTERVAL '30 days'
ORDER BY date;

-- Get weekly trends for last 90 days
SELECT 
    system_id,
    week_bucket,
    avg_cpu_weekly,
    avg_ram_weekly,
    avg_gpu_weekly,
    stddev_cpu_weekly
FROM v_weekly_resource_trends
WHERE system_id = 1 
  AND week_bucket >= NOW() - INTERVAL '90 days'
ORDER BY week_bucket;

-- Get trends for all systems (last 30 days, for batch processing)
SELECT 
    system_id,
    date,
    avg_cpu_percent,
    avg_ram_percent,
    metric_count
FROM v_daily_resource_trends
WHERE date >= NOW() - INTERVAL '30 days'
ORDER BY system_id, date;

-- Simple linear trend using PostgreSQL REGR_SLOPE (approximation only)
-- For proper slope computation, use external tools (Python scipy, R, etc.)
SELECT 
    system_id,
    REGR_SLOPE(avg_cpu_percent, EXTRACT(EPOCH FROM date)) as cpu_slope,
    REGR_SLOPE(avg_ram_percent, EXTRACT(EPOCH FROM date)) as ram_slope,
    COUNT(*) as data_points
FROM v_daily_resource_trends
WHERE date >= NOW() - INTERVAL '30 days'
GROUP BY system_id
HAVING COUNT(*) >= 7;  -- At least 7 days of data

-- Compute trend component externally:
-- Use linear regression: slope = correlation * (stddev_y / stddev_x)
-- Positive slope = degradation trend
-- trend_component = max(0, slope)

-- ============================================================================
-- COMBINED CFRS INPUT QUERY
-- ============================================================================

-- Get all three CFRS component inputs in one query
WITH latest_variance AS (
    -- Variance component: recent STDDEV
    SELECT 
        system_id,
        AVG(stddev_cpu_percent) as avg_cpu_variance,
        AVG(stddev_ram_percent) as avg_ram_variance,
        AVG(stddev_gpu_percent) as avg_gpu_variance
    FROM hourly_performance_stats
    WHERE hour_bucket >= NOW() - INTERVAL '24 hours'
    GROUP BY system_id
),
baselines AS (
    -- Deviation component: baselines for z-score
    SELECT 
        system_id,
        MAX(CASE WHEN metric_name = 'cpu_percent' THEN baseline_mean END) as cpu_baseline_mean,
        MAX(CASE WHEN metric_name = 'cpu_percent' THEN baseline_stddev END) as cpu_baseline_stddev,
        MAX(CASE WHEN metric_name = 'ram_percent' THEN baseline_mean END) as ram_baseline_mean,
        MAX(CASE WHEN metric_name = 'ram_percent' THEN baseline_stddev END) as ram_baseline_stddev
    FROM system_baselines
    WHERE is_active = TRUE
    GROUP BY system_id
),
current_values AS (
    -- Current values for deviation computation
    SELECT DISTINCT ON (system_id)
        system_id,
        cpu_percent as current_cpu,
        ram_percent as current_ram,
        timestamp as last_metric_time
    FROM metrics
    ORDER BY system_id, timestamp DESC
),
trends AS (
    -- Trend component: regression slopes
    SELECT 
        system_id,
        REGR_SLOPE(avg_cpu_percent, EXTRACT(EPOCH FROM date)) as cpu_slope,
        REGR_SLOPE(avg_ram_percent, EXTRACT(EPOCH FROM date)) as ram_slope,
        COUNT(*) as trend_data_points
    FROM v_daily_resource_trends
    WHERE date >= NOW() - INTERVAL '30 days'
    GROUP BY system_id
    HAVING COUNT(*) >= 7
)
SELECT 
    s.system_id,
    s.hostname,
    
    -- Deviation inputs
    cv.current_cpu,
    b.cpu_baseline_mean,
    b.cpu_baseline_stddev,
    cv.current_ram,
    b.ram_baseline_mean,
    b.ram_baseline_stddev,
    
    -- Variance inputs
    lv.avg_cpu_variance,
    lv.avg_ram_variance,
    lv.avg_gpu_variance,
    
    -- Trend inputs
    t.cpu_slope,
    t.ram_slope,
    t.trend_data_points,
    
    -- Metadata
    cv.last_metric_time,
    s.status
FROM systems s
LEFT JOIN current_values cv USING(system_id)
LEFT JOIN baselines b USING(system_id)
LEFT JOIN latest_variance lv USING(system_id)
LEFT JOIN trends t USING(system_id)
WHERE s.status = 'active'
ORDER BY s.system_id;

-- Use this query output to compute CFRS externally:
-- deviation = abs((current - baseline_mean) / baseline_stddev)
-- variance = avg_variance
-- trend = max(0, slope)
-- CFRS = w1*deviation + w2*variance + w3*trend

-- ============================================================================
-- BASELINE MANAGEMENT QUERIES
-- ============================================================================

-- Store a new baseline (computed externally)
INSERT INTO system_baselines (
    system_id, 
    metric_name, 
    baseline_mean, 
    baseline_stddev, 
    baseline_median,
    baseline_p95,
    baseline_start, 
    baseline_end, 
    sample_count
) VALUES (
    1,                          -- system_id
    'cpu_percent',              -- metric_name
    42.5,                       -- baseline_mean (computed externally)
    12.3,                       -- baseline_stddev (computed externally)
    40.1,                       -- baseline_median
    65.8,                       -- baseline_p95
    '2026-01-01'::TIMESTAMPTZ,  -- baseline_start
    '2026-01-14'::TIMESTAMPTZ,  -- baseline_end
    2016                        -- sample_count
);

-- Update baseline to inactive (when recomputing)
UPDATE system_baselines
SET is_active = FALSE
WHERE system_id = 1 
  AND metric_name = 'cpu_percent'
  AND is_active = TRUE;

-- Get baseline history for a system
SELECT 
    baseline_id,
    metric_name,
    baseline_mean,
    baseline_stddev,
    baseline_start,
    baseline_end,
    computed_at,
    is_active
FROM system_baselines
WHERE system_id = 1
ORDER BY computed_at DESC;

-- ============================================================================
-- BATCH EXPORT FOR EXTERNAL CFRS COMPUTATION
-- ============================================================================

-- Export all inputs as CSV for batch processing
\copy (SELECT system_id, date, avg_cpu_percent, avg_ram_percent, stddev_cpu_percent, stddev_ram_percent FROM v_daily_resource_trends WHERE date >= NOW() - INTERVAL '30 days' ORDER BY system_id, date) TO '/tmp/cfrs_trends.csv' WITH CSV HEADER;

\copy (SELECT system_id, metric_name, baseline_mean, baseline_stddev FROM system_baselines WHERE is_active = TRUE ORDER BY system_id, metric_name) TO '/tmp/cfrs_baselines.csv' WITH CSV HEADER;

\copy (SELECT system_id, hour_bucket, stddev_cpu_percent, stddev_ram_percent FROM hourly_performance_stats WHERE hour_bucket >= NOW() - INTERVAL '24 hours' ORDER BY system_id, hour_bucket) TO '/tmp/cfrs_variance.csv' WITH CSV HEADER;

-- ============================================================================
-- MONITORING & DEBUGGING
-- ============================================================================

-- Check if STDDEV columns are populated
SELECT 
    COUNT(*) as total_rows,
    COUNT(stddev_cpu_percent) as cpu_stddev_count,
    COUNT(stddev_ram_percent) as ram_stddev_count,
    MIN(hour_bucket) as earliest_data,
    MAX(hour_bucket) as latest_data
FROM hourly_performance_stats;

-- Check baseline coverage
SELECT 
    COUNT(DISTINCT system_id) as systems_with_baselines,
    COUNT(*) as total_baselines,
    COUNT(*) FILTER (WHERE is_active = TRUE) as active_baselines
FROM system_baselines;

-- Check trend view data availability
SELECT 
    COUNT(DISTINCT system_id) as systems_in_trends,
    MIN(date) as earliest_trend_date,
    MAX(date) as latest_trend_date,
    COUNT(*) as total_trend_records
FROM v_daily_resource_trends;

-- Find systems without baselines
SELECT s.system_id, s.hostname
FROM systems s
LEFT JOIN system_baselines sb ON s.system_id = sb.system_id AND sb.is_active = TRUE
WHERE sb.baseline_id IS NULL
  AND s.status = 'active';

-- ============================================================================
-- END OF CFRS QUERIES
-- ============================================================================
