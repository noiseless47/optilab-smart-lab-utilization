-- ============================================================================
-- Stored Procedures & Analytical Functions
-- ============================================================================
-- Purpose: Complex analytics, optimization scoring, and report generation
-- ============================================================================

-- ============================================================================
-- FUNCTION: Calculate Utilization Score
-- ============================================================================
-- Purpose: Calculate composite efficiency score (0-100) for a system
-- Higher score = better utilization
-- Considers CPU, RAM, GPU usage and balances over/underutilization

CREATE OR REPLACE FUNCTION calculate_utilization_score(
    p_avg_cpu NUMERIC,
    p_avg_ram NUMERIC,
    p_avg_gpu NUMERIC DEFAULT NULL,
    p_p95_cpu NUMERIC DEFAULT NULL,
    p_p95_ram NUMERIC DEFAULT NULL
)
RETURNS NUMERIC AS $$
DECLARE
    v_cpu_score NUMERIC;
    v_ram_score NUMERIC;
    v_gpu_score NUMERIC;
    v_stability_score NUMERIC;
    v_final_score NUMERIC;
BEGIN
    -- CPU Score: Optimal range 50-80%, penalty for too low or too high
    v_cpu_score := CASE
        WHEN p_avg_cpu BETWEEN 50 AND 80 THEN 100
        WHEN p_avg_cpu BETWEEN 40 AND 90 THEN 80
        WHEN p_avg_cpu BETWEEN 30 AND 95 THEN 60
        WHEN p_avg_cpu < 20 THEN 30 -- Underutilized
        ELSE 40 -- Overutilized
    END;
    
    -- RAM Score: Optimal range 40-75%
    v_ram_score := CASE
        WHEN p_avg_ram BETWEEN 40 AND 75 THEN 100
        WHEN p_avg_ram BETWEEN 30 AND 85 THEN 80
        WHEN p_avg_ram BETWEEN 20 AND 90 THEN 60
        WHEN p_avg_ram < 15 THEN 30 -- Underutilized
        ELSE 40 -- Overutilized
    END;
    
    -- GPU Score: If present, optimal 60-90%
    IF p_avg_gpu IS NOT NULL THEN
        v_gpu_score := CASE
            WHEN p_avg_gpu BETWEEN 60 AND 90 THEN 100
            WHEN p_avg_gpu BETWEEN 40 AND 95 THEN 80
            WHEN p_avg_gpu < 20 THEN 30 -- Wasted GPU
            ELSE 60
        END;
    ELSE
        v_gpu_score := NULL;
    END IF;
    
    -- Stability Score: Penalty for high variance (if p95 data available)
    IF p_p95_cpu IS NOT NULL AND p_p95_ram IS NOT NULL THEN
        v_stability_score := CASE
            WHEN (p_p95_cpu - p_avg_cpu) < 20 AND (p_p95_ram - p_avg_ram) < 20 THEN 100
            WHEN (p_p95_cpu - p_avg_cpu) < 30 AND (p_p95_ram - p_avg_ram) < 30 THEN 80
            ELSE 60
        END;
    ELSE
        v_stability_score := 100; -- No penalty if data unavailable
    END IF;
    
    -- Calculate weighted final score
    IF v_gpu_score IS NOT NULL THEN
        v_final_score := (
            v_cpu_score * 0.30 + 
            v_ram_score * 0.30 + 
            v_gpu_score * 0.25 + 
            v_stability_score * 0.15
        );
    ELSE
        v_final_score := (
            v_cpu_score * 0.40 + 
            v_ram_score * 0.40 + 
            v_stability_score * 0.20
        );
    END IF;
    
    RETURN ROUND(v_final_score, 2);
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_utilization_score IS 
'Calculate composite efficiency score (0-100) based on CPU, RAM, GPU usage';

-- ============================================================================
-- FUNCTION: Detect Bottleneck Type
-- ============================================================================
-- Purpose: Identify what type of bottleneck a system is experiencing

