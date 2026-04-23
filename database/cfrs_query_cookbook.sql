-- ============================================================================
-- CFRS QUERY COOKBOOK
-- Ready-to-use SQL queries for CFRS component computation
-- ============================================================================

-- ============================================================================
-- DEVIATION COMPONENT QUERIES
-- Purpose: Compute z-scores and deviation measures
-- ============================================================================

-- Query D1: Retrieve Current Hour Stats with Baseline for Z-Score Computation
-- Use Case: Real-time deviation detection for CFRS
SELECT
    h.system_id,
    s.hostname,
    h.hour_bucket,
    
    -- CPU I/O Wait Deviation
    h.avg_cpu_iowait AS current_cpu_iowait,
    b_iowait.baseline_mean AS baseline_cpu_iowait_mean,
    b_iowait.baseline_stddev AS baseline_cpu_iowait_stddev,
    -- External CFRS computes: z = (current - mean) / stddev
    
    -- Context Switch Deviation
    h.avg_context_switch AS current_context_switch,
    b_ctx.baseline_mean AS baseline_context_switch_mean,
    b_ctx.baseline_stddev AS baseline_context_switch_stddev,
    
    -- Swap Out Deviation
    h.avg_swap_out AS current_swap_out,
    b_swap.baseline_mean AS baseline_swap_out_mean,
    b_swap.baseline_stddev AS baseline_swap_out_stddev,
    
    -- Sample Quality
    h.cnt_cpu_iowait,
    h.total_samples

FROM cfrs_hourly_stats h
JOIN systems s ON h.system_id = s.system_id
LEFT JOIN cfrs_system_baselines b_iowait
    ON h.system_id = b_iowait.system_id
   AND b_iowait.metric_name = 'cpu_iowait'
   AND b_iowait.is_active = TRUE
LEFT JOIN cfrs_system_baselines b_ctx
    ON h.system_id = b_ctx.system_id
   AND b_ctx.metric_name = 'context_switch'
   AND b_ctx.is_active = TRUE
LEFT JOIN cfrs_system_baselines b_swap
    ON h.system_id = b_swap.system_id
   AND b_swap.metric_name = 'swap_out'
   AND b_swap.is_active = TRUE

WHERE h.hour_bucket >= NOW() - INTERVAL '1 hour'
  AND s.status = 'active'
ORDER BY h.system_id, h.hour_bucket DESC;


-- Query D2: Identify Systems with Largest Deviation (Anomaly Detection)
-- Use Case: Find systems behaving most abnormally
WITH deviation_scores AS (
    SELECT
        h.system_id,
        h.hour_bucket,
        
        -- Compute absolute z-scores (do in application for production)
        ABS((h.avg_cpu_iowait - b.baseline_mean) / NULLIF(b.baseline_stddev, 0)) AS cpu_iowait_z,
        ABS((h.avg_context_switch - b_ctx.baseline_mean) / NULLIF(b_ctx.baseline_stddev, 0)) AS context_switch_z,
        ABS((h.avg_swap_out - b_swap.baseline_mean) / NULLIF(b_swap.baseline_stddev, 0)) AS swap_out_z,
        
        h.cnt_cpu_iowait

    FROM cfrs_hourly_stats h
    LEFT JOIN cfrs_system_baselines b
        ON h.system_id = b.system_id AND b.metric_name = 'cpu_iowait' AND b.is_active = TRUE
    LEFT JOIN cfrs_system_baselines b_ctx
        ON h.system_id = b_ctx.system_id AND b_ctx.metric_name = 'context_switch' AND b_ctx.is_active = TRUE
    LEFT JOIN cfrs_system_baselines b_swap
        ON h.system_id = b_swap.system_id AND b_swap.metric_name = 'swap_out' AND b_swap.is_active = TRUE
    
    WHERE h.hour_bucket >= NOW() - INTERVAL '24 hours'
      AND h.cnt_cpu_iowait >= 10  -- Sufficient samples
)
SELECT
    s.hostname,
    d.hour_bucket,
    ROUND(d.cpu_iowait_z, 2) AS cpu_iowait_z_score,
    ROUND(d.context_switch_z, 2) AS context_switch_z_score,
    ROUND(d.swap_out_z, 2) AS swap_out_z_score,
    GREATEST(d.cpu_iowait_z, d.context_switch_z, d.swap_out_z) AS max_z_score
