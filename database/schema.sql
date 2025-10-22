-- ============================================================================
-- Smart Resource Utilization & Hardware Optimization System
-- Core Database Schema
-- ============================================================================
-- Database: lab_resource_monitor
-- Version: 1.0
-- DBMS: PostgreSQL 14+ / TimescaleDB 2.0+
-- ============================================================================

-- Create database (run this separately if needed)
-- CREATE DATABASE lab_resource_monitor;
-- \c lab_resource_monitor;

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- For text search optimization

-- ============================================================================
-- TABLES: Core System Information
-- ============================================================================

-- Table: systems
-- Purpose: Store hardware specifications and metadata for each lab machine
CREATE TABLE systems (
    system_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    hostname VARCHAR(255) NOT NULL UNIQUE,
    ip_address INET,
    location VARCHAR(255), -- e.g., "Lab A", "Server Room B"
    department VARCHAR(100),
    
    -- Hardware Specifications
    cpu_model VARCHAR(255),
    cpu_cores INTEGER,
    cpu_threads INTEGER,
    cpu_base_freq NUMERIC(6,2), -- GHz
    
    ram_total_gb NUMERIC(8,2),
    ram_type VARCHAR(50), -- DDR4, DDR5, etc.
    
    gpu_model VARCHAR(255),
    gpu_memory_gb NUMERIC(8,2),
    gpu_count INTEGER DEFAULT 0,
    
    disk_total_gb NUMERIC(10,2),
    disk_type VARCHAR(50), -- SSD, HDD, NVMe
    
    os_name VARCHAR(100),
    os_version VARCHAR(100),
    
    -- Status
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'retired', 'offline')),
    
    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen TIMESTAMP,
    
    -- Indexing
    CONSTRAINT valid_cores CHECK (cpu_cores > 0),
    CONSTRAINT valid_ram CHECK (ram_total_gb > 0)
);

CREATE INDEX idx_systems_hostname ON systems(hostname);
CREATE INDEX idx_systems_status ON systems(status);
CREATE INDEX idx_systems_location ON systems(location);
CREATE INDEX idx_systems_last_seen ON systems(last_seen);

COMMENT ON TABLE systems IS 'Master table for lab system hardware specifications';

-- ============================================================================
-- TABLES: Time-Series Metrics
-- ============================================================================