CREATE OR REPLACE FUNCTION detect_bottleneck(
    p_system_id INT,
    p_period_start TIMESTAMPTZ,
    p_period_end TIMESTAMPTZ
)
RETURNS TEXT AS $$
DECLARE
    v_avg_cpu NUMERIC;
    v_avg_ram NUMERIC;
    v_avg_io_wait NUMERIC;
    v_swap_usage INTEGER;
    v_bottleneck TEXT;
BEGIN
    -- Get average metrics for the period
    SELECT 
        AVG(cpu_percent),
        AVG(ram_percent),
        AVG(disk_io_wait_percent),
        SUM(CASE WHEN swap_percent > 5 THEN 1 ELSE 0 END)
    INTO v_avg_cpu, v_avg_ram, v_avg_io_wait, v_swap_usage
    FROM usage_metrics
    WHERE system_id = p_system_id
        AND timestamp BETWEEN p_period_start AND p_period_end;
    
    -- Determine bottleneck type based on metrics
    IF v_swap_usage > 10 OR v_avg_ram > 90 THEN
        v_bottleneck := 'RAM - Memory bottleneck detected (high swap usage or RAM exhaustion)';
    ELSIF v_avg_io_wait > 40 THEN
        v_bottleneck := 'DISK - Disk I/O bottleneck (high wait times)';
    ELSIF v_avg_cpu > 85 THEN
        v_bottleneck := 'CPU - CPU bottleneck (sustained high usage)';
    ELSIF v_avg_cpu < 30 AND v_avg_ram < 30 THEN
        v_bottleneck := 'NONE - System is underutilized';
    ELSE
        v_bottleneck := 'NONE - No significant bottleneck detected';
    END IF;
    
    RETURN v_bottleneck;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION detect_bottleneck IS 
'Analyze metrics to identify system bottleneck type (CPU, RAM, DISK, or NONE)';

-- ============================================================================
-- PROCEDURE: Generate Daily Performance Summary
-- ============================================================================
-- Purpose: Calculate and insert daily performance summary for a system

