

-- ============================================================================
-- DROP EXISTING TABLES (for clean schema updates)
-- ============================================================================
-- Uncomment the following lines if you want to drop all tables before recreating
-- WARNING: This will delete all data! Use only for development/schema updates.


-- Drop views first (due to dependencies)
DROP VIEW IF EXISTS v_systems_overview CASCADE;
DROP VIEW IF EXISTS v_latest_metrics CASCADE;
DROP VIEW IF EXISTS v_department_stats CASCADE;
DROP VIEW IF EXISTS v_daily_resource_trends CASCADE;
DROP VIEW IF EXISTS v_weekly_resource_trends CASCADE;

-- Drop continuous aggregates (TimescaleDB)
DROP MATERIALIZED VIEW IF EXISTS hourly_performance_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS daily_performance_stats CASCADE;

-- Drop triggers
DROP TRIGGER IF EXISTS trg_departments_updated_at ON departments;
DROP TRIGGER IF EXISTS trg_systems_updated_at ON systems;

-- Drop functions
DROP FUNCTION IF EXISTS update_updated_at() CASCADE;
DROP FUNCTION IF EXISTS get_systems_in_subnet(TEXT) CASCADE;
DROP FUNCTION IF EXISTS count_active_systems_by_dept() CASCADE;

-- Drop tables (in reverse dependency order)
DROP TABLE IF EXISTS system_baselines CASCADE;
DROP TABLE IF EXISTS performance_summaries CASCADE;
DROP TABLE IF EXISTS maintainence_logs CASCADE;
DROP TABLE IF EXISTS metrics CASCADE;
DROP TABLE IF EXISTS systems CASCADE;
DROP TABLE IF EXISTS collection_credentials CASCADE;
DROP TABLE IF EXISTS network_scans CASCADE;
DROP TABLE IF EXISTS lab_assistants CASCADE;
DROP TABLE IF EXISTS labs CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS hods CASCADE;

-- Drop extensions (if needed)
-- DROP EXTENSION IF EXISTS pgcrypto CASCADE;
-- DROP EXTENSION IF EXISTS timescaledb CASCADE;


-- ============================================================================
-- SCHEMA CREATION
-- ============================================================================

-- HODs
CREATE TABLE IF NOT EXISTS hods (
    hod_id SERIAL PRIMARY KEY,
    hod_name VARCHAR(200) NOT NULL,
    hod_email VARCHAR(220) UNIQUE
);
COMMENT ON TABLE hods IS 'HODs information of RVCE';

-- Departments
CREATE TABLE IF NOT EXISTS departments (
    dept_id SERIAL PRIMARY KEY,
    dept_name VARCHAR(100) NOT NULL UNIQUE,
    dept_code VARCHAR(20),                     -- 'ISE', 'CSE', 'ECE'
    vlan_id VARCHAR(20),                       -- VLAN ID
    subnet_cidr CIDR,                          -- '10.30.0.0/16'
    description TEXT,
    hod_id INT REFERENCES hods(hod_id) ON DELETE SET NULL
);
COMMENT ON TABLE departments IS 'Academic departments and their network configuration';

-- Labs
CREATE TABLE IF NOT EXISTS labs (
    lab_id SERIAL PRIMARY KEY,
    lab_dept INT REFERENCES departments(dept_id) ON DELETE CASCADE,
    lab_number INT,
    assistant_ids INT[]
);
COMMENT ON TABLE labs IS 'Labs of RVCE';

-- Lab Assistants
CREATE TABLE IF NOT EXISTS lab_assistants (
    lab_assistant_id SERIAL PRIMARY KEY,
    lab_assistant_name VARCHAR(200) NOT NULL,
    lab_assistant_email VARCHAR(250) UNIQUE,
    lab_assistant_dept INT REFERENCES departments(dept_id) ON DELETE SET NULL,
    lab_assigned INT REFERENCES labs(lab_id) ON DELETE SET NULL
);
COMMENT ON TABLE lab_assistants IS 'Lab Assistants of RVCE';

