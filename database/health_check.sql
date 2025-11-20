-- ============================================================================
-- Database Health Check & Maintenance Script
-- ============================================================================
-- Purpose: Diagnose database health, performance, and data integrity
-- Run this periodically to ensure optimal system operation
-- ============================================================================

\echo '================================================================'
\echo 'Lab Resource Monitor - Database Health Check'
\echo '================================================================'
\echo ''


-- TODO : UPDATE THE HEALTH CHECK ACCORDING TO THE EXISTING SCHEMA
-- ============================================================================
-- 1. Database Size & Growth
-- ============================================================================

\echo '1. DATABASE SIZE & STORAGE'
\echo '----------------------------'

SELECT 
    pg_database.datname AS database_name,
    pg_size_pretty(pg_database_size(pg_database.datname)) AS size
FROM pg_database
WHERE datname = 'lab_resource_monitor';

\echo ''
\echo 'Table Sizes:'

SELECT
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - 
                   pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

\echo ''

-- ============================================================================
-- 2. Data Statistics
-- ============================================================================

\echo '2. DATA STATISTICS'
\echo '----------------------------'

\echo 'Record Counts:'

SELECT 
    'Systems Registered' AS metric,
    COUNT(*) AS count
FROM systems
UNION ALL
SELECT 
    'Active Systems',
    COUNT(*)
FROM systems WHERE status = 'active'
UNION ALL
SELECT 
    'Total Metrics Collected',
    COUNT(*)
FROM usage_metrics
UNION ALL
SELECT 
    'Metrics (Last 24h)',
    COUNT(*)
FROM usage_metrics WHERE timestamp >= NOW() - INTERVAL '24 hours'
UNION ALL
SELECT 
    'Active Alerts',
    COUNT(*)
FROM alert_logs WHERE resolved_at IS NULL
UNION ALL
SELECT 
    'Performance Summaries',
    COUNT(*)
FROM performance_summaries
UNION ALL
SELECT 
    'Optimization Reports',
    COUNT(*)
FROM optimization_reports;

\echo ''

-- ============================================================================
-- 3. System Health
-- ============================================================================

\echo '3. SYSTEM HEALTH STATUS'
\echo '----------------------------'

SELECT 
    COUNT(*) AS total_systems,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN status = 'offline' THEN 1 ELSE 0 END) AS offline,
    SUM(CASE WHEN status = 'maintenance' THEN 1 ELSE 0 END) AS maintenance,
    SUM(CASE WHEN last_seen < NOW() - INTERVAL '1 hour' AND status = 'active' THEN 1 ELSE 0 END) AS not_reporting
FROM systems;

\echo ''
\echo 'Systems Not Reporting (>1 hour):'

SELECT 
    hostname,
    location,
    last_seen,
    EXTRACT(EPOCH FROM (NOW() - last_seen))/3600 AS hours_offline
FROM systems
WHERE last_seen < NOW() - INTERVAL '1 hour'
    AND status = 'active'
ORDER BY last_seen ASC;

\echo ''

-- ============================================================================
-- 4. Data Quality Checks
-- ============================================================================

\echo '4. DATA QUALITY CHECKS'
\echo '----------------------------'

\echo 'Invalid Metrics (percentage values outside 0-100):'

SELECT 
    COUNT(*) AS invalid_metrics
FROM usage_metrics
WHERE cpu_percent < 0 OR cpu_percent > 100
    OR ram_percent < 0 OR ram_percent > 100
    OR disk_percent < 0 OR disk_percent > 100;

\echo ''
\echo 'Orphaned Metrics (no matching system):'

SELECT 
    COUNT(*) AS orphaned_metrics
FROM usage_metrics um
LEFT JOIN systems s ON um.system_id = s.system_id
WHERE s.system_id IS NULL;

\echo ''
\echo 'Duplicate Timestamps:'

SELECT 
    system_id,
    timestamp,
    COUNT(*) AS duplicates
FROM usage_metrics
GROUP BY system_id, timestamp
HAVING COUNT(*) > 1
LIMIT 5;

\echo ''

-- ============================================================================
-- 5. Performance Metrics
-- ============================================================================

\echo '5. QUERY PERFORMANCE'
\echo '----------------------------'

\echo 'Index Usage Statistics (Top 10):'

SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS times_used,
    idx_tup_read AS rows_read,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC
LIMIT 10;

\echo ''
\echo 'Unused Indexes (never used, >1MB):'

SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
    AND idx_scan = 0
    AND pg_relation_size(indexrelid) > 1048576
ORDER BY pg_relation_size(indexrelid) DESC;

\echo ''

-- ============================================================================
-- 6. TimescaleDB Health (if applicable)
-- ============================================================================

\echo '6. TIMESCALEDB STATUS'
\echo '----------------------------'

-- Check if TimescaleDB is installed
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb') THEN
        RAISE NOTICE 'TimescaleDB is installed';
    ELSE
        RAISE NOTICE 'TimescaleDB is NOT installed (using regular PostgreSQL)';
    END IF;
