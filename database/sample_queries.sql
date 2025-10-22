-- ============================================================================
-- Sample Analytics Queries
-- ============================================================================
-- Purpose: Ready-to-use SQL queries for common analytical tasks
-- ============================================================================

-- ============================================================================
-- QUERY 1: Current System Health Overview
-- ============================================================================
-- Shows real-time status of all systems with latest metrics

SELECT 
    s.hostname,
    s.location,
    s.cpu_cores,
    s.ram_total_gb,
    s.gpu_model,
    um.cpu_percent AS current_cpu,
    um.ram_percent AS current_ram,
    um.gpu_utilization AS current_gpu,
    um.load_avg_1min,
    um.timestamp AS last_update,
    EXTRACT(EPOCH FROM (NOW() - s.last_seen))/60 AS minutes_offline,
    CASE 
        WHEN um.cpu_percent > 90 OR um.ram_percent > 90 THEN 'CRITICAL'
        WHEN um.cpu_percent > 80 OR um.ram_percent > 80 THEN 'HIGH LOAD'
        WHEN um.cpu_percent < 20 AND um.ram_percent < 20 THEN 'UNDERUTILIZED'
        ELSE 'NORMAL'
    END AS status
FROM systems s
LEFT JOIN LATERAL (
    SELECT * FROM usage_metrics
    WHERE system_id = s.system_id
    ORDER BY timestamp DESC
    LIMIT 1
) um ON TRUE
WHERE s.status = 'active'
ORDER BY 
    CASE 
        WHEN um.cpu_percent > 90 THEN 1
        WHEN um.ram_percent > 90 THEN 2
        ELSE 3
    END,
    s.hostname;

-- ============================================================================
-- QUERY 2: Weekly Utilization Trends
-- ============================================================================
-- Average utilization by day for the past week

SELECT 
    s.hostname,
    s.location,
    DATE(um.timestamp) AS date,
    ROUND(AVG(um.cpu_percent), 2) AS avg_cpu,
    ROUND(MAX(um.cpu_percent), 2) AS peak_cpu,
    ROUND(AVG(um.ram_percent), 2) AS avg_ram,
    ROUND(MAX(um.ram_percent), 2) AS peak_ram,
    COUNT(*) AS sample_count
FROM systems s
JOIN usage_metrics um ON s.system_id = um.system_id
WHERE um.timestamp >= CURRENT_DATE - INTERVAL '7 days'
    AND s.status = 'active'
GROUP BY s.system_id, s.hostname, s.location, DATE(um.timestamp)
ORDER BY s.hostname, DATE(um.timestamp) DESC;

-- ============================================================================
-- QUERY 3: Identify Systems Requiring RAM Upgrade
-- ============================================================================
-- Systems with high memory pressure (95th percentile RAM > 85%)

SELECT 
    s.hostname,
    s.location,
    s.ram_total_gb AS current_ram_gb,
    ROUND(AVG(um.ram_percent), 2) AS avg_ram_usage,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY um.ram_percent), 2) AS p95_ram_usage,
    ROUND(AVG(um.swap_percent), 2) AS avg_swap_usage,
    SUM(CASE WHEN um.swap_percent > 5 THEN 1 ELSE 0 END) AS swap_active_count,
    s.ram_total_gb * 2 AS recommended_ram_gb,
    'High memory pressure - RAM upgrade recommended' AS recommendation
FROM systems s
JOIN usage_metrics um ON s.system_id = um.system_id
WHERE um.timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    AND s.status = 'active'
GROUP BY s.system_id, s.hostname, s.location, s.ram_total_gb
HAVING PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY um.ram_percent) > 85
    OR SUM(CASE WHEN um.swap_percent > 5 THEN 1 ELSE 0 END) > 50
ORDER BY PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY um.ram_percent) DESC;

-- ============================================================================
-- QUERY 4: Disk I/O Bottleneck Analysis
-- ============================================================================
-- Systems with consistently high disk I/O wait times

SELECT 
    s.hostname,
    s.location,
    s.disk_type,
    s.disk_total_gb,
    ROUND(AVG(um.disk_io_wait_percent), 2) AS avg_io_wait,
    ROUND(MAX(um.disk_io_wait_percent), 2) AS max_io_wait,
    ROUND(AVG(um.disk_read_mb_s + um.disk_write_mb_s), 2) AS avg_total_io_mbs,
    SUM(CASE WHEN um.disk_io_wait_percent > 30 THEN 1 ELSE 0 END) AS high_wait_count,
    CASE 
        WHEN s.disk_type = 'HDD' THEN 'Upgrade to SSD/NVMe'
        ELSE 'Investigate I/O intensive processes'
    END AS recommendation
FROM systems s
JOIN usage_metrics um ON s.system_id = um.system_id
WHERE um.timestamp >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    AND s.status = 'active'
    AND um.disk_io_wait_percent IS NOT NULL
