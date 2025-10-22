-- ============================================================================
-- Performance Optimization Indexes
-- ============================================================================
-- Purpose: Additional indexes for query optimization beyond schema defaults
-- ============================================================================

-- ============================================================================
-- USAGE_METRICS Indexes
-- ============================================================================

-- Composite index for time-range queries filtered by system
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_system_timestamp_cpu
ON usage_metrics(system_id, timestamp DESC, cpu_percent);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_system_timestamp_ram
ON usage_metrics(system_id, timestamp DESC, ram_percent);

-- Index for finding high-usage periods
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_high_cpu
ON usage_metrics(cpu_percent DESC, timestamp DESC)
WHERE cpu_percent > 80;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_high_ram
ON usage_metrics(ram_percent DESC, timestamp DESC)
WHERE ram_percent > 80;

-- Index for GPU-related queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_gpu
ON usage_metrics(system_id, gpu_utilization, timestamp DESC)
WHERE gpu_utilization IS NOT NULL;

-- Index for I/O analysis
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_io_wait
ON usage_metrics(disk_io_wait_percent DESC, timestamp DESC)
WHERE disk_io_wait_percent > 20;

-- GIN index for per-core CPU data (JSONB)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_cpu_per_core
ON usage_metrics USING GIN(cpu_per_core);

-- BRIN index for large time-series data (alternative for older data)
-- Uncomment if table grows very large (millions of rows)
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_usage_metrics_timestamp_brin
-- ON usage_metrics USING BRIN(timestamp);

-- ============================================================================
-- PERFORMANCE_SUMMARIES Indexes
-- ============================================================================

-- Index for finding underutilized systems
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_perf_summary_low_utilization
ON performance_summaries(utilization_score ASC, period_start DESC)
WHERE is_underutilized = TRUE;

-- Index for finding systems with bottlenecks
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_perf_summary_bottleneck
ON performance_summaries(system_id, period_start DESC)
WHERE has_bottleneck = TRUE;

-- Composite index for ranking queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_perf_summary_ranking
ON performance_summaries(period_type, period_start DESC, utilization_score DESC);

-- ============================================================================
-- USER_SESSIONS Indexes
-- ============================================================================

-- Index for active session queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_active_user
ON user_sessions(user_id, login_time DESC)
WHERE is_active = TRUE;

-- Index for session duration analysis
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_duration
ON user_sessions(session_duration_minutes DESC, login_time DESC)
WHERE session_duration_minutes IS NOT NULL;

-- GIN index for process search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_sessions_processes
ON user_sessions USING GIN(active_processes);

-- ============================================================================
-- ALERT_LOGS Indexes
-- ============================================================================

-- Index for unacknowledged critical alerts
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_critical_unack
ON alert_logs(triggered_at DESC)
WHERE severity = 'critical' AND is_acknowledged = FALSE;

-- Index for alert resolution time analysis
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_resolution_time
ON alert_logs(triggered_at, resolved_at)
WHERE resolved_at IS NOT NULL;

-- Composite index for system alert history
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_alerts_system_history
ON alert_logs(system_id, triggered_at DESC, severity);

-- ============================================================================
-- PROCESS_SNAPSHOTS Indexes
-- ============================================================================

-- Index for finding resource-hungry processes
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_process_snapshots_resource_usage
ON process_snapshots(cpu_percent DESC, memory_percent DESC, timestamp DESC);

-- Index for process name searches
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_process_snapshots_name
ON process_snapshots(process_name, timestamp DESC);

-- Index for user process tracking
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_process_snapshots_user
ON process_snapshots(user_name, timestamp DESC);

-- Text search index for command line
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_process_snapshots_cmdline
ON process_snapshots USING GIN(to_tsvector('english', command_line));

-- ============================================================================
-- OPTIMIZATION_REPORTS Indexes
-- ============================================================================

-- Index for pending high-priority reports
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reports_pending_priority
ON optimization_reports(priority_score DESC, created_at DESC)
WHERE status = 'pending';

-- Index for report type analysis
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reports_type_severity
ON optimization_reports(report_type, severity, created_at DESC);

-- GIN index for recommendation search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reports_recommendations
ON optimization_reports USING GIN(recommendations);

