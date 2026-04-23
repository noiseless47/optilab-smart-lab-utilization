-- ============================================================================
-- TEMPORARY BASELINE COMPUTATION (FOR TESTING WITH <30 DAYS DATA)
-- ============================================================================
-- WARNING: This creates baselines with whatever data you have (even if < 30 days)
-- Only use this for testing CFRS functionality while collecting data
-- For production, wait 30 days and use the proper baseline computation
-- ============================================================================

-- Check how much data you have
SELECT 
    system_id,
    COUNT(*) as hours_available,
    MIN(hour_bucket) as earliest,
    MAX(hour_bucket) as latest,
    AGE(MAX(hour_bucket), MIN(hour_bucket)) as time_span
FROM cfrs_hourly_stats
GROUP BY system_id;

-- Insert test baselines for CFRS testing (uses all available data)
-- This will work with as little as 1 day of data, but is NOT production-ready
INSERT INTO cfrs_system_baselines (
    system_id, metric_name,
    baseline_mean, baseline_stddev, baseline_median, baseline_mad,
    baseline_window_days, baseline_start, baseline_end, sample_count,
    is_active, notes
)
-- CPU I/O Wait
SELECT
    system_id,
    'cpu_iowait' AS metric_name,
    AVG(avg_cpu_iowait) AS baseline_mean,
    STDDEV(avg_cpu_iowait) AS baseline_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_cpu_iowait) AS baseline_median,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(avg_cpu_iowait - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_cpu_iowait) OVER ())) AS baseline_mad,
    EXTRACT(DAY FROM AGE(MAX(hour_bucket), MIN(hour_bucket)))::INT AS baseline_window_days,
    MIN(hour_bucket) AS baseline_start,
    MAX(hour_bucket) AS baseline_end,
    COUNT(*) AS sample_count,
    TRUE AS is_active,
    'TEST BASELINE - NOT PRODUCTION READY' AS notes
FROM cfrs_hourly_stats
WHERE cnt_cpu_iowait >= 5  -- At least 5 samples
GROUP BY system_id
HAVING COUNT(*) >= 10  -- At least 10 hours of data

UNION ALL

-- Context Switch Rate
SELECT
    system_id,
    'context_switch' AS metric_name,
    AVG(avg_context_switch),
    STDDEV(avg_context_switch),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_context_switch),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(avg_context_switch - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_context_switch) OVER ())),
    EXTRACT(DAY FROM AGE(MAX(hour_bucket), MIN(hour_bucket)))::INT,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE,
    'TEST BASELINE - NOT PRODUCTION READY'
FROM cfrs_hourly_stats
WHERE cnt_context_switch >= 5
GROUP BY system_id
HAVING COUNT(*) >= 10

UNION ALL

-- Swap Out Rate
SELECT
    system_id,
    'swap_out' AS metric_name,
    AVG(avg_swap_out),
    STDDEV(avg_swap_out),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_swap_out),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(avg_swap_out - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_swap_out) OVER ())),
    EXTRACT(DAY FROM AGE(MAX(hour_bucket), MIN(hour_bucket)))::INT,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE,
    'TEST BASELINE - NOT PRODUCTION READY'
FROM cfrs_hourly_stats
WHERE cnt_swap_out >= 5
GROUP BY system_id
HAVING COUNT(*) >= 10

UNION ALL

-- Major Page Faults
SELECT
    system_id,
    'major_page_faults' AS metric_name,
    AVG(avg_major_page_faults),
    STDDEV(avg_major_page_faults),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_major_page_faults),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(avg_major_page_faults - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_major_page_faults) OVER ())),
    EXTRACT(DAY FROM AGE(MAX(hour_bucket), MIN(hour_bucket)))::INT,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE,
    'TEST BASELINE - NOT PRODUCTION READY'
FROM cfrs_hourly_stats
WHERE cnt_major_page_faults >= 5
GROUP BY system_id
HAVING COUNT(*) >= 10

UNION ALL

-- CPU Temperature
SELECT
    system_id,
    'cpu_temp' AS metric_name,
    AVG(avg_cpu_temp),
    STDDEV(avg_cpu_temp),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_cpu_temp),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(avg_cpu_temp - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_cpu_temp) OVER ())),
    EXTRACT(DAY FROM AGE(MAX(hour_bucket), MIN(hour_bucket)))::INT,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE,
    'TEST BASELINE - NOT PRODUCTION READY'
FROM cfrs_hourly_stats
WHERE cnt_cpu_temp >= 5
GROUP BY system_id
HAVING COUNT(*) >= 10

UNION ALL

-- GPU Temperature
SELECT
    system_id,
    'gpu_temp' AS metric_name,
    AVG(avg_gpu_temp),
    STDDEV(avg_gpu_temp),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_gpu_temp),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY ABS(avg_gpu_temp - PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_gpu_temp) OVER ())),
    EXTRACT(DAY FROM AGE(MAX(hour_bucket), MIN(hour_bucket)))::INT,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE,
    'TEST BASELINE - NOT PRODUCTION READY'
FROM cfrs_hourly_stats
WHERE cnt_gpu_temp >= 5
GROUP BY system_id
HAVING COUNT(*) >= 10

ON CONFLICT (system_id, metric_name, baseline_start, baseline_end)
DO UPDATE SET
    baseline_mean = EXCLUDED.baseline_mean,
    baseline_stddev = EXCLUDED.baseline_stddev,
    baseline_median = EXCLUDED.baseline_median,
    baseline_mad = EXCLUDED.baseline_mad,
    sample_count = EXCLUDED.sample_count,
    computed_at = NOW(),
    is_active = TRUE,
    notes = EXCLUDED.notes;

-- Verify baselines were created
SELECT 
    system_id,
    metric_name,
    ROUND(baseline_mean::NUMERIC, 2) as mean,
    ROUND(baseline_stddev::NUMERIC, 2) as stddev,
    baseline_window_days as days,
    sample_count,
    notes
FROM cfrs_system_baselines
WHERE is_active = TRUE
ORDER BY system_id, metric_name;

-- Summary
SELECT 
    system_id,
    COUNT(*) as baselines_created,
    MIN(baseline_window_days) as min_days,
    MAX(baseline_window_days) as max_days,
    CASE 
        WHEN COUNT(*) >= 6 THEN '✅ All Tier-1 metrics'
        WHEN COUNT(*) >= 1 THEN '⚠️ Partial (' || COUNT(*) || '/6)'
        ELSE '🔴 No baselines'
    END as status
FROM cfrs_system_baselines
WHERE is_active = TRUE
GROUP BY system_id
ORDER BY system_id;