FROM deviation_scores d
JOIN systems s ON d.system_id = s.system_id
WHERE GREATEST(d.cpu_iowait_z, d.context_switch_z, d.swap_out_z) > 3  -- Z > 3 = significant anomaly
ORDER BY max_z_score DESC
LIMIT 20;


-- Query D3: P95-Based Deviation (Alternative to Z-Score)
-- Use Case: Deviation measured as distance from 95th percentile
SELECT
    h.system_id,
    s.hostname,
    h.hour_bucket,
    h.avg_cpu_iowait AS current_value,
    h.p95_cpu_iowait AS p95_threshold,
    
    -- Deviation from P95
    CASE
        WHEN h.avg_cpu_iowait > h.p95_cpu_iowait THEN
            h.avg_cpu_iowait - h.p95_cpu_iowait
        ELSE 0
    END AS p95_deviation,
    
    -- Percentage above P95
    CASE
        WHEN h.p95_cpu_iowait > 0 THEN
            100.0 * (h.avg_cpu_iowait - h.p95_cpu_iowait) / h.p95_cpu_iowait
        ELSE NULL
    END AS pct_above_p95

FROM cfrs_hourly_stats h
JOIN systems s ON h.system_id = s.system_id
WHERE h.hour_bucket >= NOW() - INTERVAL '24 hours'
  AND h.avg_cpu_iowait > h.p95_cpu_iowait  -- Only show exceedances
ORDER BY p95_deviation DESC
LIMIT 50;


-- ============================================================================
-- VARIANCE COMPONENT QUERIES
-- Purpose: Measure volatility and instability
-- ============================================================================

-- Query V1: Coefficient of Variation (Volatility Indicator)
-- Use Case: Identify systems with erratic behavior
SELECT
    system_id,
    hour_bucket,
    
    -- CV = stddev / mean (normalized volatility)
    ROUND((stddev_cpu_iowait / NULLIF(avg_cpu_iowait, 0))::NUMERIC, 3) AS cv_cpu_iowait,
    ROUND((stddev_context_switch / NULLIF(avg_context_switch, 0))::NUMERIC, 3) AS cv_context_switch,
    ROUND((stddev_swap_out / NULLIF(avg_swap_out, 0))::NUMERIC, 3) AS cv_swap_out,
    ROUND((stddev_major_page_faults / NULLIF(avg_major_page_faults, 0))::NUMERIC, 3) AS cv_page_faults,
    
    -- Aggregate volatility score (count of high-CV metrics)
    (
        (CASE WHEN (stddev_cpu_iowait / NULLIF(avg_cpu_iowait, 0)) > 0.5 THEN 1 ELSE 0 END) +
        (CASE WHEN (stddev_context_switch / NULLIF(avg_context_switch, 0)) > 0.5 THEN 1 ELSE 0 END) +
        (CASE WHEN (stddev_swap_out / NULLIF(avg_swap_out, 0)) > 0.5 THEN 1 ELSE 0 END) +
        (CASE WHEN (stddev_major_page_faults / NULLIF(avg_major_page_faults, 0)) > 0.5 THEN 1 ELSE 0 END)
    ) AS high_volatility_count,
    
    -- Sample quality
    cnt_cpu_iowait,
    total_samples

FROM cfrs_hourly_stats
WHERE hour_bucket >= NOW() - INTERVAL '24 hours'
  AND cnt_cpu_iowait >= 10  -- Sufficient samples for reliable STDDEV
ORDER BY high_volatility_count DESC, hour_bucket DESC
LIMIT 50;


-- Query V2: Daily Variance Trend (Increasing Instability)
-- Use Case: Detect systems becoming increasingly unstable over time
SELECT
    system_id,
    day_bucket,
    
    -- Daily standard deviations for Tier-1 metrics
    ROUND(stddev_cpu_iowait::NUMERIC, 2) AS daily_stddev_cpu_iowait,
    ROUND(stddev_context_switch::NUMERIC, 0) AS daily_stddev_context_switch,
    ROUND(stddev_swap_out::NUMERIC, 2) AS daily_stddev_swap_out,
    ROUND(stddev_major_page_faults::NUMERIC, 2) AS daily_stddev_page_faults,
    
    -- 7-day rolling average of STDDEV (smoothed volatility trend)
    ROUND(AVG(stddev_cpu_iowait) OVER (
        PARTITION BY system_id
        ORDER BY day_bucket
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    )::NUMERIC, 2) AS rolling_7d_stddev_cpu_iowait,
    
    cnt_cpu_iowait,
    total_samples

