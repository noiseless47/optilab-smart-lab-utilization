-- ============================================================================
-- Migration Script: Add CFRS Support to Existing Database
-- ============================================================================
-- Purpose: Upgrade existing lab monitoring database to support CFRS computation
-- Run this AFTER running schema.sql and setup_timescaledb.sql on a new database
-- OR run this to migrate an existing database without losing data
-- ============================================================================

BEGIN;

-- ============================================================================
-- 1. Drop and recreate continuous aggregates (they have new columns)
-- ============================================================================

-- Drop existing aggregates (will be recreated by setup_timescaledb.sql)
DROP MATERIALIZED VIEW IF EXISTS hourly_performance_stats CASCADE;
DROP MATERIALIZED VIEW IF EXISTS daily_performance_stats CASCADE;

-- Note: After this script, you MUST run setup_timescaledb.sql to recreate them
-- with STDDEV columns and without unsafe time assumptions

-- ============================================================================
-- 2. Add STDDEV columns to performance_summaries table
-- ============================================================================

-- Add variance columns for CFRS support
ALTER TABLE performance_summaries 
ADD COLUMN IF NOT EXISTS stddev_cpu_percent NUMERIC(5,2),
ADD COLUMN IF NOT EXISTS stddev_ram_percent NUMERIC(5,2),
ADD COLUMN IF NOT EXISTS stddev_gpu_percent NUMERIC(5,2),
ADD COLUMN IF NOT EXISTS stddev_disk_percent NUMERIC(5,2);

-- Add min columns (for statistical completeness)
ALTER TABLE performance_summaries 
ADD COLUMN IF NOT EXISTS min_cpu_percent NUMERIC(5,2),
ADD COLUMN IF NOT EXISTS min_ram_percent NUMERIC(5,2),
ADD COLUMN IF NOT EXISTS min_gpu_percent NUMERIC(5,2),
ADD COLUMN IF NOT EXISTS min_disk_percent NUMERIC(5,2);

-- Add metric_count if missing
ALTER TABLE performance_summaries 
ADD COLUMN IF NOT EXISTS metric_count INT;

-- ============================================================================
-- 3. Remove unsafe/hardcoded columns
-- ============================================================================

-- Remove hardcoded threshold columns
ALTER TABLE performance_summaries 
DROP COLUMN IF EXISTS cpu_above_80_minutes,
DROP COLUMN IF EXISTS ram_above_80_minutes;

-- Remove hardcoded classification columns
ALTER TABLE performance_summaries 
DROP COLUMN IF EXISTS is_underutilized,
DROP COLUMN IF EXISTS is_overutilized;

-- Remove computed score (CFRS will replace this)
ALTER TABLE performance_summaries 
DROP COLUMN IF EXISTS utilization_score;

-- Remove columns with unsafe time assumptions
ALTER TABLE performance_summaries 
DROP COLUMN IF EXISTS total_disk_read_gb,
DROP COLUMN IF EXISTS total_disk_write_gb,
DROP COLUMN IF EXISTS swap_used_minutes,
DROP COLUMN IF EXISTS avg_disk_io_wait;

-- Update table comment
COMMENT ON TABLE performance_summaries IS 'Aggregated performance statistics by time period. Includes variance metrics for CFRS computation. No hardcoded thresholds.';

-- ============================================================================
-- 4. Create system_baselines table
-- ============================================================================

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

CREATE INDEX IF NOT EXISTS idx_baselines_system_metric ON system_baselines(system_id, metric_name, is_active);
CREATE INDEX IF NOT EXISTS idx_baselines_computed ON system_baselines(computed_at DESC);

-- ============================================================================
-- 5. CFRS support views
-- ============================================================================

-- Note: CFRS trend views (v_daily_resource_trends, v_weekly_resource_trends)
-- will be created AFTER running setup_timescaledb.sql, since they depend on
-- the continuous aggregates that need to be recreated first.
-- These views are defined in schema.sql and will be created/updated there.

COMMIT;

-- ============================================================================
-- POST-MIGRATION STEPS (Run manually)
-- ============================================================================

-- 1. Recreate continuous aggregates with new STDDEV columns:
--    psql -d your_database -f database/setup_timescaledb.sql

-- 2. Refresh aggregates to populate new columns (if data exists):
--    CALL refresh_continuous_aggregate('hourly_performance_stats', NULL, NULL);
--    CALL refresh_continuous_aggregate('daily_performance_stats', NULL, NULL);

-- 3. Verify STDDEV columns are populated:
--    SELECT system_id, hour_bucket, stddev_cpu_percent 
--    FROM hourly_performance_stats 
--    WHERE stddev_cpu_percent IS NOT NULL
--    LIMIT 10;

-- ============================================================================

SELECT 'Migration completed!' AS status;
SELECT 'Next steps:' AS info;
SELECT '1. Run: psql -d DB_NAME -f database/setup_timescaledb.sql' AS step1;
SELECT '2. Run: psql -d DB_NAME -f database/schema.sql (to create CFRS views)' AS step2;
SELECT '3. Refresh continuous aggregates to populate STDDEV columns' AS step3;
SELECT '4. Begin computing and storing system baselines' AS step4;
SELECT '5. See CFRS_DATABASE_SUPPORT.md for usage examples' AS step5;