-- ============================================================================
-- SYSTEMS Indexes (additional)
-- ============================================================================

-- Composite index for hardware specs queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_systems_specs
ON systems(cpu_cores, ram_total_gb, gpu_count)
WHERE status = 'active';

-- Text search for hostname/location
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_systems_text_search
ON systems USING GIN(to_tsvector('english', hostname || ' ' || COALESCE(location, '')));

-- Index for offline system detection
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_systems_offline
ON systems(last_seen DESC)
WHERE status = 'active' AND last_seen < CURRENT_TIMESTAMP - INTERVAL '1 hour';

-- ============================================================================
-- USERS Indexes
-- ============================================================================

-- Index for user search
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_search
ON users(username, full_name);

-- Index for department-based queries
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_dept_role
ON users(department, role);

-- ============================================================================
-- Index Statistics & Monitoring
-- ============================================================================

-- View to monitor index usage
CREATE OR REPLACE VIEW index_usage_stats AS
SELECT
    schemaname,
    tablename,
    indexname,
    idx_scan AS index_scans,
    idx_tup_read AS tuples_read,
    idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    CASE 
        WHEN idx_scan = 0 THEN 'UNUSED'
        WHEN idx_scan < 100 THEN 'LOW USAGE'
        ELSE 'ACTIVE'
    END AS usage_status
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan ASC, pg_relation_size(indexrelid) DESC;

-- View to find missing indexes (queries with high seq scans)
CREATE OR REPLACE VIEW potential_missing_indexes AS
SELECT
    schemaname,
    tablename,
    seq_scan AS sequential_scans,
    seq_tup_read AS rows_read_sequentially,
    idx_scan AS index_scans,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS table_size,
    CASE 
        WHEN seq_scan > 1000 AND seq_scan > idx_scan THEN 'HIGH PRIORITY'
        WHEN seq_scan > 100 THEN 'MEDIUM PRIORITY'
        ELSE 'LOW PRIORITY'
    END AS index_recommendation
FROM pg_stat_user_tables
WHERE schemaname = 'public'
    AND seq_scan > 0
ORDER BY seq_scan DESC, pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- ============================================================================
-- Index Maintenance Commands (for reference)
-- ============================================================================

/*
-- Rebuild all indexes (run during maintenance window)
REINDEX DATABASE lab_resource_monitor;

-- Rebuild specific table indexes
REINDEX TABLE usage_metrics;

-- Analyze tables for query planner optimization
ANALYZE usage_metrics;
ANALYZE performance_summaries;
ANALYZE alert_logs;

-- Update statistics for all tables
ANALYZE;

-- Check for bloated indexes
SELECT
    schemaname,
    tablename,
    indexname,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
    AND idx_scan = 0
    AND pg_relation_size(indexrelid) > 1024 * 1024  -- > 1MB
ORDER BY pg_relation_size(indexrelid) DESC;

-- Drop unused indexes (be careful!)
-- DROP INDEX CONCURRENTLY index_name;
*/

-- ============================================================================
-- Query Performance Monitoring
-- ============================================================================

-- Enable pg_stat_statements for query performance tracking
-- Add to postgresql.conf: shared_preload_libraries = 'pg_stat_statements'
-- Then: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- View to find slow queries
CREATE OR REPLACE VIEW slow_queries AS
SELECT
    query,
    calls,
    total_exec_time / 1000 AS total_time_seconds,
    mean_exec_time / 1000 AS avg_time_seconds,
    max_exec_time / 1000 AS max_time_seconds,
    rows,
    100.0 * shared_blks_hit / NULLIF(shared_blks_hit + shared_blks_read, 0) AS cache_hit_ratio
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 20;

-- ============================================================================
-- Verification
-- ============================================================================

-- Check all indexes on usage_metrics table
SELECT
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename = 'usage_metrics'
ORDER BY indexname;

-- Show total index sizes per table
SELECT
    tablename,
    COUNT(*) AS index_count,
    pg_size_pretty(SUM(pg_relation_size(indexrelid))) AS total_index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
GROUP BY tablename
ORDER BY SUM(pg_relation_size(indexrelid)) DESC;

-- ============================================================================
-- END OF INDEXES
-- ============================================================================
