-- ============================================================================
-- Sample Metrics Data for Testing
-- ============================================================================
-- This script inserts sample metrics data for testing the API endpoints
-- Run this after creating a system to populate metrics data
-- ============================================================================

-- Insert sample metrics for system_id = 1 (adjust ID as needed)
-- This simulates 24 hours of metrics data (every 5 minutes)

DO $$
DECLARE
    sys_id INTEGER := 1; -- Change this to your system ID
    current_time TIMESTAMPTZ := NOW() - INTERVAL '24 hours';
    i INTEGER;
BEGIN
    -- Insert metrics for the last 24 hours (288 records = 24h * 12 per hour)
    FOR i IN 0..287 LOOP
        INSERT INTO metrics (
            system_id,
            timestamp,
            cpu_percent,
            ram_percent,
            disk_percent,
            network_sent_mbps,
            network_recv_mbps,
            gpu_percent,
            gpu_memory_used_gb,
            gpu_temperature,
            uptime_seconds,
            logged_in_users,
            collection_method
        ) VALUES (
            sys_id,
            current_time + (i * INTERVAL '5 minutes'),
            -- CPU: Normal range 10-90%
            10 + (random() * 80)::numeric(5,2),
            -- RAM: Normal range 20-95%
            20 + (random() * 75)::numeric(5,2),
            -- Disk: Normal range 5-85%
            5 + (random() * 80)::numeric(5,2),
            -- Network: 0-100 Mbps
            (random() * 100)::numeric(10,2),
            (random() * 200)::numeric(10,2),
            -- GPU: 0-100% (if available)
            (random() * 100)::numeric(5,2),
            -- GPU Memory: 0-12GB
            (random() * 12)::numeric(10,2),
            -- GPU Temp: 30-85°C
            30 + (random() * 55)::numeric(5,2),
            -- Uptime: increasing over time
            (i * 300 + random() * 600)::bigint,
            -- Users: 0-5
            (random() * 5)::integer,
            -- Collection method
            'wmi'
        );
    END LOOP;

    RAISE NOTICE 'Inserted 288 sample metrics records for system %', sys_id;
END $$;

-- Verify the data was inserted
SELECT
    system_id,
    COUNT(*) as total_metrics,
    MIN(timestamp) as earliest_metric,
    MAX(timestamp) as latest_metric,
    ROUND(AVG(cpu_percent), 2) as avg_cpu_percent,
    ROUND(AVG(ram_percent), 2) as avg_ram_percent
FROM metrics
WHERE system_id = 1  -- Change this to your system ID
GROUP BY system_id;

-- Check that TimescaleDB aggregations are working
SELECT 'Hourly aggregates created:' as status, COUNT(*) as count
FROM hourly_performance_stats
WHERE system_id = 1;  -- Change this to your system ID

SELECT 'Daily aggregates created:' as status, COUNT(*) as count
FROM daily_performance_stats
WHERE system_id = 1;  -- Change this to your system ID

-- ============================================================================
-- END OF SAMPLE METRICS
-- ============================================================================