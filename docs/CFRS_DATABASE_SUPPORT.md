# CFRS Database Support Documentation

## Overview

The database layer has been extended to support the **Composite Fault Risk Score (CFRS)** system for academic lab computer monitoring. The database prepares statistically correct inputs for CFRS computation but **does not compute CFRS itself**.

## CFRS Components (Computed Outside Database)

CFRS ranks systems by operational degradation risk using three components:

1. **Deviation** - Short-term abnormal behavior relative to baseline (z-scores)
2. **Variance** - Instability/unpredictability over rolling windows (STDDEV)
3. **Trend** - Long-term degradation via slope detection (linear regression)

---

## Database Changes

### ✅ 1. Variance Metrics Added

Both `hourly_performance_stats` and `daily_performance_stats` continuous aggregates now include:

```sql
-- For each resource type (CPU, RAM, GPU, Disk):
STDDEV(cpu_percent) AS stddev_cpu_percent
STDDEV(ram_percent) AS stddev_ram_percent
STDDEV(gpu_percent) AS stddev_gpu_percent
STDDEV(disk_percent) AS stddev_disk_percent
```

**Purpose:** Direct input for CFRS variance component. High STDDEV = unstable/unpredictable system.

**Usage Example:**
```sql
-- Get last 7 days variance for a system
SELECT 
    day_bucket::DATE,
    stddev_cpu_percent,
    stddev_ram_percent
FROM daily_performance_stats
WHERE system_id = 1 
  AND day_bucket >= NOW() - INTERVAL '7 days'
ORDER BY day_bucket;
```

---

### ✅ 2. Unsafe Time Assumptions Removed

**Removed:**
```sql
-- ❌ REMOVED: Assumed 5-minute sampling intervals
SUM(CASE WHEN cpu_percent > 80 THEN 1 ELSE 0 END) * 5 AS cpu_above_80_minutes
```

**Why:** Fixed sampling assumptions break when:
- Metrics arrive at irregular intervals
- Systems go offline temporarily
- Collection frequency changes

**Alternative:** Compute durations using actual timestamps in application layer if needed.

---

### ✅ 3. Baseline Storage Table

New table: `system_baselines`

Stores statistical baselines for deviation component (z-score computation):

```sql
CREATE TABLE system_baselines (
    baseline_id SERIAL PRIMARY KEY,
    system_id INT NOT NULL,
    metric_name VARCHAR(50) NOT NULL,  -- 'cpu_percent', 'ram_percent', etc.
    
    -- Statistics
    baseline_mean NUMERIC(10,4) NOT NULL,
    baseline_stddev NUMERIC(10,4) NOT NULL,
    baseline_median NUMERIC(10,4),
    baseline_p95 NUMERIC(10,4),
    
    -- Context
    baseline_start TIMESTAMPTZ NOT NULL,
    baseline_end TIMESTAMPTZ NOT NULL,
    sample_count INT NOT NULL,
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE
);
```

**Purpose:** Store "normal behavior" baselines for each system/metric. Used for z-score deviation computation:

```
z-score = (current_value - baseline_mean) / baseline_stddev
```

**Usage Example:**
```sql
-- Store baseline for system 1 CPU (computed externally)
INSERT INTO system_baselines (
    system_id, metric_name, 
    baseline_mean, baseline_stddev, baseline_median,
    baseline_start, baseline_end, sample_count
) VALUES (
    1, 'cpu_percent',
    42.5, 12.3, 40.1,
    '2026-01-01', '2026-01-14', 2016
);

-- Retrieve active baselines for deviation computation
SELECT 
    metric_name,
    baseline_mean,
    baseline_stddev
FROM system_baselines
WHERE system_id = 1 AND is_active = TRUE;
```

---

### ✅ 4. Trend-Friendly Views

#### `v_daily_resource_trends`

Daily time-series data suitable for **linear regression** / slope computation:

```sql
SELECT * FROM v_daily_resource_trends
WHERE system_id = 1
  AND date >= NOW() - INTERVAL '30 days'
ORDER BY date;
```

Returns:
- `date`, `day_bucket`
- `avg_cpu_percent`, `stddev_cpu_percent`, `max_cpu_percent`
- `avg_ram_percent`, `stddev_ram_percent`, `max_ram_percent`
- `avg_gpu_percent`, `avg_disk_percent`
- `metric_count` (sample quality indicator)

