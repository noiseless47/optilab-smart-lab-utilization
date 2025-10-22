-- ============================================================================
-- Triggers for Real-Time Monitoring & Alerts
-- ============================================================================
-- Purpose: Automated anomaly detection and threshold-based alerts
-- ============================================================================

-- ============================================================================
-- TRIGGER: Update System Last Seen Timestamp
-- ============================================================================

CREATE OR REPLACE FUNCTION update_system_last_seen()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE systems
    SET last_seen = NEW.timestamp
    WHERE system_id = NEW.system_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_last_seen
    AFTER INSERT ON usage_metrics
    FOR EACH ROW
    EXECUTE FUNCTION update_system_last_seen();

COMMENT ON TRIGGER trg_update_last_seen ON usage_metrics IS 
'Automatically update system last_seen timestamp when metrics are inserted';

-- ============================================================================
-- TRIGGER: Automatic Alert Generation
-- ============================================================================

CREATE OR REPLACE FUNCTION check_alert_conditions()
RETURNS TRIGGER AS $$
DECLARE
    v_rule RECORD;
    v_metric_value NUMERIC;
    v_threshold_exceeded BOOLEAN;
    v_recent_alerts INTEGER;
BEGIN
    -- Loop through all enabled alert rules
    FOR v_rule IN 
        SELECT * FROM alert_rules WHERE is_enabled = TRUE
    LOOP
        -- Get the metric value from the new row
        v_metric_value := CASE v_rule.metric_name
            WHEN 'cpu_percent' THEN NEW.cpu_percent
            WHEN 'ram_percent' THEN NEW.ram_percent
            WHEN 'gpu_utilization' THEN NEW.gpu_utilization
            WHEN 'gpu_temp' THEN NEW.gpu_temp
            WHEN 'disk_percent' THEN NEW.disk_percent
            WHEN 'disk_io_wait_percent' THEN NEW.disk_io_wait_percent
            WHEN 'cpu_temp' THEN NEW.cpu_temp
            WHEN 'swap_percent' THEN NEW.swap_percent
            ELSE NULL
        END;
        
        -- Skip if metric not applicable
        CONTINUE WHEN v_metric_value IS NULL;
        
        -- Check if threshold is exceeded
        v_threshold_exceeded := CASE v_rule.condition
            WHEN '>' THEN v_metric_value > v_rule.threshold_value
            WHEN '<' THEN v_metric_value < v_rule.threshold_value
            WHEN '>=' THEN v_metric_value >= v_rule.threshold_value
            WHEN '<=' THEN v_metric_value <= v_rule.threshold_value
            WHEN '=' THEN v_metric_value = v_rule.threshold_value
            ELSE FALSE
        END;
        
        -- If threshold exceeded, check if sustained over duration
        IF v_threshold_exceeded THEN
            -- Check how many times this condition was met in the duration window
            SELECT COUNT(*) INTO v_recent_alerts
            FROM usage_metrics
            WHERE system_id = NEW.system_id
                AND timestamp BETWEEN 
                    NEW.timestamp - (v_rule.duration_minutes || ' minutes')::INTERVAL 
                    AND NEW.timestamp
                AND CASE v_rule.metric_name
                    WHEN 'cpu_percent' THEN cpu_percent
                    WHEN 'ram_percent' THEN ram_percent
                    WHEN 'gpu_utilization' THEN gpu_utilization
                    WHEN 'gpu_temp' THEN gpu_temp
                    WHEN 'disk_percent' THEN disk_percent
                    WHEN 'disk_io_wait_percent' THEN disk_io_wait_percent
                    WHEN 'cpu_temp' THEN cpu_temp
                    WHEN 'swap_percent' THEN swap_percent
                END > v_rule.threshold_value;
            
            -- If sustained for the duration, create alert (if not already alerted recently)
            IF v_recent_alerts >= (v_rule.duration_minutes / 5) THEN -- Assuming 5-min collection interval
                -- Check if similar alert exists in last hour (prevent spam)
                IF NOT EXISTS (
                    SELECT 1 FROM alert_logs
                    WHERE rule_id = v_rule.rule_id
                        AND system_id = NEW.system_id
                        AND triggered_at > NEW.timestamp - INTERVAL '1 hour'
                        AND resolved_at IS NULL
                ) THEN
                    -- Insert alert
                    INSERT INTO alert_logs (
                        rule_id,
                        system_id,
                        triggered_at,
                        metric_name,
                        actual_value,
                        threshold_value,
                        severity,
                        message,
                        metadata
                    )
                    VALUES (
                        v_rule.rule_id,
                        NEW.system_id,
                        NEW.timestamp,
                        v_rule.metric_name,
                        v_metric_value,
                        v_rule.threshold_value,
                        v_rule.severity,
                        format('Alert: %s on system. %s: %s %s %s (threshold: %s) for %s minutes',
                            v_rule.rule_name,
                            v_rule.metric_name,
                            v_metric_value,
                            v_rule.condition,
                            v_rule.threshold_value,
                            v_rule.threshold_value,
                            v_rule.duration_minutes
                        ),
                        jsonb_build_object(
                            'hostname', (SELECT hostname FROM systems WHERE system_id = NEW.system_id),
                            'rule_name', v_rule.rule_name,
                            'timestamp', NEW.timestamp
                        )
                    );
                END IF;
            END IF;
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_check_alerts
    AFTER INSERT ON usage_metrics
    FOR EACH ROW
    EXECUTE FUNCTION check_alert_conditions();