GROUP BY s.system_id, s.hostname, s.location, s.disk_type, s.disk_total_gb
HAVING AVG(um.disk_io_wait_percent) > 20
ORDER BY AVG(um.disk_io_wait_percent) DESC;

-- ============================================================================
-- QUERY 5: Underutilized Systems for Reallocation
-- ============================================================================
-- Systems with low average CPU and RAM usage over 30 days

SELECT 
    s.hostname,
    s.location,
    s.cpu_cores,
    s.ram_total_gb,
    s.gpu_model,
    ROUND(AVG(um.cpu_percent), 2) AS avg_cpu,
    ROUND(AVG(um.ram_percent), 2) AS avg_ram,
    ROUND(AVG(um.gpu_utilization), 2) AS avg_gpu,
    calculate_utilization_score(
        AVG(um.cpu_percent),
        AVG(um.ram_percent),
        AVG(um.gpu_utilization)
    ) AS efficiency_score,
    'Consider consolidation or repurposing' AS recommendation
FROM systems s
JOIN usage_metrics um ON s.system_id = um.system_id
WHERE um.timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    AND s.status = 'active'
GROUP BY s.system_id, s.hostname, s.location, s.cpu_cores, s.ram_total_gb, s.gpu_model
HAVING AVG(um.cpu_percent) < 25 AND AVG(um.ram_percent) < 30
ORDER BY AVG(um.cpu_percent) + AVG(um.ram_percent) ASC;

-- ============================================================================
-- QUERY 6: GPU Utilization Analysis
-- ============================================================================
-- Compare GPU-equipped systems by utilization

SELECT 
    s.hostname,
    s.location,
    s.gpu_model,
    s.gpu_memory_gb,
    ROUND(AVG(um.gpu_utilization), 2) AS avg_gpu_usage,
    ROUND(MAX(um.gpu_utilization), 2) AS peak_gpu_usage,
    ROUND(AVG(um.gpu_temp), 2) AS avg_gpu_temp,
    SUM(CASE WHEN um.gpu_utilization < 10 THEN 1 ELSE 0 END) AS idle_count,
    SUM(CASE WHEN um.gpu_utilization > 90 THEN 1 ELSE 0 END) AS saturated_count,
    CASE 
        WHEN AVG(um.gpu_utilization) < 15 THEN 'GPU underutilized - consider reallocation'
        WHEN AVG(um.gpu_utilization) > 85 THEN 'GPU heavily utilized - consider upgrade or workload distribution'
        ELSE 'GPU utilization within normal range'
    END AS assessment
FROM systems s
JOIN usage_metrics um ON s.system_id = um.system_id
WHERE um.timestamp >= CURRENT_TIMESTAMP - INTERVAL '7 days'
    AND s.gpu_count > 0
    AND s.status = 'active'
GROUP BY s.system_id, s.hostname, s.location, s.gpu_model, s.gpu_memory_gb
ORDER BY avg_gpu_usage DESC;

-- ============================================================================
-- QUERY 7: Peak Usage Hours Analysis
-- ============================================================================
-- Identify peak usage times across all systems

SELECT 
    EXTRACT(HOUR FROM timestamp) AS hour_of_day,
    ROUND(AVG(cpu_percent), 2) AS avg_cpu,
    ROUND(AVG(ram_percent), 2) AS avg_ram,
    COUNT(DISTINCT system_id) AS active_systems,
    COUNT(*) AS total_samples
FROM usage_metrics
WHERE timestamp >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY EXTRACT(HOUR FROM timestamp)
ORDER BY hour_of_day;

-- ============================================================================
-- QUERY 8: Alert Frequency by System
-- ============================================================================
-- Systems generating the most alerts

SELECT 
    s.hostname,
    s.location,
    COUNT(*) AS alert_count,
    SUM(CASE WHEN al.severity = 'critical' THEN 1 ELSE 0 END) AS critical_alerts,
    SUM(CASE WHEN al.severity = 'warning' THEN 1 ELSE 0 END) AS warning_alerts,
    MAX(al.triggered_at) AS last_alert,
    STRING_AGG(DISTINCT al.metric_name, ', ') AS alert_types
FROM alert_logs al
JOIN systems s ON al.system_id = s.system_id
WHERE al.triggered_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
GROUP BY s.system_id, s.hostname, s.location
ORDER BY alert_count DESC
LIMIT 20;

-- ============================================================================
-- QUERY 9: Cost Optimization Opportunities
-- ============================================================================
-- Combined view of optimization opportunities