-- Table: usage_metrics
-- Purpose: Store detailed real-time system utilization metrics
CREATE TABLE usage_metrics (
    metric_id BIGSERIAL,
    system_id UUID NOT NULL REFERENCES systems(system_id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- CPU Metrics
    cpu_percent NUMERIC(5,2), -- Overall CPU usage percentage
    cpu_per_core JSONB, -- Per-core usage as JSON array
    cpu_freq_current NUMERIC(8,2), -- Current frequency in MHz
    cpu_temp NUMERIC(5,2), -- Temperature in Celsius
    
    -- Memory Metrics
    ram_used_gb NUMERIC(8,2),
    ram_available_gb NUMERIC(8,2),
    ram_percent NUMERIC(5,2),
    swap_used_gb NUMERIC(8,2),
    swap_percent NUMERIC(5,2),
    
    -- GPU Metrics (NULL if no GPU)
    gpu_utilization NUMERIC(5,2), -- GPU usage percentage
    gpu_memory_used_gb NUMERIC(8,2),
    gpu_memory_percent NUMERIC(5,2),
    gpu_temp NUMERIC(5,2),
    gpu_power_draw NUMERIC(6,2), -- Watts
    
    -- Disk I/O Metrics
    disk_read_mb_s NUMERIC(10,2), -- MB/s
    disk_write_mb_s NUMERIC(10,2),
    disk_read_ops INTEGER,
    disk_write_ops INTEGER,
    disk_io_wait_percent NUMERIC(5,2),
    disk_used_gb NUMERIC(10,2),
    disk_percent NUMERIC(5,2),
    
    -- Network Metrics
    net_sent_mb_s NUMERIC(10,2),
    net_recv_mb_s NUMERIC(10,2),
    net_packets_sent INTEGER,
    net_packets_recv INTEGER,
    
    -- Process Metrics
    process_count INTEGER,
    thread_count INTEGER,
    
    -- System Load
    load_avg_1min NUMERIC(6,2),
    load_avg_5min NUMERIC(6,2),
    load_avg_15min NUMERIC(6,2),
    
    -- Metadata
    collection_duration_ms INTEGER, -- Time taken to collect metrics
    
    PRIMARY KEY (system_id, timestamp)
);

-- Optimize for time-series queries
CREATE INDEX idx_usage_metrics_timestamp ON usage_metrics(timestamp DESC);
CREATE INDEX idx_usage_metrics_system_time ON usage_metrics(system_id, timestamp DESC);
CREATE INDEX idx_usage_metrics_cpu_percent ON usage_metrics(cpu_percent);
CREATE INDEX idx_usage_metrics_ram_percent ON usage_metrics(ram_percent);

COMMENT ON TABLE usage_metrics IS 'Time-series storage for system performance metrics';

-- ============================================================================
-- TABLES: User Activity Tracking
-- ============================================================================

-- Table: users
-- Purpose: Store user information for session tracking
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(100) NOT NULL UNIQUE,
    full_name VARCHAR(255),
    email VARCHAR(255),
    role VARCHAR(50), -- student, faculty, admin
    department VARCHAR(100),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_role ON users(role);

-- Table: user_sessions
-- Purpose: Track user login sessions and activity
CREATE TABLE user_sessions (
    session_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(user_id),
    system_id UUID NOT NULL REFERENCES systems(system_id),
    username VARCHAR(100) NOT NULL, -- Denormalized for faster queries
    
    login_time TIMESTAMPTZ NOT NULL,
    logout_time TIMESTAMPTZ,
    session_duration_minutes INTEGER GENERATED ALWAYS AS 
        (EXTRACT(EPOCH FROM (logout_time - login_time)) / 60) STORED,
    
    -- Activity Summary
    active_processes JSONB, -- List of major processes used
    peak_cpu_usage NUMERIC(5,2),
    peak_ram_usage NUMERIC(5,2),
    total_disk_read_gb NUMERIC(10,2),
    total_disk_write_gb NUMERIC(10,2),
    
    session_type VARCHAR(50), -- interactive, batch, remote
    is_active BOOLEAN DEFAULT TRUE,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_user_sessions_user ON user_sessions(user_id);
CREATE INDEX idx_user_sessions_system ON user_sessions(system_id);
CREATE INDEX idx_user_sessions_login_time ON user_sessions(login_time DESC);
CREATE INDEX idx_user_sessions_active ON user_sessions(is_active) WHERE is_active = TRUE;

COMMENT ON TABLE user_sessions IS 'User login sessions with activity summaries';

-- ============================================================================
-- TABLES: Analytics & Aggregations
-- ============================================================================

-- Table: performance_summaries
-- Purpose: Pre-computed daily/hourly summaries for faster analytics
CREATE TABLE performance_summaries (
    summary_id BIGSERIAL PRIMARY KEY,
    system_id UUID NOT NULL REFERENCES systems(system_id),
    
    period_type VARCHAR(20) NOT NULL CHECK (period_type IN ('hourly', 'daily', 'weekly', 'monthly')),
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    
    -- CPU Statistics
    avg_cpu_percent NUMERIC(5,2),
    max_cpu_percent NUMERIC(5,2),
    min_cpu_percent NUMERIC(5,2),
    p95_cpu_percent NUMERIC(5,2), -- 95th percentile
    cpu_above_80_minutes INTEGER, -- Time spent above 80% usage
    
    -- RAM Statistics
    avg_ram_percent NUMERIC(5,2),
    max_ram_percent NUMERIC(5,2),
    p95_ram_percent NUMERIC(5,2),
    swap_used_minutes INTEGER, -- Time swap was active
    
    -- GPU Statistics (NULL if no GPU)
    avg_gpu_percent NUMERIC(5,2),
    max_gpu_percent NUMERIC(5,2),
    gpu_idle_minutes INTEGER,
    
    -- Disk I/O Statistics
    avg_disk_io_wait NUMERIC(5,2),
    total_disk_read_gb NUMERIC(12,2),
    total_disk_write_gb NUMERIC(12,2),
    
    -- System Health Indicators
    uptime_minutes INTEGER,
    anomaly_count INTEGER DEFAULT 0,
    utilization_score NUMERIC(5,2), -- Composite efficiency score (0-100)
    
    -- Flags
    is_underutilized BOOLEAN, -- avg_cpu < 30% AND avg_ram < 30%
    is_overutilized BOOLEAN, -- p95_cpu > 90% OR p95_ram > 90%
    has_bottleneck BOOLEAN,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(system_id, period_type, period_start)
);

CREATE INDEX idx_perf_summary_system_period ON performance_summaries(system_id, period_type, period_start DESC);
CREATE INDEX idx_perf_summary_underutilized ON performance_summaries(is_underutilized) WHERE is_underutilized = TRUE;
CREATE INDEX idx_perf_summary_overutilized ON performance_summaries(is_overutilized) WHERE is_overutilized = TRUE;

COMMENT ON TABLE performance_summaries IS 'Aggregated performance metrics by time period';

-- ============================================================================
-- TABLES: Optimization & Recommendations
-- ============================================================================

-- Table: optimization_reports
-- Purpose: Store generated optimization recommendations
CREATE TABLE optimization_reports (
    report_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    system_id UUID REFERENCES systems(system_id),
    
    report_type VARCHAR(50) NOT NULL, -- hardware_upgrade, reallocation, configuration
    severity VARCHAR(20) CHECK (severity IN ('low', 'medium', 'high', 'critical')),
    
    title VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Recommendations
    recommendations JSONB, -- Structured recommendations
    estimated_cost NUMERIC(10,2),
    priority_score INTEGER, -- 1-10
    
    -- Supporting Data
    analysis_period_start TIMESTAMPTZ,
    analysis_period_end TIMESTAMPTZ,
    supporting_metrics JSONB,
    
    -- Status Tracking
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'implemented', 'rejected', 'archived')),
    assigned_to VARCHAR(255),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP
);