COMMENT ON TRIGGER trg_check_alerts ON usage_metrics IS 
'Automatically check alert conditions and generate alerts when thresholds are exceeded';

-- ============================================================================
-- TRIGGER: Increment Anomaly Count in Performance Summary
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_anomaly_count()
RETURNS TRIGGER AS $$
BEGIN
    -- Update anomaly count in today's daily summary
    UPDATE performance_summaries
    SET anomaly_count = anomaly_count + 1
    WHERE system_id = NEW.system_id
        AND period_type = 'daily'
        AND period_start = DATE_TRUNC('day', NEW.triggered_at)
        AND period_end = DATE_TRUNC('day', NEW.triggered_at) + INTERVAL '1 day';
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_update_anomaly_count
    AFTER INSERT ON alert_logs
    FOR EACH ROW
    WHEN (NEW.severity IN ('warning', 'critical'))
    EXECUTE FUNCTION increment_anomaly_count();

COMMENT ON TRIGGER trg_update_anomaly_count ON alert_logs IS 
'Increment anomaly count in performance summary when critical/warning alerts are triggered';

-- ============================================================================
-- TRIGGER: Auto-close Alerts
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_resolve_alerts()
RETURNS TRIGGER AS $$
DECLARE
    v_alert RECORD;
BEGIN
    -- Find open alerts for this system
    FOR v_alert IN 
        SELECT al.alert_id, al.metric_name, al.threshold_value, ar.condition
        FROM alert_logs al
        JOIN alert_rules ar ON al.rule_id = ar.rule_id
        WHERE al.system_id = NEW.system_id
            AND al.resolved_at IS NULL
    LOOP
        -- Check if condition is no longer met
        IF (v_alert.condition = '>' AND 
            CASE v_alert.metric_name
                WHEN 'cpu_percent' THEN NEW.cpu_percent
                WHEN 'ram_percent' THEN NEW.ram_percent
                WHEN 'gpu_utilization' THEN NEW.gpu_utilization
                WHEN 'disk_percent' THEN NEW.disk_percent
                WHEN 'disk_io_wait_percent' THEN NEW.disk_io_wait_percent
                ELSE NULL
            END <= v_alert.threshold_value * 0.9) -- 10% buffer
        OR (v_alert.condition = '<' AND 
            CASE v_alert.metric_name
                WHEN 'cpu_percent' THEN NEW.cpu_percent
                WHEN 'ram_percent' THEN NEW.ram_percent
                WHEN 'gpu_utilization' THEN NEW.gpu_utilization
                ELSE NULL
            END >= v_alert.threshold_value * 1.1)
        THEN
            -- Auto-resolve the alert
            UPDATE alert_logs
            SET resolved_at = NEW.timestamp
            WHERE alert_id = v_alert.alert_id;
        END IF;
    END LOOP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_resolve_alerts
    AFTER INSERT ON usage_metrics
    FOR EACH ROW
    EXECUTE FUNCTION auto_resolve_alerts();

COMMENT ON TRIGGER trg_auto_resolve_alerts ON usage_metrics IS 
'Automatically resolve alerts when metrics return to normal levels';

-- ============================================================================
-- TRIGGER: Validate Metrics Before Insert
-- ============================================================================