-- NETWORK SCANS (Discovery History)
CREATE TABLE IF NOT EXISTS network_scans (
    scan_id SERIAL PRIMARY KEY,
    dept_id INT REFERENCES departments(dept_id) ON DELETE CASCADE,
    scan_type VARCHAR(50) NOT NULL,            -- 'nmap', 'arp', 'manual'
    target_range VARCHAR(100) NOT NULL,        -- we specify the range of IPs of a particular lab
    scan_start TIMESTAMPTZ NOT NULL,
    scan_end TIMESTAMPTZ,
    duration_seconds INT GENERATED ALWAYS AS 
        (EXTRACT(EPOCH FROM (scan_end - scan_start))::INT) STORED,
    systems_found INT DEFAULT 0,
    -- systems_new INT DEFAULT 0,
    status VARCHAR(20) DEFAULT 'running',      -- 'running', 'completed', 'failed'
    error_message TEXT,
    scan_parameters JSONB,                     -- Additional scan options
    created_at TIMESTAMPTZ DEFAULT NOW()
);
COMMENT ON TABLE network_scans IS 'History of network discovery scans';

CREATE INDEX idx_network_scans_dept ON network_scans(dept_id);
CREATE INDEX idx_network_scans_status ON network_scans(status);
CREATE INDEX idx_network_scans_start ON network_scans(scan_start DESC);

-- COLLECTION CREDENTIALS (Secure Vault)
-- Enable encryption extension
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS collection_credentials (
    credential_id SERIAL PRIMARY KEY,
    credential_name VARCHAR(100) NOT NULL UNIQUE,
    credential_type VARCHAR(50) NOT NULL,      -- 'ssh', 'wmi', 'snmp'
    username VARCHAR(255),
    password_encrypted BYTEA,                  -- Encrypted password
    ssh_key_path TEXT,
    snmp_community VARCHAR(100),
    additional_config JSONB,                   -- Extra parameters
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    last_used TIMESTAMPTZ,
    used_count INT DEFAULT 0
);

COMMENT ON TABLE collection_credentials IS 'Encrypted credentials for remote system access';

-- Helper functions for encryption/decryption
-- Usage: pgp_sym_encrypt('password', 'master_key')
-- Usage: pgp_sym_decrypt(password_encrypted, 'master_key')