FROM cfrs_daily_stats
WHERE day_bucket >= NOW() - INTERVAL '30 days'
  AND cnt_cpu_iowait >= 50  -- Sufficient daily samples
ORDER BY system_id, day_bucket DESC;


-- Query V3: Variance Spike Detection
-- Use Case: Find sudden increases in volatility
WITH variance_baseline AS (
    SELECT
        system_id,
        AVG(stddev_cpu_iowait) AS baseline_stddev,
        STDDEV(stddev_cpu_iowait) AS stddev_of_stddev
    FROM cfrs_daily_stats
    WHERE day_bucket >= NOW() - INTERVAL '30 days'
      AND day_bucket < NOW() - INTERVAL '7 days'  -- Baseline excludes last week
      AND cnt_cpu_iowait >= 50
    GROUP BY system_id
)
SELECT
    d.system_id,
    s.hostname,
    d.day_bucket,
    d.stddev_cpu_iowait AS current_variance,
    v.baseline_stddev AS baseline_variance,
    
    -- Variance spike magnitude
    ROUND((d.stddev_cpu_iowait - v.baseline_stddev) / NULLIF(v.stddev_of_stddev, 0), 2) AS variance_z_score

FROM cfrs_daily_stats d
JOIN variance_baseline v ON d.system_id = v.system_id
JOIN systems s ON d.system_id = s.system_id
WHERE d.day_bucket >= NOW() - INTERVAL '7 days'
  AND d.stddev_cpu_iowait > v.baseline_stddev + (2 * v.stddev_of_stddev)  -- 2-sigma spike
ORDER BY variance_z_score DESC;


-- ============================================================================
-- TREND COMPONENT QUERIES
-- Purpose: Detect degradation patterns via linear regression
-- ============================================================================

-- Query T1: 30-Day Linear Regression Slope (Degradation Trend)
-- Use Case: Identify systems with worsening metrics over time
SELECT
    system_id,
    
    -- CPU I/O Wait trend
    ROUND(REGR_SLOPE(avg_cpu_iowait, day_epoch)::NUMERIC, 6) AS cpu_iowait_slope,
    ROUND(REGR_R2(avg_cpu_iowait, day_epoch)::NUMERIC, 3) AS cpu_iowait_r2,
    
    -- Context Switch trend
    ROUND(REGR_SLOPE(avg_context_switch, day_epoch)::NUMERIC, 6) AS context_switch_slope,
    ROUND(REGR_R2(avg_context_switch, day_epoch)::NUMERIC, 3) AS context_switch_r2,
    
    -- Swap Out trend
    ROUND(REGR_SLOPE(avg_swap_out, day_epoch)::NUMERIC, 6) AS swap_out_slope,
    ROUND(REGR_R2(avg_swap_out, day_epoch)::NUMERIC, 3) AS swap_out_r2,
    
    -- Major Page Faults trend
    ROUND(REGR_SLOPE(avg_major_page_faults, day_epoch)::NUMERIC, 6) AS page_faults_slope,
    ROUND(REGR_R2(avg_major_page_faults, day_epoch)::NUMERIC, 3) AS page_faults_r2,
    
    -- CPU Temperature trend
    ROUND(REGR_SLOPE(avg_cpu_temp, day_epoch)::NUMERIC, 6) AS cpu_temp_slope,
    ROUND(REGR_R2(avg_cpu_temp, day_epoch)::NUMERIC, 3) AS cpu_temp_r2,
    
    -- Data quality
    COUNT(*) AS days_with_data

FROM v_cfrs_daily_tier1_trends
WHERE day_bucket >= NOW() - INTERVAL '30 days'
  AND avg_cpu_iowait IS NOT NULL
GROUP BY system_id
HAVING COUNT(*) >= 20  -- Require 20+ days for reliable trend
ORDER BY cpu_iowait_slope DESC;