CREATE OR REPLACE FUNCTION validate_usage_metrics()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate percentage values are within 0-100
    IF NEW.cpu_percent IS NOT NULL AND (NEW.cpu_percent < 0 OR NEW.cpu_percent > 100) THEN
        RAISE WARNING 'Invalid cpu_percent value: %. Setting to NULL.', NEW.cpu_percent;
        NEW.cpu_percent := NULL;
    END IF;
    
    IF NEW.ram_percent IS NOT NULL AND (NEW.ram_percent < 0 OR NEW.ram_percent > 100) THEN
        RAISE WARNING 'Invalid ram_percent value: %. Setting to NULL.', NEW.ram_percent;
        NEW.ram_percent := NULL;
    END IF;
    
    IF NEW.gpu_utilization IS NOT NULL AND (NEW.gpu_utilization < 0 OR NEW.gpu_utilization > 100) THEN
        RAISE WARNING 'Invalid gpu_utilization value: %. Setting to NULL.', NEW.gpu_utilization;
        NEW.gpu_utilization := NULL;
    END IF;
    
    IF NEW.disk_percent IS NOT NULL AND (NEW.disk_percent < 0 OR NEW.disk_percent > 100) THEN
        RAISE WARNING 'Invalid disk_percent value: %. Setting to NULL.', NEW.disk_percent;
        NEW.disk_percent := NULL;
    END IF;
    
    -- Validate non-negative values
    IF NEW.ram_used_gb IS NOT NULL AND NEW.ram_used_gb < 0 THEN
        NEW.ram_used_gb := 0;
    END IF;
    
    IF NEW.disk_read_mb_s IS NOT NULL AND NEW.disk_read_mb_s < 0 THEN
        NEW.disk_read_mb_s := 0;
    END IF;
    
    IF NEW.disk_write_mb_s IS NOT NULL AND NEW.disk_write_mb_s < 0 THEN
        NEW.disk_write_mb_s := 0;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_metrics
    BEFORE INSERT ON usage_metrics
    FOR EACH ROW
    EXECUTE FUNCTION validate_usage_metrics();

COMMENT ON TRIGGER trg_validate_metrics ON usage_metrics IS 
'Validate and sanitize metric values before insertion';

-- ============================================================================
-- TRIGGER: Auto-create System Record
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_create_system()
RETURNS TRIGGER AS $$
BEGIN
    -- If system_id doesn't exist, this will fail FK constraint
    -- This trigger logs the attempt for audit purposes
    IF NOT EXISTS (SELECT 1 FROM systems WHERE system_id = NEW.system_id) THEN
        RAISE NOTICE 'Attempted to insert metrics for non-existent system: %', NEW.system_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Note: Commented out as it might interfere with FK constraint
-- CREATE TRIGGER trg_check_system_exists
--     BEFORE INSERT ON usage_metrics
--     FOR EACH ROW
--     EXECUTE FUNCTION auto_create_system();

-- ============================================================================
-- SCHEDULED JOBS (Using pg_cron extension if available)
-- ============================================================================

-- To use these, install pg_cron extension: CREATE EXTENSION pg_cron;

/*
-- Generate daily summaries for all systems (runs at 1 AM daily)
SELECT cron.schedule(
    'generate-daily-summaries',
    '0 1 * * *',
    $$
    DO $$
    DECLARE
        v_system RECORD;
    BEGIN
        FOR v_system IN SELECT system_id FROM systems WHERE status = 'active'
        LOOP
            CALL generate_daily_summary(v_system.system_id, CURRENT_DATE - 1);
        END LOOP;
    END $$;
    $$
);

-- Generate optimization reports weekly (runs Sunday at 2 AM)
SELECT cron.schedule(
    'weekly-optimization-reports',
    '0 2 * * 0',
    $$
    DO $$
    DECLARE
        v_system RECORD;
    BEGIN
        FOR v_system IN SELECT system_id FROM systems WHERE status = 'active'
        LOOP
            CALL create_optimization_report(v_system.system_id, 30);
        END LOOP;
    END $$;
    $$
);

-- Clean up old unacknowledged info-level alerts (runs daily at 3 AM)
SELECT cron.schedule(
    'cleanup-old-alerts',
    '0 3 * * *',
    $$
    DELETE FROM alert_logs 
    WHERE severity = 'info' 
        AND triggered_at < CURRENT_TIMESTAMP - INTERVAL '30 days'
        AND is_acknowledged = FALSE;
    $$
);
*/

-- ============================================================================
-- Manual Trigger Testing
-- ============================================================================

-- Test alert trigger with sample data
-- INSERT INTO usage_metrics (system_id, timestamp, cpu_percent, ram_percent, disk_percent)
-- SELECT 
--     (SELECT system_id FROM systems LIMIT 1),
--     CURRENT_TIMESTAMP,
--     96.5,  -- Should trigger high CPU alert
--     92.0,  -- Should trigger high RAM alert
--     88.0;  -- Should trigger disk space alert

-- ============================================================================
-- END OF TRIGGERS
-- ============================================================================