CREATE INDEX idx_optimization_reports_system ON optimization_reports(system_id);
CREATE INDEX idx_optimization_reports_status ON optimization_reports(status);
CREATE INDEX idx_optimization_reports_severity ON optimization_reports(severity);
CREATE INDEX idx_optimization_reports_created ON optimization_reports(created_at DESC);

COMMENT ON TABLE optimization_reports IS 'Generated optimization recommendations for systems';

-- ============================================================================
-- TABLES: Alerts & Monitoring
-- ============================================================================

-- Table: alert_rules
-- Purpose: Define threshold-based alerting rules
CREATE TABLE alert_rules (
    rule_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    rule_name VARCHAR(255) NOT NULL UNIQUE,
    description TEXT,
    
    metric_name VARCHAR(100) NOT NULL, -- cpu_percent, ram_percent, etc.
    condition VARCHAR(20) NOT NULL CHECK (condition IN ('>', '<', '>=', '<=', '=')),
    threshold_value NUMERIC(10,2) NOT NULL,
    duration_minutes INTEGER DEFAULT 5, -- Sustained for how long
    
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('info', 'warning', 'critical')),
    
    is_enabled BOOLEAN DEFAULT TRUE,
    notify_email VARCHAR(255),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_alert_rules_enabled ON alert_rules(is_enabled) WHERE is_enabled = TRUE;

-- Table: alert_logs
-- Purpose: Log triggered alerts
CREATE TABLE alert_logs (
    alert_id BIGSERIAL PRIMARY KEY,
    rule_id UUID REFERENCES alert_rules(rule_id),
    system_id UUID REFERENCES systems(system_id),
    
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMPTZ,
    
    metric_name VARCHAR(100),
    actual_value NUMERIC(10,2),
    threshold_value NUMERIC(10,2),
    severity VARCHAR(20),
    
    message TEXT,
    is_acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_by VARCHAR(255),
    acknowledged_at TIMESTAMP,
    
    metadata JSONB -- Additional context
);

CREATE INDEX idx_alert_logs_system ON alert_logs(system_id);
CREATE INDEX idx_alert_logs_triggered ON alert_logs(triggered_at DESC);
CREATE INDEX idx_alert_logs_unresolved ON alert_logs(resolved_at) WHERE resolved_at IS NULL;

COMMENT ON TABLE alert_logs IS 'Log of triggered alerts and anomalies';

-- ============================================================================
-- TABLES: Process Tracking
-- ============================================================================

-- Table: process_snapshots
-- Purpose: Store periodic snapshots of running processes
CREATE TABLE process_snapshots (
    snapshot_id BIGSERIAL PRIMARY KEY,
    system_id UUID NOT NULL REFERENCES systems(system_id),
    timestamp TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    process_name VARCHAR(255),
    process_id INTEGER,
    user_name VARCHAR(100),
    
    cpu_percent NUMERIC(5,2),
    memory_mb NUMERIC(10,2),
    memory_percent NUMERIC(5,2),
    
    status VARCHAR(50), -- running, sleeping, zombie, etc.
    num_threads INTEGER,
    
    command_line TEXT
);

CREATE INDEX idx_process_snapshots_system_time ON process_snapshots(system_id, timestamp DESC);
CREATE INDEX idx_process_snapshots_cpu ON process_snapshots(cpu_percent DESC);