-- Query T2: Identify Degrading Systems (Positive Slope + High R²)
-- Use Case: High-confidence degradation detection
WITH trend_analysis AS (
    SELECT
        system_id,
        REGR_SLOPE(avg_cpu_iowait, day_epoch) AS cpu_iowait_slope,
        REGR_R2(avg_cpu_iowait, day_epoch) AS cpu_iowait_r2,
        REGR_SLOPE(avg_context_switch, day_epoch) AS context_switch_slope,
        REGR_R2(avg_context_switch, day_epoch) AS context_switch_r2,
        REGR_SLOPE(avg_swap_out, day_epoch) AS swap_out_slope,
        REGR_R2(avg_swap_out, day_epoch) AS swap_out_r2,
        COUNT(*) AS days_with_data
    FROM v_cfrs_daily_tier1_trends
    WHERE day_bucket >= NOW() - INTERVAL '30 days'
    GROUP BY system_id
    HAVING COUNT(*) >= 20
)
SELECT
    s.hostname,
    s.status,
    ROUND(t.cpu_iowait_slope::NUMERIC, 6) AS cpu_iowait_slope,
    ROUND(t.cpu_iowait_r2::NUMERIC, 3) AS cpu_iowait_r2,
    ROUND(t.context_switch_slope::NUMERIC, 6) AS context_switch_slope,
    ROUND(t.context_switch_r2::NUMERIC, 3) AS context_switch_r2,
    ROUND(t.swap_out_slope::NUMERIC, 6) AS swap_out_slope,
    ROUND(t.swap_out_r2::NUMERIC, 3) AS swap_out_r2,
    
    -- Degradation confidence score (count of strong positive trends)
    (
        (CASE WHEN t.cpu_iowait_slope > 0.05 AND t.cpu_iowait_r2 > 0.7 THEN 1 ELSE 0 END) +
        (CASE WHEN t.context_switch_slope > 100 AND t.context_switch_r2 > 0.7 THEN 1 ELSE 0 END) +
        (CASE WHEN t.swap_out_slope > 0.05 AND t.swap_out_r2 > 0.7 THEN 1 ELSE 0 END)
    ) AS degradation_signals,
    
    t.days_with_data

FROM trend_analysis t
JOIN systems s ON t.system_id = s.system_id
WHERE (
    (t.cpu_iowait_slope > 0.05 AND t.cpu_iowait_r2 > 0.7) OR
    (t.context_switch_slope > 100 AND t.context_switch_r2 > 0.7) OR
    (t.swap_out_slope > 0.05 AND t.swap_out_r2 > 0.7)
)
ORDER BY degradation_signals DESC, cpu_iowait_slope DESC;


-- Query T3: Week-over-Week Trend Comparison
-- Use Case: Detect recent acceleration in degradation
SELECT
    system_id,
    week_bucket,
    
    -- Week-over-week change in metrics
    weekly_avg_cpu_iowait,
    LAG(weekly_avg_cpu_iowait, 1) OVER (PARTITION BY system_id ORDER BY week_bucket) AS prev_week_cpu_iowait,
    weekly_avg_cpu_iowait - LAG(weekly_avg_cpu_iowait, 1) OVER (PARTITION BY system_id ORDER BY week_bucket) AS wow_change_cpu_iowait,
    
    weekly_avg_context_switch,
    LAG(weekly_avg_context_switch, 1) OVER (PARTITION BY system_id ORDER BY week_bucket) AS prev_week_context_switch,
    weekly_avg_context_switch - LAG(weekly_avg_context_switch, 1) OVER (PARTITION BY system_id ORDER BY week_bucket) AS wow_change_context_switch,
    
    weekly_total_samples

FROM v_cfrs_weekly_tier1_trends
WHERE week_bucket >= NOW() - INTERVAL '12 weeks'
ORDER BY system_id, week_bucket DESC;


-- ============================================================================
-- COMPOSITE QUERIES (Multi-Component CFRS Inputs)
-- ============================================================================

-- Query C1: All CFRS Inputs for One System (Last 24 Hours)
-- Use Case: Comprehensive system health assessment
SELECT
    h.hour_bucket,
    
    -- Current values
    h.avg_cpu_iowait,
    h.avg_context_switch,
    h.avg_swap_out,
    h.avg_major_page_faults,
    h.avg_cpu_temp,
    
    -- Variance measures
    h.stddev_cpu_iowait,
    h.stddev_context_switch,
    h.stddev_swap_out,
    h.stddev_major_page_faults,
    
    -- Baseline for deviation
    b_iowait.baseline_mean AS baseline_cpu_iowait,
    b_iowait.baseline_stddev AS baseline_cpu_iowait_stddev,
    
    -- Sample quality
    h.cnt_cpu_iowait,
    h.total_samples

