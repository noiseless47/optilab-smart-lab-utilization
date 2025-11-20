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
    swap_total_gb NUMERIC(10,2)
    disk_total_gb NUMERIC(10,2),
    gpu_model VARCHAR(255),
    gpu_memory NUMERIC(10,2),
    
    -- Collection Configuration
    credential_id INT REFERENCES collection_credentials(credential_id),
    snmp_enabled BOOLEAN DEFAULT FALSE,
    ssh_port INT DEFAULT 22,
    -- collection_method VARCHAR(50),             -- 'wmi', 'ssh', 'snmp', 'agent', 'none'
    
    -- Status & Timestamps
    status VARCHAR(20) DEFAULT 'discovered',   -- 'discovered', 'active', 'offline', 'maintenance'
    notes TEXT,

    first_seen TIMESTAMPTZ DEFAULT NOW(),
    last_seen TIMESTAMPTZ,
    last_scan_id INT REFERENCES network_scans(scan_id),
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
CREATE INDEX idx_systems_last_seen ON systems(last_seen DESC);
CREATE INDEX idx_systems_tags ON systems USING gin(tags);


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
    swap_percent NUMERIC(5,2) CHECK (swap_percent >= 0 AND swap_percent <= 100),
    
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
    collection_method VARCHAR(50),
    collection_duration_ms INT,
    
    PRIMARY KEY (system_id, timestamp)
);

COMMENT ON TABLE usage_metrics IS 'Time-series resource utilization metrics';

-- Indexes for time-series queries
CREATE INDEX idx_usage_metrics_timestamp ON usage_metrics(timestamp DESC);
CREATE INDEX idx_usage_metrics_system_time ON usage_metrics(system_id, timestamp DESC);


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
    resolved_at TIMESTAMPTZ,\
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
    cpu_above_80_minutes INT,
    
    -- RAM Statistics
    avg_ram_percent NUMERIC(5,2),
    max_ram_percent NUMERIC(5,2),
    swap_used_minutes INT,
    
    -- GPU Statistics
    avg_gpu_percent NUMERIC(5,2),
    max_gpu_percent NUMERIC(5,2),
    
    -- Disk Statistics
    avg_disk_io_wait NUMERIC(5,2),
    total_disk_read_gb NUMERIC(12,2),
    total_disk_write_gb NUMERIC(12,2),
    
    -- System Statistics
    uptime_minutes INT,
    utilization_score NUMERIC(5,2),
    
    -- Flags
    is_underutilized BOOLEAN DEFAULT FALSE,
    is_overutilized BOOLEAN DEFAULT FALSE,
    anomaly_count INT DEFAULT 0,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    
    UNIQUE(system_id, period_type, period_start)
);

COMMENT ON TABLE performance_summaries IS 'Aggregated performance statistics by time period';

CREATE INDEX idx_perf_summary_system_period ON performance_summaries(system_id, period_start DESC);
CREATE INDEX idx_perf_summary_period_type ON performance_summaries(period_type, period_start DESC);

-- ============================================================================
-- 10. OPTIMIZATION REPORTS
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

-- TODO : MAKE SURE VIEWS ARE CONSISTENT WITH THE CURRENT SCHEMA.
-- View: Systems with department info
CREATE OR REPLACE VIEW v_systems_overview AS
SELECT 
    s.system_id,
    s.hostname,
    s.ip_address::TEXT,
    s.mac_address::TEXT,
    d.dept_name,
    d.dept_code,
    s.os_type,
    s.status,
    s.collection_method,
    s.last_seen,
    EXTRACT(EPOCH FROM (NOW() - s.last_seen))/60 AS minutes_since_seen,
    s.is_monitored
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
    active_processes,
    logged_in_users
FROM usage_metrics
ORDER BY system_id, timestamp DESC;

-- View: Department statistics
CREATE OR REPLACE VIEW v_department_stats AS
SELECT 
    d.dept_name,
    COUNT(s.system_id) AS total_systems,
    COUNT(s.system_id) FILTER (WHERE s.status = 'active') AS active_systems,
    COUNT(s.system_id) FILTER (WHERE s.status = 'offline') AS offline_systems,
    MAX(s.last_seen) AS last_scan_time
FROM departments d
LEFT JOIN systems s USING(dept_id)
GROUP BY d.dept_id, d.dept_name;

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

CREATE TRIGGER trg_collection_jobs_updated_at
    BEFORE UPDATE ON collection_jobs
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

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