COMMENT ON TABLE process_snapshots IS 'Periodic snapshots of resource-intensive processes';

-- ============================================================================
-- VIEWS: Common Analytics
-- ============================================================================

-- View: current_system_status
-- Purpose: Real-time status of all systems with latest metrics
CREATE VIEW current_system_status AS
SELECT 
    s.system_id,
    s.hostname,
    s.location,
    s.status,
    s.cpu_cores,
    s.ram_total_gb,
    s.gpu_model,
    
    -- Latest metrics
    um.timestamp AS last_update,
    um.cpu_percent,
    um.ram_percent,
    um.gpu_utilization,
    um.disk_percent,
    um.load_avg_1min,
    
    -- Status flags
    CASE 
        WHEN um.cpu_percent > 90 OR um.ram_percent > 90 THEN 'overloaded'
        WHEN um.cpu_percent < 20 AND um.ram_percent < 20 THEN 'underutilized'
        ELSE 'normal'
    END AS utilization_status,
    
    -- Time since last seen
    EXTRACT(EPOCH FROM (NOW() - s.last_seen))/60 AS minutes_since_seen
    
FROM systems s
LEFT JOIN LATERAL (
    SELECT * FROM usage_metrics um2
    WHERE um2.system_id = s.system_id
    ORDER BY um2.timestamp DESC
    LIMIT 1
) um ON TRUE
WHERE s.status = 'active';

COMMENT ON VIEW current_system_status IS 'Current status and latest metrics for all active systems';

-- View: system_utilization_rankings
-- Purpose: Rank systems by utilization for optimization
CREATE VIEW system_utilization_rankings AS
SELECT 
    s.hostname,
    s.location,
    ps.avg_cpu_percent,
    ps.avg_ram_percent,
    ps.avg_gpu_percent,
    ps.utilization_score,
    ps.is_underutilized,
    ps.is_overutilized,
    
    RANK() OVER (ORDER BY ps.utilization_score DESC) as efficiency_rank
    
FROM systems s
JOIN performance_summaries ps ON s.system_id = ps.system_id
WHERE ps.period_type = 'daily'
    AND ps.period_start >= CURRENT_DATE - INTERVAL '7 days';

-- ============================================================================
-- FUNCTIONS: Utility & Helpers
-- ============================================================================

-- Function: update_updated_at_column
-- Purpose: Automatically update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to relevant tables
CREATE TRIGGER update_systems_updated_at
    BEFORE UPDATE ON systems
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_optimization_reports_updated_at
    BEFORE UPDATE ON optimization_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_alert_rules_updated_at
    BEFORE UPDATE ON alert_rules
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- ============================================================================
-- Initial Data / Sample Records
-- ============================================================================

-- Insert sample alert rules
INSERT INTO alert_rules (rule_name, description, metric_name, condition, threshold_value, duration_minutes, severity, is_enabled)
VALUES
    ('High CPU Usage', 'Alert when CPU usage exceeds 95% for 10 minutes', 'cpu_percent', '>', 95, 10, 'critical', TRUE),
    ('High RAM Usage', 'Alert when RAM usage exceeds 90% for 5 minutes', 'ram_percent', '>', 90, 5, 'warning', TRUE),
    ('High Disk I/O Wait', 'Alert when disk I/O wait exceeds 50%', 'disk_io_wait_percent', '>', 50, 5, 'warning', TRUE),
    ('Low Disk Space', 'Alert when disk usage exceeds 85%', 'disk_percent', '>', 85, 1, 'warning', TRUE),
    ('GPU Overheating', 'Alert when GPU temperature exceeds 85°C', 'gpu_temp', '>', 85, 5, 'critical', TRUE);

-- ============================================================================
-- GRANTS & PERMISSIONS (Adjust as needed)
-- ============================================================================

-- Example: Create read-only role for dashboard access
-- CREATE ROLE dashboard_readonly;
-- GRANT CONNECT ON DATABASE lab_resource_monitor TO dashboard_readonly;
-- GRANT USAGE ON SCHEMA public TO dashboard_readonly;
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO dashboard_readonly;

-- Example: Create write role for data collectors
-- CREATE ROLE data_collector;
-- GRANT INSERT ON usage_metrics, user_sessions, process_snapshots TO data_collector;
-- GRANT SELECT ON systems TO data_collector;

-- ============================================================================
-- END OF SCHEMA
-- ============================================================================

-- Verify schema creation
SELECT 
    table_name, 
    (SELECT COUNT(*) FROM information_schema.columns WHERE table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE'
ORDER BY table_name;