FROM cfrs_hourly_stats h
LEFT JOIN cfrs_system_baselines b_iowait
    ON h.system_id = b_iowait.system_id
   AND b_iowait.metric_name = 'cpu_iowait'
   AND b_iowait.is_active = TRUE

WHERE h.system_id = 42  -- Replace with target system_id
  AND h.hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY h.hour_bucket DESC;


-- Query C2: CFRS Risk Matrix (All Systems, All Components)
-- Use Case: Dashboard overview of system health
WITH deviation_component AS (
    SELECT
        h.system_id,
        ABS((h.avg_cpu_iowait - b.baseline_mean) / NULLIF(b.baseline_stddev, 0)) AS cpu_iowait_z
    FROM cfrs_hourly_stats h
    LEFT JOIN cfrs_system_baselines b
        ON h.system_id = b.system_id AND b.metric_name = 'cpu_iowait' AND b.is_active = TRUE
    WHERE h.hour_bucket = (SELECT MAX(hour_bucket) FROM cfrs_hourly_stats)
),
variance_component AS (
    SELECT
        system_id,
        stddev_cpu_iowait / NULLIF(avg_cpu_iowait, 0) AS cpu_iowait_cv
    FROM cfrs_hourly_stats
    WHERE hour_bucket = (SELECT MAX(hour_bucket) FROM cfrs_hourly_stats)
),
trend_component AS (
    SELECT
        system_id,
        REGR_SLOPE(avg_cpu_iowait, day_epoch) AS cpu_iowait_slope
    FROM v_cfrs_daily_tier1_trends
    WHERE day_bucket >= NOW() - INTERVAL '30 days'
    GROUP BY system_id
    HAVING COUNT(*) >= 20
)
SELECT
    s.hostname,
    s.status,
    ROUND(d.cpu_iowait_z, 2) AS deviation_score,
    ROUND(v.cpu_iowait_cv, 3) AS variance_score,
    ROUND(t.cpu_iowait_slope::NUMERIC, 6) AS trend_score,
    
    -- Simple composite (do NOT use this in production - implement proper CFRS)
    ROUND((
        COALESCE(d.cpu_iowait_z, 0) * 0.4 +
        COALESCE(v.cpu_iowait_cv * 10, 0) * 0.3 +
        COALESCE(t.cpu_iowait_slope * 10000, 0) * 0.3
    )::NUMERIC, 2) AS simple_composite_score

FROM systems s
LEFT JOIN deviation_component d ON s.system_id = d.system_id
LEFT JOIN variance_component v ON s.system_id = v.system_id
LEFT JOIN trend_component t ON s.system_id = t.system_id
WHERE s.status = 'active'
ORDER BY simple_composite_score DESC;


-- ============================================================================
-- BASELINE COMPUTATION QUERIES
-- ============================================================================

-- Query B1: Compute Baseline for One System (Insert into Baseline Table)
-- Use Case: Initial baseline creation or refresh
INSERT INTO cfrs_system_baselines (
    system_id, metric_name,
    baseline_mean, baseline_stddev, baseline_median,
    baseline_window_days, baseline_start, baseline_end, sample_count
)
SELECT
    42 AS system_id,  -- Replace with target system_id
    'cpu_iowait' AS metric_name,
    AVG(avg_cpu_iowait) AS baseline_mean,
    STDDEV(avg_cpu_iowait) AS baseline_stddev,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_cpu_iowait) AS baseline_median,
    30 AS baseline_window_days,
    MIN(hour_bucket) AS baseline_start,
    MAX(hour_bucket) AS baseline_end,
    COUNT(*) AS sample_count
FROM cfrs_hourly_stats
WHERE system_id = 42
  AND hour_bucket >= NOW() - INTERVAL '30 days'
  AND avg_cpu_iowait IS NOT NULL
ON CONFLICT (system_id, metric_name, baseline_start, baseline_end)
DO UPDATE SET
    baseline_mean = EXCLUDED.baseline_mean,
    baseline_stddev = EXCLUDED.baseline_stddev,
    baseline_median = EXCLUDED.baseline_median,
    sample_count = EXCLUDED.sample_count,
    computed_at = NOW();