-- 4. SYSTEMS (Enhanced with Network Info)
CREATE TABLE IF NOT EXISTS systems (
    system_id SERIAL PRIMARY KEY,
    system_number INT,
    lab_id INT REFERENCES labs(lab_id) ON DELETE SET NULL,
    dept_id INT REFERENCES departments(dept_id) ON DELETE SET NULL,
    
    -- Network Identification
    hostname VARCHAR(255) NOT NULL,
    ip_address INET NOT NULL UNIQUE,           
    mac_address MACADDR,                       
    
    -- System Information
    -- os_type VARCHAR(50),                       
    -- os_version VARCHAR(200),
    -- os_architecture VARCHAR(20),      
    
    -- Hardware Specs (discovered or collected)
    cpu_model VARCHAR(255),
    cpu_cores INT,
    ram_total_gb NUMERIC(10,2),
    disk_total_gb NUMERIC(10,2),
    gpu_model VARCHAR(255),
    gpu_memory NUMERIC(10,2),
    
    -- Collection Configuration
    -- credential_id INT REFERENCES collection_credentials(credential_id),
    snmp_enabled BOOLEAN DEFAULT FALSE,
    ssh_port INT DEFAULT 22,
    -- collection_method VARCHAR(50),             -- 'wmi', 'ssh', 'snmp', 'agent', 'none'
    
    -- Status & Timestamps
    status VARCHAR(20) DEFAULT 'discovered',   -- 'discovered', 'active', 'offline', 'maintenance'
    notes TEXT,

    -- first_seen TIMESTAMPTZ DEFAULT NOW(),/
    -- last_seen TIMESTAMPTZ,
    -- last_scan_id INT REFERENCES network_scans(scan_id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
    
    -- Metadata
    -- tags TEXT[],                               -- Array of tags: ['lab-pc', 'faculty', 'gaming']
    -- wmi_enabled BOOLEAN DEFAULT FALSE,
);
COMMENT ON TABLE systems IS 'Discovered and monitored computer systems';

-- Indexes for performance
CREATE INDEX idx_systems_dept ON systems(dept_id);
CREATE INDEX idx_systems_ip ON systems USING gist(ip_address inet_ops);
CREATE INDEX idx_systems_mac ON systems(mac_address);
CREATE INDEX idx_systems_hostname ON systems(hostname);
CREATE INDEX idx_systems_status ON systems(status);


-- 5. USAGE METRICS (Time-Series Data)
CREATE TABLE IF NOT EXISTS metrics (
    metric_id BIGSERIAL,
    system_id INT NOT NULL REFERENCES systems(system_id) ON DELETE CASCADE,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- CPU Metrics
    cpu_percent NUMERIC(5,2) CHECK (cpu_percent >= 0 AND cpu_percent <= 100),
    cpu_temperature NUMERIC(5,2),
    -- cpu_per_core NUMERIC(5,2)[],              -- Array of per-core usage
    
    -- Memory Metrics
    ram_percent NUMERIC(5,2) CHECK (ram_percent >= 0 AND ram_percent <= 100),
    
    -- Disk Metrics
    disk_percent NUMERIC(5,2) CHECK (disk_percent >= 0 AND disk_percent <= 100),
    disk_read_mbps NUMERIC(10,2),
    disk_write_mbps NUMERIC(10,2),
    
    -- Network Metrics
    network_sent_mbps NUMERIC(10,2),
    network_recv_mbps NUMERIC(10,2),
    
    -- GPU Metrics (if available)
    gpu_percent NUMERIC(5,2),
    gpu_memory_used_gb NUMERIC(10,2),
    gpu_temperature NUMERIC(5,2),
    
    -- System Metrics
    uptime_seconds BIGINT,
    logged_in_users INT,
    
    -- Collection Metadata
    -- collection_method VARCHAR(50),
    -- collection_duration_ms INT,
    
    PRIMARY KEY (system_id, timestamp)
);

COMMENT ON TABLE metrics IS 'Time-series resource utilization metrics';

-- Indexes for time-series queries
CREATE INDEX idx_metrics_timestamp ON metrics(timestamp DESC);
CREATE INDEX idx_metrics_system_time ON metrics(system_id, timestamp DESC);


-- -- 6. COLLECTION JOBS (Scheduled Tasks)
-- CREATE TABLE IF NOT EXISTS collection_jobs (
--     job_id SERIAL PRIMARY KEY,
--     job_name VARCHAR(200) NOT NULL UNIQUE,
--     job_type VARCHAR(50) NOT NULL,            -- 'discovery', 'metrics_collection'
--     dept_id INT REFERENCES departments(dept_id) ON DELETE CASCADE,
    
--     -- Schedule Configuration
--     schedule_cron VARCHAR(100),                -- '*/5 * * * *' (every 5 min)
--     schedule_description TEXT,
--     enabled BOOLEAN DEFAULT TRUE,
    
--     -- Execution Tracking
--     last_run_start TIMESTAMPTZ,
--     last_run_end TIMESTAMPTZ,
--     last_run_status VARCHAR(20),               -- 'success', 'failed', 'partial'
--     last_run_message TEXT,
--     next_run TIMESTAMPTZ,
    
--     -- Statistics
--     total_runs INT DEFAULT 0,
--     successful_runs INT DEFAULT 0,
--     failed_runs INT DEFAULT 0,
--     avg_duration_seconds NUMERIC(10,2),
    
--     -- Configuration
--     job_config JSONB,                          -- Job-specific parameters
    
--     created_at TIMESTAMPTZ DEFAULT NOW(),
--     updated_at TIMESTAMPTZ DEFAULT NOW()
-- );

-- COMMENT ON TABLE collection_jobs IS 'Automated discovery and collection job schedules';

-- CREATE INDEX idx_collection_jobs_dept ON collection_jobs(dept_id);
-- CREATE INDEX idx_collection_jobs_enabled ON collection_jobs(enabled) WHERE enabled = TRUE;
-- CREATE INDEX idx_collection_jobs_next_run ON collection_jobs(next_run);

-- -- 7. COLLECTION LOGS (Audit Trail)
-- CREATE TABLE IF NOT EXISTS collection_logs (
--     log_id BIGSERIAL PRIMARY KEY,
--     log_timestamp TIMESTAMPTZ DEFAULT NOW(),
--     job_id INT REFERENCES collection_jobs(job_id) ON DELETE SET NULL,
--     system_id INT REFERENCES systems(system_id) ON DELETE CASCADE,
    
--     -- Log Details
--     log_level VARCHAR(20),                     -- 'INFO', 'WARNING', 'ERROR'
--     log_message TEXT NOT NULL,
--     collection_method VARCHAR(50),
    
--     -- Error Details
--     error_code VARCHAR(50),
--     error_details JSONB,
    
--     -- Performance
--     response_time_ms INT,
    
--     created_at TIMESTAMPTZ DEFAULT NOW()
-- );

-- COMMENT ON TABLE collection_logs IS 'Audit log for all collection activities';

-- CREATE INDEX idx_collection_logs_timestamp ON collection_logs(log_timestamp DESC);
-- CREATE INDEX idx_collection_logs_system ON collection_logs(system_id);
-- CREATE INDEX idx_collection_logs_level ON collection_logs(log_level);


-- -- 8. ALERT RULES & LOGS
-- -- Alert Rules Table
-- CREATE TABLE IF NOT EXISTS alert_rules (
--     rule_id SERIAL PRIMARY KEY,
--     rule_name VARCHAR(200) NOT NULL UNIQUE,
--     metric_name VARCHAR(100) NOT NULL,        -- 'cpu_percent', 'ram_percent', 'disk_percent', etc.
--     condition VARCHAR(10) NOT NULL,            -- '>', '<', '>=', '<=', '='
--     threshold_value NUMERIC(10,2) NOT NULL,
--     duration_minutes INT DEFAULT 5,            -- Alert if condition met for N minutes
--     severity VARCHAR(20) DEFAULT 'warning',    -- 'info', 'warning', 'critical'
--     is_enabled BOOLEAN DEFAULT TRUE,
--     description TEXT,
--     created_at TIMESTAMPTZ DEFAULT NOW(),
--     updated_at TIMESTAMPTZ DEFAULT NOW()
-- );

-- COMMENT ON TABLE alert_rules IS 'Alert threshold rules for system metrics';

-- CREATE INDEX idx_alert_rules_enabled ON alert_rules(is_enabled) WHERE is_enabled = TRUE;
-- CREATE INDEX idx_alert_rules_metric ON alert_rules(metric_name);

-- Alert Logs Table
CREATE TABLE IF NOT EXISTS maintainence_logs (
    maintainence_id BIGSERIAL PRIMARY KEY,
    system_id INT REFERENCES systems(system_id) ON DELETE CASCADE,
    date_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_acknowledged BOOLEAN DEFAULT FALSE,
    acknowledged_at TIMESTAMPTZ,
    acknowledged_by VARCHAR(100),
    resolved_at TIMESTAMPTZ,
    severity VARCHAR(20) NOT NULL,
    message TEXT NOT NULL
);
COMMENT ON TABLE alert_logs IS 'Maintainence Logs';

CREATE INDEX idx_alert_logs_system ON maintainence_logs(system_id);
CREATE INDEX idx_alert_logs_triggered ON maintainence_logs(date_at DESC);
CREATE INDEX idx_alert_logs_severity ON maintainence_logs(severity);
CREATE INDEX idx_alert_logs_unresolved ON maintainence_logs(resolved_at) WHERE resolved_at IS NULL;

-- -- Department-level Alert Rules
-- CREATE TABLE IF NOT EXISTS department_alert_rules (
--     rule_id SERIAL PRIMARY KEY,
--     dept_id INT REFERENCES departments(dept_id) ON DELETE CASCADE,
--     rule_name VARCHAR(200) NOT NULL,
--     rule_type VARCHAR(50),                     -- 'cpu', 'ram', 'disk', 'offline_systems'
--     threshold_value NUMERIC(10,2),
--     threshold_operator VARCHAR(10),            -- '>', '<', '>=', '<=', '='
--     affected_systems_threshold INT,            -- Alert if N systems affected
--     enabled BOOLEAN DEFAULT TRUE,
--     severity VARCHAR(20) DEFAULT 'warning',
--     notification_channels JSONB,               -- ['email', 'slack', 'sms']
--     created_at TIMESTAMPTZ DEFAULT NOW()
-- );

-- COMMENT ON TABLE department_alert_rules IS 'Alert rules that apply to entire departments';

-- ============================================================================
-- 9. PERFORMANCE SUMMARIES
-- ============================================================================

CREATE TABLE IF NOT EXISTS performance_summaries (
    summary_id BIGSERIAL PRIMARY KEY,
    system_id INT NOT NULL REFERENCES systems(system_id) ON DELETE CASCADE,
    period_type VARCHAR(20) NOT NULL,          -- 'hourly', 'daily', 'weekly', 'monthly'
    period_start TIMESTAMPTZ NOT NULL,
    period_end TIMESTAMPTZ NOT NULL,
    
    -- CPU Statistics
    avg_cpu_percent NUMERIC(5,2),
    max_cpu_percent NUMERIC(5,2),
    min_cpu_percent NUMERIC(5,2),
    stddev_cpu_percent NUMERIC(5,2),           -- Added for CFRS variance component
    
    -- RAM Statistics
    avg_ram_percent NUMERIC(5,2),
    max_ram_percent NUMERIC(5,2),
    min_ram_percent NUMERIC(5,2),
    stddev_ram_percent NUMERIC(5,2),           -- Added for CFRS variance component
    
    -- GPU Statistics
    avg_gpu_percent NUMERIC(5,2),
    max_gpu_percent NUMERIC(5,2),
    min_gpu_percent NUMERIC(5,2),
    stddev_gpu_percent NUMERIC(5,2),           -- Added for CFRS variance component
    
    -- Disk Statistics
    avg_disk_percent NUMERIC(5,2),
    max_disk_percent NUMERIC(5,2),
    min_disk_percent NUMERIC(5,2),
    stddev_disk_percent NUMERIC(5,2),          -- Added for CFRS variance component
    
    -- System Statistics
    uptime_minutes INT,
    
    -- Metadata
    anomaly_count INT DEFAULT 0,
    metric_count INT,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(system_id, period_type, period_start)
);

COMMENT ON TABLE performance_summaries IS 'Aggregated performance statistics by time period. Includes variance metrics for CFRS computation. No hardcoded thresholds.';

CREATE INDEX idx_perf_summary_system_period ON performance_summaries(system_id, period_start DESC);
CREATE INDEX idx_perf_summary_period_type ON performance_summaries(period_type, period_start DESC);

-- ============================================================================
-- 10. SYSTEM BASELINES (CFRS Support)
-- ============================================================================

-- Table to store statistical baselines for CFRS deviation component
-- Stores mean/stddev for z-score computation outside the database
CREATE TABLE IF NOT EXISTS system_baselines (
    baseline_id SERIAL PRIMARY KEY,
    system_id INT NOT NULL REFERENCES systems(system_id) ON DELETE CASCADE,
    metric_name VARCHAR(50) NOT NULL,          -- 'cpu_percent', 'ram_percent', 'gpu_percent', 'disk_percent'
    
    -- Baseline Statistics
    baseline_mean NUMERIC(10,4) NOT NULL,
    baseline_stddev NUMERIC(10,4) NOT NULL,
    baseline_median NUMERIC(10,4),
    baseline_p95 NUMERIC(10,4),
    
    -- Baseline Computation Context
    baseline_start TIMESTAMPTZ NOT NULL,
    baseline_end TIMESTAMPTZ NOT NULL,
    sample_count INT NOT NULL,
    
    -- Metadata
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,            -- Allow multiple baseline versions
    
    UNIQUE(system_id, metric_name, baseline_start, baseline_end)
);

COMMENT ON TABLE system_baselines IS 'Statistical baselines for CFRS deviation component. Stores mean/stddev for z-score computation. Does NOT compute CFRS internally.';

CREATE INDEX idx_baselines_system_metric ON system_baselines(system_id, metric_name, is_active);
CREATE INDEX idx_baselines_computed ON system_baselines(computed_at DESC);

-- ============================================================================
-- 11. OPTIMIZATION REPORTS
-- ============================================================================

-- CREATE TABLE IF NOT EXISTS optimization_reports (
--     report_id SERIAL PRIMARY KEY,
--     system_id INT REFERENCES systems(system_id) ON DELETE CASCADE,
--     report_type VARCHAR(50) NOT NULL,          -- 'automated_analysis', 'manual_review', 'capacity_planning'
--     severity VARCHAR(20),                      -- 'low', 'medium', 'high', 'critical'
--     title VARCHAR(255) NOT NULL,
--     description TEXT,
--     recommendations JSONB,                     -- Array of recommendation objects
--     priority_score INT,
--     analysis_period_start TIMESTAMPTZ,
--     analysis_period_end TIMESTAMPTZ,
--     status VARCHAR(20) DEFAULT 'pending',      -- 'pending', 'approved', 'implemented', 'rejected'
--     created_at TIMESTAMPTZ DEFAULT NOW(),
--     reviewed_at TIMESTAMPTZ,
--     reviewed_by VARCHAR(100),
--     implementation_notes TEXT
-- );

-- COMMENT ON TABLE optimization_reports IS 'Hardware optimization and upgrade recommendations';

-- CREATE INDEX idx_optimization_reports_system ON optimization_reports(system_id);
-- CREATE INDEX idx_optimization_reports_status ON optimization_reports(status);
-- CREATE INDEX idx_optimization_reports_severity ON optimization_reports(severity, priority_score DESC);

-- VIEWS FOR EASY QUERYING

-- Views for easy querying
-- View: Systems with department info
CREATE OR REPLACE VIEW v_systems_overview AS
SELECT
    s.system_id,
    s.hostname,
    s.ip_address::TEXT,
    s.mac_address::TEXT,
    d.dept_name,
    d.dept_code,
    s.status
FROM systems s
LEFT JOIN departments d USING(dept_id);

-- View: Latest metrics per system
CREATE OR REPLACE VIEW v_latest_metrics AS
SELECT DISTINCT ON (system_id)
    system_id,
    timestamp,
    cpu_percent,
    ram_percent,
    disk_percent,
    logged_in_users
FROM metrics
ORDER BY system_id, timestamp DESC;

-- View: Department statistics
CREATE OR REPLACE VIEW v_department_stats AS
SELECT
    d.dept_name,
    COUNT(s.system_id) AS total_systems,
    COUNT(s.system_id) FILTER (WHERE s.status = 'active') AS active_systems,
    COUNT(s.system_id) FILTER (WHERE s.status = 'offline') AS offline_systems
FROM departments d
LEFT JOIN systems s USING(dept_id)
GROUP BY d.dept_id, d.dept_name;

-- View: Systems with dynamic status based on last metric timestamp
CREATE OR REPLACE VIEW v_systems_with_status AS
SELECT 
    s.*,
    m.last_metric_time,
    CASE 
        WHEN m.last_metric_time IS NULL THEN 'unknown'
        WHEN m.last_metric_time < NOW() - INTERVAL '10 minutes' THEN 'offline'
        ELSE 'active'
    END as computed_status
FROM systems s
LEFT JOIN (
    SELECT system_id, MAX(timestamp) as last_metric_time
    FROM metrics
    GROUP BY system_id
) m ON s.system_id = m.system_id;

COMMENT ON VIEW v_systems_with_status IS 'Systems with dynamically computed status based on last metrics timestamp. A system is considered offline if no metrics received in last 10 minutes.';

-- ============================================================================
-- CFRS SUPPORT VIEWS
-- ============================================================================

-- View: Daily resource trends for CFRS trend component
-- Suitable for linear regression / slope analysis to detect long-term degradation
CREATE OR REPLACE VIEW v_daily_resource_trends AS
SELECT
    system_id,
    day_bucket::DATE as date,
    day_bucket,
    
    -- CPU Trend Data
    avg_cpu_percent,
    stddev_cpu_percent,
    max_cpu_percent,
    
    -- RAM Trend Data
    avg_ram_percent,
    stddev_ram_percent,
    max_ram_percent,
    
    -- GPU Trend Data
    avg_gpu_percent,
    stddev_gpu_percent,
    max_gpu_percent,
    
    -- Disk Trend Data
    avg_disk_percent,
    stddev_disk_percent,
    max_disk_percent,
    
    -- Sample Quality
    metric_count
FROM daily_performance_stats
ORDER BY system_id, day_bucket;

COMMENT ON VIEW v_daily_resource_trends IS 'Daily resource utilization for trend analysis. Suitable for linear regression to compute degradation slopes. Part of CFRS trend component input.';

-- View: Weekly rolling statistics for CFRS trend component
-- Provides sliding window context for multi-day pattern analysis
CREATE OR REPLACE VIEW v_weekly_resource_trends AS
SELECT
    system_id,
    time_bucket('7 days', day_bucket) AS week_bucket,
    
    -- CPU Weekly Aggregates
    AVG(avg_cpu_percent) AS avg_cpu_weekly,
    STDDEV(avg_cpu_percent) AS stddev_cpu_weekly,
    MAX(max_cpu_percent) AS peak_cpu_weekly,
    
    -- RAM Weekly Aggregates
    AVG(avg_ram_percent) AS avg_ram_weekly,
    STDDEV(avg_ram_percent) AS stddev_ram_weekly,
    MAX(max_ram_percent) AS peak_ram_weekly,
    
    -- GPU Weekly Aggregates
    AVG(avg_gpu_percent) AS avg_gpu_weekly,
    STDDEV(avg_gpu_percent) AS stddev_gpu_weekly,
    MAX(max_gpu_percent) AS peak_gpu_weekly,
    
    -- Disk Weekly Aggregates
    AVG(avg_disk_percent) AS avg_disk_weekly,
    STDDEV(avg_disk_percent) AS stddev_disk_weekly,
    MAX(max_disk_percent) AS peak_disk_weekly,
    
    -- Sample Quality
    SUM(metric_count) AS total_samples
FROM daily_performance_stats
GROUP BY system_id, week_bucket
ORDER BY system_id, week_bucket;

COMMENT ON VIEW v_weekly_resource_trends IS 'Weekly aggregated trends for multi-day pattern analysis. Supports CFRS trend component with longer time windows.';

-- ============================================================================
-- TRIGGERS & FUNCTIONS
-- ============================================================================

-- Update timestamp trigger function
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply to tables with updated_at
CREATE TRIGGER trg_departments_updated_at
    BEFORE UPDATE ON departments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_systems_updated_at
    BEFORE UPDATE ON systems
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Function to update system status based on last metrics
CREATE OR REPLACE FUNCTION update_system_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update status if not in maintenance
    IF (SELECT status FROM systems WHERE system_id = NEW.system_id) != 'maintenance' THEN
        UPDATE systems 
        SET status = 'active', updated_at = NOW()
        WHERE system_id = NEW.system_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to mark system as active when metrics are inserted
CREATE TRIGGER trg_metrics_update_status
    AFTER INSERT ON metrics
    FOR EACH ROW
    EXECUTE FUNCTION update_system_status();

COMMENT ON FUNCTION update_system_status() IS 'Automatically updates system status to active when metrics are received, unless system is in maintenance mode';

-- Function to mark systems as offline if no metrics in last 10 minutes
-- This should be called periodically (e.g., via cron job or pg_cron)
CREATE OR REPLACE FUNCTION mark_systems_offline()
RETURNS TABLE(system_id INT, hostname VARCHAR, old_status VARCHAR, new_status VARCHAR) AS $$
BEGIN
    RETURN QUERY
    UPDATE systems s
    SET status = 'offline', updated_at = NOW()
    FROM (
        SELECT sys.system_id, sys.hostname, sys.status as old_status
        FROM systems sys
        LEFT JOIN (
            SELECT m.system_id, MAX(m.timestamp) as last_metric_time
            FROM metrics m
            GROUP BY m.system_id
        ) recent_metrics ON sys.system_id = recent_metrics.system_id
        WHERE sys.status NOT IN ('maintenance')
        AND (
            recent_metrics.last_metric_time IS NULL 
            OR recent_metrics.last_metric_time < NOW() - INTERVAL '10 minutes'
        )
        AND sys.status != 'offline'
    ) offline_systems
    WHERE s.system_id = offline_systems.system_id
    RETURNING s.system_id, s.hostname, offline_systems.old_status, s.status as new_status;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION mark_systems_offline() IS 'Marks systems as offline if no metrics received in last 10 minutes. Should be run periodically (every 5-10 minutes). Does not affect systems in maintenance mode.';

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Function: Get systems in a subnet
CREATE OR REPLACE FUNCTION get_systems_in_subnet(subnet_cidr TEXT)
RETURNS TABLE (
    system_id INT,
    hostname VARCHAR,
    ip_address TEXT,
    status VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.system_id,
        s.hostname,
        s.ip_address::TEXT,
        s.status
    FROM systems s
    WHERE s.ip_address <<= subnet_cidr::INET
    ORDER BY s.ip_address;
END;
$$ LANGUAGE plpgsql;

-- Function: Count active systems by department
CREATE OR REPLACE FUNCTION count_active_systems_by_dept()
RETURNS TABLE (
    dept_name VARCHAR,
    active_count BIGINT,
    total_count BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        d.dept_name,
        COUNT(s.system_id) FILTER (WHERE s.status = 'active'),
        COUNT(s.system_id)
    FROM departments d
    LEFT JOIN systems s USING(dept_id)
    GROUP BY d.dept_name
    ORDER BY d.dept_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION detect_sustained_cpu_overload()
RETURNS TRIGGER AS $$
DECLARE
    high_cpu_minutes INT;
BEGIN
    SELECT COUNT(*) INTO high_cpu_minutes
    FROM metrics
    WHERE system_id = NEW.system_id
      AND cpu_percent > 85
      AND timestamp >= NOW() - INTERVAL '5 minutes';

    IF high_cpu_minutes >= 5 THEN
        INSERT INTO maintainence_logs (
            system_id,
            severity,
            message
        )
        VALUES (
            NEW.system_id,
            'critical',
            'Sustained CPU usage above 85% for over 5 minutes'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cpu_overload
AFTER INSERT ON metrics
FOR EACH ROW
EXECUTE FUNCTION detect_sustained_cpu_overload();


CREATE OR REPLACE FUNCTION detect_disk_io_anomaly()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.disk_write_mbps > 500 THEN
        INSERT INTO maintainence_logs (
            system_id,
            severity,
            message
        )
        VALUES (
            NEW.system_id,
            'warning',
            'Abnormally high disk write throughput detected'
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


INSERT INTO maintainence_logs (system_id, severity, message)
SELECT
    s.system_id,
    'critical',
    'System has stopped reporting metrics for over 10 minutes'
FROM systems s
LEFT JOIN metrics m
  ON s.system_id = m.system_id
  AND m.timestamp >= NOW() - INTERVAL '10 minutes'
WHERE s.status = 'active'
  AND m.metric_id IS NULL;



-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

-- In production, create specific roles:
-- CREATE ROLE lab_monitor_collector WITH LOGIN PASSWORD 'secure_password';
-- GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO lab_monitor_collector;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO lab_monitor_collector;

-- ============================================================================
-- COMPLETED
-- ============================================================================




COMMENT ON SCHEMA public IS 'Agentless Lab Resource Monitoring Database - Network Discovery Based';

SELECT 'Schema created successfully!' AS status;