CREATE OR REPLACE PROCEDURE generate_daily_summary(
    p_system_id INT,
    p_date DATE
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_period_start TIMESTAMPTZ;
    v_period_end TIMESTAMPTZ;
    v_summary_record RECORD;
    v_utilization_score NUMERIC;
    v_has_bottleneck BOOLEAN;
BEGIN
    v_period_start := p_date::TIMESTAMPTZ;
    v_period_end := (p_date + INTERVAL '1 day')::TIMESTAMPTZ;
    
    -- Calculate aggregate statistics
    SELECT
        -- CPU Stats
        AVG(cpu_percent) AS avg_cpu,
        MAX(cpu_percent) AS max_cpu,
        MIN(cpu_percent) AS min_cpu,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent) AS p95_cpu,
        SUM(CASE WHEN cpu_percent > 80 THEN 1 ELSE 0 END) * 5 AS cpu_high_minutes,
        
        -- RAM Stats
        AVG(ram_percent) AS avg_ram,
        MAX(ram_percent) AS max_ram,
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent) AS p95_ram,
        SUM(CASE WHEN swap_percent > 0 THEN 1 ELSE 0 END) * 5 AS swap_minutes,
        
        -- GPU Stats
        AVG(gpu_utilization) AS avg_gpu,
        MAX(gpu_utilization) AS max_gpu,
        SUM(CASE WHEN COALESCE(gpu_utilization, 0) < 10 THEN 1 ELSE 0 END) * 5 AS gpu_idle,
        
        -- Disk Stats
        AVG(disk_io_wait_percent) AS avg_io_wait,
        SUM(disk_read_mb_s * 300 / 1024.0) AS total_read_gb,
        SUM(disk_write_mb_s * 300 / 1024.0) AS total_write_gb,
        
        -- Uptime (number of 5-min intervals)
        COUNT(*) * 5 AS uptime_minutes
        
    INTO v_summary_record
    FROM usage_metrics
    WHERE system_id = p_system_id
        AND timestamp BETWEEN v_period_start AND v_period_end;
    
    -- Calculate utilization score
    v_utilization_score := calculate_utilization_score(
        v_summary_record.avg_cpu,
        v_summary_record.avg_ram,
        v_summary_record.avg_gpu,
        v_summary_record.p95_cpu,
        v_summary_record.p95_ram
    );
    
    -- Check for bottleneck
    v_has_bottleneck := (
        detect_bottleneck(p_system_id, v_period_start, v_period_end) NOT LIKE '%NONE%'
    );
    
    -- Insert or update summary
    INSERT INTO performance_summaries (
        system_id, period_type, period_start, period_end,
        avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent, cpu_above_80_minutes,
        avg_ram_percent, max_ram_percent, p95_ram_percent, swap_used_minutes,
        avg_gpu_percent, max_gpu_percent, gpu_idle_minutes,
        avg_disk_io_wait, total_disk_read_gb, total_disk_write_gb,
        uptime_minutes, utilization_score,
        is_underutilized, is_overutilized, has_bottleneck
    )
    VALUES (
        p_system_id, 'daily', v_period_start, v_period_end,
        v_summary_record.avg_cpu, v_summary_record.max_cpu, v_summary_record.min_cpu, 
        v_summary_record.p95_cpu, v_summary_record.cpu_high_minutes,
        v_summary_record.avg_ram, v_summary_record.max_ram, 
        v_summary_record.p95_ram, v_summary_record.swap_minutes,
        v_summary_record.avg_gpu, v_summary_record.max_gpu, v_summary_record.gpu_idle,
        v_summary_record.avg_io_wait, v_summary_record.total_read_gb, v_summary_record.total_write_gb,
        v_summary_record.uptime_minutes, v_utilization_score,
        (v_summary_record.avg_cpu < 30 AND v_summary_record.avg_ram < 30),
        (v_summary_record.p95_cpu > 90 OR v_summary_record.p95_ram > 90),
        v_has_bottleneck
    )
    ON CONFLICT (system_id, period_type, period_start) 
    DO UPDATE SET
        avg_cpu_percent = EXCLUDED.avg_cpu_percent,
        max_cpu_percent = EXCLUDED.max_cpu_percent,
        utilization_score = EXCLUDED.utilization_score,
        is_underutilized = EXCLUDED.is_underutilized,
        is_overutilized = EXCLUDED.is_overutilized,
        has_bottleneck = EXCLUDED.has_bottleneck;
    
    RAISE NOTICE 'Daily summary generated for system % on %', p_system_id, p_date;
END;
$$;

COMMENT ON PROCEDURE generate_daily_summary IS 
'Generate daily performance summary with utilization scores and flags';

-- ============================================================================
-- FUNCTION: Generate Hardware Recommendations
-- ============================================================================
-- Purpose: Analyze system performance and generate upgrade recommendations

CREATE OR REPLACE FUNCTION generate_hardware_recommendations(
    p_system_id INT,
    p_analysis_days INTEGER DEFAULT 30
)
RETURNS TABLE (
    recommendation_type VARCHAR,
    priority INTEGER,
    title VARCHAR,
    description TEXT,
    estimated_impact VARCHAR
) AS $$
DECLARE
    v_system RECORD;
    v_avg_cpu NUMERIC;
    v_avg_ram NUMERIC;
    v_p95_ram NUMERIC;
    v_avg_io_wait NUMERIC;
    v_swap_usage INTEGER;
    v_avg_gpu NUMERIC;