-- Query B2: Bulk Baseline Computation (All Systems, All Tier-1 Metrics)
-- Use Case: Initial setup or periodic baseline refresh
INSERT INTO cfrs_system_baselines (
    system_id, metric_name,
    baseline_mean, baseline_stddev, baseline_median,
    baseline_window_days, baseline_start, baseline_end, sample_count,
    is_active
)
-- CPU I/O Wait baselines
SELECT
    system_id,
    'cpu_iowait' AS metric_name,
    AVG(avg_cpu_iowait),
    STDDEV(avg_cpu_iowait),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_cpu_iowait),
    30,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE
FROM cfrs_hourly_stats
WHERE hour_bucket >= NOW() - INTERVAL '30 days'
  AND avg_cpu_iowait IS NOT NULL
GROUP BY system_id
HAVING COUNT(*) >= 100  -- Require 100+ hours of data

UNION ALL

-- Context Switch baselines
SELECT
    system_id,
    'context_switch' AS metric_name,
    AVG(avg_context_switch),
    STDDEV(avg_context_switch),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_context_switch),
    30,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE
FROM cfrs_hourly_stats
WHERE hour_bucket >= NOW() - INTERVAL '30 days'
  AND avg_context_switch IS NOT NULL
GROUP BY system_id
HAVING COUNT(*) >= 100

UNION ALL

-- Swap Out baselines
SELECT
    system_id,
    'swap_out' AS metric_name,
    AVG(avg_swap_out),
    STDDEV(avg_swap_out),
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_swap_out),
    30,
    MIN(hour_bucket),
    MAX(hour_bucket),
    COUNT(*),
    TRUE
FROM cfrs_hourly_stats
WHERE hour_bucket >= NOW() - INTERVAL '30 days'
  AND avg_swap_out IS NOT NULL
GROUP BY system_id
HAVING COUNT(*) >= 100

ON CONFLICT (system_id, metric_name, baseline_start, baseline_end)
DO UPDATE SET
    baseline_mean = EXCLUDED.baseline_mean,
    baseline_stddev = EXCLUDED.baseline_stddev,
    baseline_median = EXCLUDED.baseline_median,
    sample_count = EXCLUDED.sample_count,
    computed_at = NOW(),
    is_active = TRUE;


-- ============================================================================
-- MONITORING QUERIES
-- ============================================================================

-- Query M1: Aggregate Freshness Check
SELECT
    view_name,
    refresh_lag,
    last_run_duration,
    last_run_status,
    CASE
        WHEN refresh_lag > INTERVAL '3 hours' THEN '⚠️  STALE'
        WHEN last_run_status != 'Success' THEN '❌ FAILED'
        ELSE '✅ OK'
    END AS status
FROM timescaledb_information.continuous_aggregate_stats
WHERE view_name LIKE 'cfrs_%'
ORDER BY refresh_lag DESC;


-- Query M2: Baseline Coverage Report
SELECT
    metric_name,
    COUNT(DISTINCT system_id) AS systems_with_baseline,
    (SELECT COUNT(*) FROM systems WHERE status = 'active') AS total_active_systems,
    ROUND(100.0 * COUNT(DISTINCT system_id) / (SELECT COUNT(*) FROM systems WHERE status = 'active'), 1) AS coverage_pct,
    AVG(sample_count) AS avg_samples,
    MAX(computed_at) AS latest_computation
FROM cfrs_system_baselines
WHERE is_active = TRUE
GROUP BY metric_name
ORDER BY coverage_pct ASC;


-- Query M3: Data Quality Audit
SELECT
    'Hourly Stats' AS aggregate_type,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT system_id) AS systems_covered,
    ROUND(AVG(total_samples), 1) AS avg_samples_per_hour,
    ROUND(100.0 * SUM(CASE WHEN cnt_cpu_iowait >= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_sufficient_samples,
    MIN(hour_bucket) AS earliest_data,
    MAX(hour_bucket) AS latest_data
FROM cfrs_hourly_stats

UNION ALL

SELECT
    'Daily Stats' AS aggregate_type,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT system_id) AS systems_covered,
    ROUND(AVG(total_samples), 1) AS avg_samples_per_day,
    ROUND(100.0 * SUM(CASE WHEN cnt_cpu_iowait >= 50 THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_sufficient_samples,
    MIN(day_bucket) AS earliest_data,
    MAX(day_bucket) AS latest_data
FROM cfrs_daily_stats;


-- ============================================================================
-- END OF QUERY COOKBOOK
-- ============================================================================

-- Note: All queries above provide INPUTS to CFRS computation.
-- Actual CFRS scoring should be done in application layer, not SQL.