WITH system_efficiency AS (
    SELECT 
        s.system_id,
        s.hostname,
        s.location,
        AVG(um.cpu_percent) AS avg_cpu,
        AVG(um.ram_percent) AS avg_ram,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY um.ram_percent) AS p95_ram
    FROM systems s
    JOIN usage_metrics um ON s.system_id = um.system_id
    WHERE um.timestamp >= CURRENT_TIMESTAMP - INTERVAL '30 days'
        AND s.status = 'active'
    GROUP BY s.system_id, s.hostname, s.location
)
SELECT 
    hostname,
    location,
    ROUND(avg_cpu, 2) AS avg_cpu_percent,
    ROUND(avg_ram, 2) AS avg_ram_percent,
    CASE 
        WHEN avg_cpu < 20 AND avg_ram < 25 THEN 'HIGH - Consolidate or repurpose'
        WHEN avg_cpu < 30 AND avg_ram < 35 THEN 'MEDIUM - Monitor for consolidation'
        WHEN p95_ram > 85 THEN 'UPGRADE - RAM upgrade needed'
        WHEN avg_cpu > 80 THEN 'UPGRADE - CPU upgrade or workload redistribution'
        ELSE 'OPTIMAL - No action needed'
    END AS optimization_priority,
    CASE 
        WHEN avg_cpu < 20 AND avg_ram < 25 THEN 'Resource waste - low utilization'
        WHEN p95_ram > 85 THEN 'Performance bottleneck - insufficient RAM'
        WHEN avg_cpu > 80 THEN 'Performance bottleneck - CPU constrained'
        ELSE 'Well balanced'
    END AS reason
FROM system_efficiency
ORDER BY 
    CASE 
        WHEN avg_cpu < 20 AND avg_ram < 25 THEN 1
        WHEN p95_ram > 85 THEN 2
        WHEN avg_cpu > 80 THEN 3
        ELSE 4
    END,
    avg_cpu DESC;

-- ============================================================================
-- QUERY 10: System Comparison Dashboard
-- ============================================================================
-- Side-by-side comparison of all systems

SELECT 
    s.hostname,
    s.location,
    s.cpu_cores || ' cores' AS cpu_config,
    s.ram_total_gb || ' GB' AS ram_config,
    COALESCE(s.gpu_model, 'No GPU') AS gpu_config,
    ROUND(ps.avg_cpu_percent, 1) || '%' AS avg_cpu,
    ROUND(ps.avg_ram_percent, 1) || '%' AS avg_ram,
    ROUND(ps.avg_gpu_percent, 1) || '%' AS avg_gpu,
    ps.utilization_score AS score,
    CASE 
        WHEN ps.is_underutilized THEN '⚠️ Underutilized'
        WHEN ps.is_overutilized THEN '🔴 Overloaded'
        WHEN ps.has_bottleneck THEN '⚡ Bottleneck'
        ELSE '✅ Normal'
    END AS status_icon
FROM systems s
LEFT JOIN LATERAL (
    SELECT * FROM performance_summaries
    WHERE system_id = s.system_id
        AND period_type = 'daily'
    ORDER BY period_start DESC
    LIMIT 7
) ps ON TRUE
WHERE s.status = 'active'
ORDER BY ps.utilization_score DESC, s.hostname;

-- ============================================================================
-- QUERY 11: Generate Monthly Report Data
-- ============================================================================
-- Comprehensive monthly statistics for reporting

SELECT 
    s.hostname,
    s.location,
    COUNT(DISTINCT DATE(um.timestamp)) AS days_monitored,
    ROUND(AVG(um.cpu_percent), 2) AS avg_cpu,
    ROUND(MAX(um.cpu_percent), 2) AS max_cpu,
    ROUND(AVG(um.ram_percent), 2) AS avg_ram,
    ROUND(MAX(um.ram_percent), 2) AS max_ram,
    ROUND(AVG(um.load_avg_1min), 2) AS avg_load,
    SUM(CASE WHEN um.cpu_percent > 80 THEN 1 ELSE 0 END) * 5 / 60.0 AS hours_high_cpu,
    SUM(CASE WHEN um.ram_percent > 80 THEN 1 ELSE 0 END) * 5 / 60.0 AS hours_high_ram,
    (SELECT COUNT(*) FROM alert_logs al 
     WHERE al.system_id = s.system_id 
     AND al.triggered_at >= DATE_TRUNC('month', CURRENT_DATE)) AS alert_count
FROM systems s
JOIN usage_metrics um ON s.system_id = um.system_id
WHERE um.timestamp >= DATE_TRUNC('month', CURRENT_DATE)
    AND s.status = 'active'
GROUP BY s.system_id, s.hostname, s.location
ORDER BY s.hostname;

-- ============================================================================
-- QUERY 12: Time-Series Data for Grafana/Visualization
-- ============================================================================
-- Format optimized for time-series charts

SELECT 
    time_bucket('1 hour', timestamp) AS time,
    system_id,
    (SELECT hostname FROM systems WHERE system_id = um.system_id) AS hostname,
    AVG(cpu_percent) AS cpu,
    AVG(ram_percent) AS ram,
    AVG(gpu_utilization) AS gpu,
    AVG(disk_io_wait_percent) AS io_wait
FROM usage_metrics um
WHERE timestamp >= NOW() - INTERVAL '24 hours'
GROUP BY time_bucket('1 hour', timestamp), system_id
ORDER BY time DESC, system_id;

-- ============================================================================
-- END OF SAMPLE QUERIES
-- ============================================================================