BEGIN
    -- Get system specs
    SELECT * INTO v_system FROM systems WHERE system_id = p_system_id;
    
    -- Get performance metrics for analysis period
    SELECT
        AVG(cpu_percent),
        AVG(ram_percent),
        PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY ram_percent),
        AVG(disk_io_wait_percent),
        SUM(CASE WHEN swap_percent > 5 THEN 1 ELSE 0 END),
        AVG(gpu_utilization)
    INTO v_avg_cpu, v_avg_ram, v_p95_ram, v_avg_io_wait, v_swap_usage, v_avg_gpu
    FROM usage_metrics
    WHERE system_id = p_system_id
        AND timestamp >= CURRENT_TIMESTAMP - (p_analysis_days || ' days')::INTERVAL;
    
    -- RAM Upgrade Recommendation
    IF v_p95_ram > 85 OR v_swap_usage > 50 THEN
        RETURN QUERY SELECT 
            'hardware_upgrade'::VARCHAR,
            9,
            'RAM Upgrade Required'::VARCHAR,
            format('System %s shows high memory pressure (avg: %s%%, p95: %s%%). Current: %s GB. Recommend upgrading to %s GB.',
                v_system.hostname, ROUND(v_avg_ram, 1), ROUND(v_p95_ram, 1),
                v_system.ram_total_gb, v_system.ram_total_gb * 2),
            'HIGH - Will significantly reduce swap usage and improve performance'::VARCHAR;
    END IF;
    
    -- Disk Upgrade Recommendation
    IF v_avg_io_wait > 30 AND v_system.disk_type = 'HDD' THEN
        RETURN QUERY SELECT
            'hardware_upgrade'::VARCHAR,
            8,
            'Disk Upgrade to SSD Recommended'::VARCHAR,
            format('System %s has high I/O wait times (avg: %s%%). Current disk type: %s. Recommend upgrading to NVMe SSD.',
                v_system.hostname, ROUND(v_avg_io_wait, 1), v_system.disk_type),
            'HIGH - Will dramatically improve I/O performance'::VARCHAR;
    END IF;
    
    -- CPU Upgrade Recommendation
    IF v_avg_cpu > 85 THEN
        RETURN QUERY SELECT
            'hardware_upgrade'::VARCHAR,
            7,
            'CPU Upgrade or Workload Redistribution'::VARCHAR,
            format('System %s shows sustained high CPU usage (avg: %s%%). Current: %s cores. Consider upgrading CPU or redistributing workload.',
                v_system.hostname, ROUND(v_avg_cpu, 1), v_system.cpu_cores),
            'MEDIUM - Will improve processing capacity'::VARCHAR;
    END IF;
    
    -- GPU Addition Recommendation
    IF v_system.gpu_count = 0 AND v_avg_cpu > 70 THEN
        RETURN QUERY SELECT
            'hardware_addition'::VARCHAR,
            6,
            'Consider Adding GPU for Compute Tasks'::VARCHAR,
            format('System %s has high CPU usage (%s%%) with no GPU. If running ML/graphics workloads, adding a GPU could offload work.',
                v_system.hostname, ROUND(v_avg_cpu, 1)),
            'MEDIUM - If applicable to workload type'::VARCHAR;
    END IF;
    
    -- Underutilization - Reallocation
    IF v_avg_cpu < 20 AND v_avg_ram < 25 THEN
        RETURN QUERY SELECT
            'reallocation'::VARCHAR,
            5,
            'System Underutilized - Consider Reallocation'::VARCHAR,
            format('System %s is underutilized (CPU: %s%%, RAM: %s%%). Consider consolidating workloads or repurposing.',
                v_system.hostname, ROUND(v_avg_cpu, 1), ROUND(v_avg_ram, 1)),
            'MEDIUM - Cost optimization opportunity'::VARCHAR;
    END IF;
    
    -- Wasted GPU
    IF v_system.gpu_count > 0 AND COALESCE(v_avg_gpu, 0) < 15 THEN
        RETURN QUERY SELECT
            'reallocation'::VARCHAR,
            6,
            'GPU Underutilized - Reallocation Recommended'::VARCHAR,
            format('System %s has GPU (%s) with low utilization (avg: %s%%). Consider moving to GPU-intensive workload system.',
                v_system.hostname, v_system.gpu_model, ROUND(v_avg_gpu, 1)),
            'MEDIUM - Better GPU resource allocation'::VARCHAR;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION generate_hardware_recommendations IS 
'Analyze system metrics and generate hardware upgrade/reallocation recommendations';

-- ============================================================================
-- PROCEDURE: Create Optimization Report
-- ============================================================================