**Use Case:** Compute trend slope externally using linear regression:
```python
# External computation example (NOT in database)
import numpy as np
from scipy.stats import linregress

# Fetch daily averages
days = [1, 2, 3, ..., 30]
cpu_avgs = [45.2, 46.1, 47.3, ..., 58.9]

slope, intercept, r_value, p_value, std_err = linregress(days, cpu_avgs)

# Positive slope = degradation trend
if slope > 0.1:  # Rising >0.1% per day
    print("Degradation detected")
```

---

#### `v_weekly_resource_trends`

Weekly aggregates for multi-day pattern analysis:

```sql
SELECT * FROM v_weekly_resource_trends
WHERE system_id = 1
  AND week_bucket >= NOW() - INTERVAL '90 days';
```

Returns:
- `week_bucket` (7-day buckets)
- `avg_cpu_weekly`, `stddev_cpu_weekly`, `peak_cpu_weekly`
- Similar for RAM, GPU, disk
- `total_samples` (quality indicator)

**Use Case:** Longer-term trend detection, smoothing out daily noise.

---

### ✅ 5. Updated `performance_summaries` Table

Removed unsafe/hardcoded metrics:

**Removed:**
- `cpu_above_80_minutes` (hardcoded threshold)
- `is_underutilized` / `is_overutilized` (hardcoded classification)
- `utilization_score` (computed score - CFRS should replace this)
- `total_disk_read_gb` / `total_disk_write_gb` (unsafe time assumptions)

**Added:**
- `stddev_cpu_percent`
- `stddev_ram_percent`
- `stddev_gpu_percent`
- `stddev_disk_percent`
- `min_cpu_percent`, `min_ram_percent`, `min_gpu_percent`, `min_disk_percent`

---

## CFRS Computation Workflow (External)

The database **only** provides inputs. CFRS computation happens in application layer:

### Step 1: Establish Baselines

```python
# Compute baseline from first 14 days of "normal" operation
baseline_data = fetch_metrics(system_id=1, days=14)
baseline_mean = np.mean(baseline_data['cpu_percent'])
baseline_stddev = np.std(baseline_data['cpu_percent'])

# Store in database
store_baseline(system_id=1, metric='cpu_percent', 
               mean=baseline_mean, stddev=baseline_stddev)
```

### Step 2: Compute Deviation Component

```python
# Fetch current value and baseline
current_cpu = fetch_latest_metric(system_id=1, 'cpu_percent')
baseline = fetch_baseline(system_id=1, 'cpu_percent')

# Z-score deviation
z_score = (current_cpu - baseline['mean']) / baseline['stddev']
deviation_component = abs(z_score)  # Higher = more abnormal
```

### Step 3: Compute Variance Component

```python
# Fetch recent variance from aggregates
recent_variance = query("""
    SELECT stddev_cpu_percent
    FROM hourly_performance_stats
    WHERE system_id = 1 
      AND hour_bucket >= NOW() - INTERVAL '24 hours'
""")

variance_component = np.mean(recent_variance)  # Higher = more unstable
```

### Step 4: Compute Trend Component

```python
# Fetch daily trends for regression
daily_data = query("""
    SELECT date, avg_cpu_percent
    FROM v_daily_resource_trends
    WHERE system_id = 1 
      AND date >= NOW() - INTERVAL '30 days'
    ORDER BY date
""")

# Linear regression slope
slope, _ = np.polyfit(daily_data['date_ordinal'], daily_data['avg_cpu_percent'], 1)
trend_component = max(0, slope)  # Only positive slopes = degradation
```

### Step 5: Combine into CFRS

```python
# Weighted composite score
CFRS = (
    w1 * deviation_component +
    w2 * variance_component +
    w3 * trend_component
)

# Rank systems by CFRS (highest = most at-risk)
```

---

## Migration Guide

### For Existing Databases

1. **Recreate continuous aggregates** (they were modified):
   ```bash
   psql -d lab_monitor -f database/setup_timescaledb.sql
   ```

2. **Add new columns to `performance_summaries`**:
   ```sql
   ALTER TABLE performance_summaries 
   ADD COLUMN IF NOT EXISTS stddev_cpu_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS stddev_ram_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS stddev_gpu_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS stddev_disk_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS min_cpu_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS min_ram_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS min_gpu_percent NUMERIC(5,2),
   ADD COLUMN IF NOT EXISTS min_disk_percent NUMERIC(5,2),
   DROP COLUMN IF EXISTS cpu_above_80_minutes,
   DROP COLUMN IF EXISTS ram_above_80_minutes,
   DROP COLUMN IF EXISTS is_underutilized,
   DROP COLUMN IF EXISTS is_overutilized,
   DROP COLUMN IF EXISTS utilization_score;
   ```