END $$;

\echo ''

-- If TimescaleDB exists, show hypertable info
SELECT
    hypertable_name,
    num_chunks,
    pg_size_pretty(total_bytes) AS total_size,
    pg_size_pretty(compressed_total_bytes) AS compressed_size,
    ROUND(100.0 * compressed_total_bytes / NULLIF(total_bytes, 0), 2) AS compression_ratio
FROM (
    SELECT 
        h.table_name AS hypertable_name,
        COUNT(c.chunk_name) AS num_chunks,
        SUM(c.total_bytes) AS total_bytes,
        SUM(c.compressed_total_bytes) AS compressed_total_bytes
    FROM timescaledb_information.hypertables h
    LEFT JOIN timescaledb_information.chunks c ON h.table_name = c.hypertable_name
    GROUP BY h.table_name
) stats
WHERE EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'timescaledb');

\echo ''

-- ============================================================================
-- 7. Alert Summary
-- ============================================================================

\echo '7. ALERT SUMMARY (Last 7 Days)'
\echo '----------------------------'

SELECT 
    severity,
    COUNT(*) AS total_alerts,
    SUM(CASE WHEN resolved_at IS NULL THEN 1 ELSE 0 END) AS unresolved,
    SUM(CASE WHEN is_acknowledged THEN 1 ELSE 0 END) AS acknowledged
FROM alert_logs
WHERE triggered_at >= NOW() - INTERVAL '7 days'
GROUP BY severity
ORDER BY 
    CASE severity
        WHEN 'critical' THEN 1
        WHEN 'warning' THEN 2
        WHEN 'info' THEN 3
    END;

\echo ''
\echo 'Most Frequently Alerted Systems:'

SELECT 
    s.hostname,
    s.location,
    COUNT(*) AS alert_count,
    STRING_AGG(DISTINCT al.metric_name, ', ') AS alert_types
FROM alert_logs al
JOIN systems s ON al.system_id = s.system_id
WHERE al.triggered_at >= NOW() - INTERVAL '7 days'
GROUP BY s.hostname, s.location
ORDER BY alert_count DESC
LIMIT 5;

\echo ''

-- ============================================================================
-- 8. Database Connections
-- ============================================================================

\echo '8. DATABASE CONNECTIONS'
\echo '----------------------------'

SELECT 
    COUNT(*) AS total_connections,
    SUM(CASE WHEN state = 'active' THEN 1 ELSE 0 END) AS active,
    SUM(CASE WHEN state = 'idle' THEN 1 ELSE 0 END) AS idle,
    MAX(EXTRACT(EPOCH FROM (NOW() - query_start))) AS longest_query_seconds
FROM pg_stat_activity
WHERE datname = 'lab_resource_monitor';

\echo ''

-- ============================================================================
-- 9. Last Collection Times
-- ============================================================================

\echo '9. DATA COLLECTION STATUS'
\echo '----------------------------'

SELECT 
    s.hostname,
    MAX(um.timestamp) AS last_metric,
    EXTRACT(EPOCH FROM (NOW() - MAX(um.timestamp)))/60 AS minutes_ago
FROM systems s
LEFT JOIN usage_metrics um ON s.system_id = um.system_id
WHERE s.status = 'active'
GROUP BY s.hostname
ORDER BY MAX(um.timestamp) DESC NULLS LAST;

\echo ''

-- ============================================================================
-- 10. Recommendations
-- ============================================================================

\echo '10. MAINTENANCE RECOMMENDATIONS'
\echo '----------------------------'

-- Check if VACUUM needed
SELECT 
    schemaname,
    tablename,
    n_dead_tup AS dead_tuples,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND n_dead_tup > 1000
    AND n_dead_tup::float / NULLIF(n_live_tup + n_dead_tup, 0) > 0.1
ORDER BY dead_ratio DESC;

\echo ''
\echo 'Recommendations:'
\echo '- If dead_ratio > 10%, consider running VACUUM ANALYZE'
\echo '- Check for unused indexes and consider dropping them'
\echo '- Monitor systems "not_reporting" and investigate'
\echo '- Review unresolved critical alerts'
\echo ''

-- ============================================================================
-- 11. Sample Maintenance Commands
-- ============================================================================

\echo '11. MAINTENANCE COMMANDS (Run as needed)'
\echo '----------------------------'
\echo '-- Analyze all tables (update statistics):'
\echo 'ANALYZE;'
\echo ''
\echo '-- Vacuum and analyze (reclaim space):'
\echo 'VACUUM ANALYZE;'
\echo ''
\echo '-- Reindex all indexes (if fragmented):'
\echo 'REINDEX DATABASE lab_resource_monitor;'
\echo ''
\echo '-- Check for bloat:'
\echo 'SELECT * FROM pg_stat_user_tables WHERE n_dead_tup > 10000;'
\echo ''

-- ============================================================================
-- END OF HEALTH CHECK
-- ============================================================================

\echo '================================================================'
\echo 'Health Check Complete'
\echo '================================================================'