CREATE OR REPLACE PROCEDURE create_optimization_report(
    p_system_id INT,
    p_analysis_days INTEGER DEFAULT 30
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_recommendations JSONB;
    v_report_id INT;
    v_system_hostname VARCHAR;
    v_severity VARCHAR;
    v_priority INTEGER;
BEGIN
    -- Get system hostname
    SELECT hostname INTO v_system_hostname FROM systems WHERE system_id = p_system_id;
    
    -- Generate recommendations and convert to JSONB
    SELECT jsonb_agg(
        jsonb_build_object(
            'type', recommendation_type,
            'priority', priority,
            'title', title,
            'description', description,
            'impact', estimated_impact
        )
    )
    INTO v_recommendations
    FROM generate_hardware_recommendations(p_system_id, p_analysis_days);
    
    -- Determine severity based on max priority
    SELECT MAX(priority) INTO v_priority
    FROM generate_hardware_recommendations(p_system_id, p_analysis_days);
    
    v_severity := CASE
        WHEN v_priority >= 9 THEN 'critical'
        WHEN v_priority >= 7 THEN 'high'
        WHEN v_priority >= 5 THEN 'medium'
        ELSE 'low'
    END;
    
    -- Insert report only if there are recommendations
    IF v_recommendations IS NOT NULL AND jsonb_array_length(v_recommendations) > 0 THEN
        INSERT INTO optimization_reports (
            system_id,
            report_type,
            severity,
            title,
            description,
            recommendations,
            priority_score,
            analysis_period_start,
            analysis_period_end,
            status
        )
        VALUES (
            p_system_id,
            'automated_analysis',
            v_severity,
            format('Optimization Report for %s', v_system_hostname),
            format('Automated analysis based on %s days of performance data', p_analysis_days),
            v_recommendations,
            v_priority,
            CURRENT_TIMESTAMP - (p_analysis_days || ' days')::INTERVAL,
            CURRENT_TIMESTAMP,
            'pending'
        )
        RETURNING report_id INTO v_report_id;
        
        RAISE NOTICE 'Optimization report % created for system %', v_report_id, v_system_hostname;
    ELSE
        RAISE NOTICE 'No recommendations found for system %', v_system_hostname;
    END IF;
END;
$$;

-- ============================================================================
-- FUNCTION: Get Top Resource Consumers
-- ============================================================================

CREATE OR REPLACE FUNCTION get_top_resource_consumers(
    p_resource_type VARCHAR, -- 'cpu', 'ram', 'gpu', 'disk_io'
    p_limit INTEGER DEFAULT 10,
    p_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    hostname VARCHAR,
    location VARCHAR,
    avg_usage NUMERIC,
    max_usage NUMERIC,
    current_usage NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        s.hostname,
        s.location,
        ROUND(AVG(
            CASE p_resource_type
                WHEN 'cpu' THEN um.cpu_percent
                WHEN 'ram' THEN um.ram_percent
                WHEN 'gpu' THEN um.gpu_utilization
                WHEN 'disk_io' THEN um.disk_io_wait_percent
            END
        )::NUMERIC, 2) AS avg_usage,
        ROUND(MAX(
            CASE p_resource_type
                WHEN 'cpu' THEN um.cpu_percent
                WHEN 'ram' THEN um.ram_percent
                WHEN 'gpu' THEN um.gpu_utilization
                WHEN 'disk_io' THEN um.disk_io_wait_percent
            END
        )::NUMERIC, 2) AS max_usage,
        ROUND((
            SELECT CASE p_resource_type
                WHEN 'cpu' THEN cpu_percent
                WHEN 'ram' THEN ram_percent
                WHEN 'gpu' THEN gpu_utilization
                WHEN 'disk_io' THEN disk_io_wait_percent
            END
            FROM usage_metrics um2
            WHERE um2.system_id = s.system_id
            ORDER BY timestamp DESC
            LIMIT 1
        )::NUMERIC, 2) AS current_usage
    FROM systems s
    JOIN usage_metrics um ON s.system_id = um.system_id
    WHERE um.timestamp >= CURRENT_TIMESTAMP - (p_hours || ' hours')::INTERVAL
        AND s.status = 'active'
    GROUP BY s.system_id, s.hostname, s.location
    ORDER BY avg_usage DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_top_resource_consumers IS 
'Get top N systems by resource usage (cpu/ram/gpu/disk_io) over specified hours';

-- ============================================================================
-- END OF STORED PROCEDURES
-- ============================================================================