3. **Create baselines table**:
   ```sql
   CREATE TABLE system_baselines (
       -- See full definition in schema.sql
   );
   ```

4. **Refresh aggregates** to populate STDDEV values:
   ```sql
   CALL refresh_continuous_aggregate('hourly_performance_stats', NULL, NULL);
   CALL refresh_continuous_aggregate('daily_performance_stats', NULL, NULL);
   ```

---

## Query Examples for CFRS

### Get Variance Inputs (Last 24 Hours)
```sql
SELECT 
    system_id,
    hour_bucket,
    stddev_cpu_percent,
    stddev_ram_percent,
    metric_count
FROM hourly_performance_stats
WHERE hour_bucket >= NOW() - INTERVAL '24 hours'
ORDER BY system_id, hour_bucket DESC;
```

### Get Baseline for Deviation
```sql
SELECT 
    system_id,
    metric_name,
    baseline_mean,
    baseline_stddev,
    sample_count,
    baseline_start,
    baseline_end
FROM system_baselines
WHERE is_active = TRUE
ORDER BY system_id, metric_name;
```

### Get Trend Data (30 Days)
```sql
SELECT 
    system_id,
    date,
    avg_cpu_percent,
    avg_ram_percent,
    stddev_cpu_percent
FROM v_daily_resource_trends
WHERE date >= NOW() - INTERVAL '30 days'
ORDER BY system_id, date;
```

### Combined Query for All CFRS Inputs
```sql
-- Get all inputs needed for CFRS computation
WITH latest_metrics AS (
    SELECT system_id, avg_cpu_percent, stddev_cpu_percent
    FROM hourly_performance_stats
    WHERE hour_bucket = (SELECT MAX(hour_bucket) FROM hourly_performance_stats)
),
baselines AS (
    SELECT system_id, metric_name, baseline_mean, baseline_stddev
    FROM system_baselines
    WHERE is_active = TRUE AND metric_name = 'cpu_percent'
),
trends AS (
    SELECT system_id, 
           REGR_SLOPE(avg_cpu_percent, EXTRACT(EPOCH FROM date)) as cpu_slope
    FROM v_daily_resource_trends
    WHERE date >= NOW() - INTERVAL '30 days'
    GROUP BY system_id
)
SELECT 
    lm.system_id,
    lm.avg_cpu_percent as current_cpu,
    lm.stddev_cpu_percent as current_variance,
    b.baseline_mean,
    b.baseline_stddev,
    t.cpu_slope as trend_slope
FROM latest_metrics lm
LEFT JOIN baselines b USING(system_id)
LEFT JOIN trends t USING(system_id);
```

---

## Best Practices

### ✅ DO

- Compute CFRS in application layer (Python, R, etc.)
- Use `STDDEV` metrics directly from aggregates
- Store baselines in `system_baselines` table
- Use views for batch-friendly queries
- Document baseline computation methodology
- Version baselines (keep `is_active=FALSE` for old ones)

### ❌ DON'T

- Compute CFRS inside SQL (too complex, not reproducible)
- Use hardcoded thresholds (e.g., `cpu > 80%`)
- Assume fixed sampling intervals
- Store CFRS scores in database (compute on-demand)
- Mix statistical methods (pick one approach consistently)

---

## Research Notes

- **Statistical Correctness:** All metrics use proper statistical functions (STDDEV, PERCENTILE)
- **Reproducibility:** Same queries always return same results for same time period
- **No ML in DB:** All ML/scoring happens in application layer
- **Batch-Friendly:** Views optimized for bulk export, not row-by-row
- **Flexibility:** No assumptions about CFRS weights or thresholds

---

## Files Modified

1. `database/setup_timescaledb.sql` - Added STDDEV, baselines table, trend views
2. `database/schema.sql` - Updated performance_summaries, added baselines, trend views
3. `database/CFRS_DATABASE_SUPPORT.md` - This documentation

---

## Questions?

For CFRS implementation details, see your research paper / methodology docs.

For database-specific questions:
- Variance: Use `stddev_*_percent` columns
- Deviation: Use `system_baselines` table for z-scores
- Trend: Use `v_daily_resource_trends` view for regression
