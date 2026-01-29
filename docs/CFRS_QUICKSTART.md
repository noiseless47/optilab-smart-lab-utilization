# CFRS Quick Start Guide

## What is CFRS?

The **Composite Fault Risk Score (CFRS)** is a sophisticated risk ranking system that combines three statistical components to quantify operational degradation in computing systems:

- **Deviation (40%)**: How far current behavior deviates from normal baseline
- **Variance (30%)**: System instability and erratic behavior
- **Trend (30%)**: Long-term degradation patterns

**CFRS is a relative ranking score** - higher scores indicate higher risk of operational issues.

---

## Prerequisites

✅ System must have at least **30 days** of collected metrics  
✅ TimescaleDB continuous aggregates must be active  
✅ Metrics collection must be running consistently  

---

## Getting Started (3 Steps)

### Step 1: Verify Data Availability

Check that your system has sufficient data:

```sql
-- Check hourly aggregates
SELECT COUNT(*) as hourly_records,
       MIN(hour_bucket) as earliest,
       MAX(hour_bucket) as latest
FROM cfrs_hourly_stats
WHERE system_id = YOUR_SYSTEM_ID;

-- Check daily aggregates
SELECT COUNT(*) as daily_records
FROM cfrs_daily_stats
WHERE system_id = YOUR_SYSTEM_ID;
```

**Requirements**:
- Hourly records: ≥ 720 (30 days × 24 hours)
- Daily records: ≥ 30

### Step 2: Compute Baselines

Baselines define "normal" behavior for each metric. Compute once per system:

**Using API:**
```bash
curl -X POST http://localhost:3000/systems/YOUR_SYSTEM_ID/cfrs/baselines/compute \
  -H "Content-Type: application/json" \
  -d '{"windowDays": 30}'
```

**Using Frontend:**
1. Navigate to System Detail page
2. Click **CFRS** tab
3. Click **Compute Baselines** button

**Expected Response:**
```json
{
  "message": "Baselines computation completed",
  "system_id": 45,
  "computed": 11,
  "total": 11,
  "results": [ /* 11 baseline entries */ ],
  "errors": []
}
```

### Step 3: View CFRS Score

**Using API:**
```bash
curl http://localhost:3000/systems/YOUR_SYSTEM_ID/cfrs/score
```

**Using Frontend:**
1. Navigate to System Detail page
2. Click **CFRS** tab
3. View comprehensive CFRS analysis with:
   - Overall risk score and level
   - Component breakdown (D, V, S)
   - Per-metric details
   - Trend analysis with R² scores

---

## Understanding Your CFRS Score

### Risk Levels

| Score Range | Risk Level | Color  | Meaning |
|-------------|------------|--------|---------|
| < 1.0       | **Low**    | 🟢 Green | System operating normally |
| 1.0 - 2.0   | **Medium** | 🟡 Yellow | Minor deviations detected |
| 2.0 - 3.0   | **High**   | 🟠 Orange | Significant abnormalities |
| ≥ 3.0       | **Critical** | 🔴 Red | Severe degradation risk |

### Component Interpretation

#### Deviation Component (D)
- **What it measures**: Short-term abnormality from baseline
- **High scores mean**: Current metrics significantly differ from normal
- **Example**: CPU I/O wait suddenly increased from 5% to 20%

#### Variance Component (V)
- **What it measures**: Instability and unpredictability
- **High scores mean**: Metrics fluctuating erratically
- **Example**: RAM usage swinging wildly between 30% and 90%

#### Trend Component (S)
- **What it measures**: Long-term degradation patterns
- **High scores mean**: Metrics steadily worsening over time
- **Example**: Swap rate gradually increasing over 30 days

---

## Common Use Cases

### 1. Proactive Maintenance

Identify systems needing attention before failures occur:

```bash
# Get CFRS for all systems in a department
curl -X POST http://localhost:3000/systems/cfrs/batch \
  -H "Content-Type: application/json" \
  -d '{
    "systemIds": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  }' | jq '.results | sort_by(.cfrs_score) | reverse | .[:3]'
```

This returns the **top 3 highest risk systems** for prioritized maintenance.

### 2. Capacity Planning

Track CFRS trends across lab systems to identify capacity constraints:

```sql
-- Systems with high trend component (long-term degradation)
SELECT system_id, cfrs_score, 
       components->'trend'->>'score' as trend_score
FROM cfrs_scores_history  -- if you implement historical tracking
WHERE trend_score > 2.0
ORDER BY trend_score DESC;
```

### 3. Workload Impact Assessment

Compare CFRS before and after workload changes:

```bash
# Baseline before change
curl http://localhost:3000/systems/45/cfrs/score > before.json

# ... make workload changes ...

# Compare after 24 hours
curl http://localhost:3000/systems/45/cfrs/score > after.json
```

---

## Best Practices

### ✅ DO

1. **Recompute baselines quarterly** or after major system changes
   ```bash
   curl -X POST http://localhost:3000/systems/45/cfrs/baselines/compute
   ```

2. **Monitor all three components**, not just the total score
   - High Deviation + Low Variance = Sudden change
   - Low Deviation + High Variance = Instability
   - Low D & V + High Trend = Gradual degradation

3. **Use batch processing** for department-wide analysis
   ```javascript
   const systems = await api.get('/departments/1/systems');
   const systemIds = systems.data.map(s => s.system_id);
   const cfrsResults = await api.post('/systems/cfrs/batch', { systemIds });
   ```

4. **Check R² scores** in trend component for reliability
   - R² > 0.7: Strong linear trend (reliable)
   - R² < 0.3: Weak trend (interpret cautiously)

### ❌ DON'T

1. **Don't treat CFRS as absolute failure predictor**  
   ⚠️ CFRS is a relative risk ranking, not a probability

2. **Don't compare CFRS across different institutions**  
   ⚠️ Baselines are institution-specific

3. **Don't use CFRS for real-time alerting**  
   ⚠️ CFRS updates hourly; use raw metrics for immediate alerts

4. **Don't ignore context**  
   ⚠️ High CFRS during exam week may be normal workload intensification

---

## Troubleshooting

### Problem: "No baselines available"

**Solution:**
```bash
curl -X POST http://localhost:3000/systems/45/cfrs/baselines/compute
```

### Problem: "Insufficient samples for baseline"

**Causes:**
- System added recently (< 30 days)
- Sparse metrics collection
- TimescaleDB not refreshing

**Solutions:**
```bash
# Option 1: Use shorter baseline window
curl -X POST http://localhost:3000/systems/45/cfrs/baselines/compute \
  -d '{"windowDays": 14}'

# Option 2: Force aggregate refresh (run in PostgreSQL)
CALL refresh_continuous_aggregate('cfrs_hourly_stats', NULL, NULL);
```

### Problem: "Insufficient days for trend analysis"

**Cause:** Less than 20 days of data

**Solution:**
```bash
# Use shorter trend window
curl "http://localhost:3000/systems/45/cfrs/score?trendWindow=14"
```

### Problem: High CFRS but system seems normal

**Investigation Steps:**

1. **Check component breakdown:**
   ```bash
   curl http://localhost:3000/systems/45/cfrs/score | jq '.components'
   ```

2. **Inspect per-metric scores:**
   - Which specific metrics are elevated?
   - Are they all elevated or just one?

3. **Review baseline age:**
   ```bash
   curl http://localhost:3000/systems/45/cfrs/baselines | jq '.[].computed_at'
   ```
   
   If baselines are > 90 days old, recompute them.

4. **Check recent changes:**
   - New software installations?
   - Workload changes?
   - Hardware upgrades?

---

## Advanced Configuration

### Custom Component Weights

Emphasize different aspects based on your priorities:

```javascript
// Emphasize long-term trends for aging infrastructure
await api.put('/systems/cfrs/config', {
  weights: {
    deviation: 0.30,
    variance: 0.25,
    trend: 0.45  // Increased from default 0.30
  }
});
```

### MAD-Based Deviation (Robust to Outliers)

```bash
curl "http://localhost:3000/systems/45/cfrs/score?useMAD=true"
```

**Use when:**
- Baseline period had occasional extreme values
- More conservative risk assessment desired
- Metrics with heavy-tailed distributions

---

## API Reference Summary

### Baselines
```
POST   /systems/:systemId/cfrs/baseline/:metricName
POST   /systems/:systemId/cfrs/baselines/compute
GET    /systems/:systemId/cfrs/baseline/:metricName
GET    /systems/:systemId/cfrs/baselines
```

### CFRS Scores
```
GET    /systems/:systemId/cfrs/score
POST   /systems/cfrs/batch
```

### Configuration
```
GET    /systems/cfrs/config
PUT    /systems/cfrs/config
```

---

## Example Workflow: New System Setup

```bash
# 1. Wait for 30 days of data collection
# (Monitor with: SELECT COUNT(*) FROM cfrs_hourly_stats WHERE system_id = X)

# 2. Compute baselines
curl -X POST http://localhost:3000/systems/45/cfrs/baselines/compute

# 3. Get initial CFRS
curl http://localhost:3000/systems/45/cfrs/score

# 4. Schedule weekly CFRS checks
# (Add to cron or monitoring system)

# 5. Recompute baselines every quarter
# (Add to maintenance schedule)
```

---

## Metrics Reference

### Tier-1 Metrics (Primary Risk Drivers)
These have the strongest correlation with system degradation:

1. **cpu_iowait_percent** - CPU time waiting for I/O (storage bottlenecks)
2. **context_switch_rate** - Context switches/sec (scheduler stress)
3. **swap_out_rate** - Memory pages swapped out/sec (memory pressure)
4. **major_page_fault_rate** - Major page faults/sec (storage latency)
5. **cpu_temperature** - CPU thermal stress
6. **gpu_temperature** - GPU thermal stress

### Tier-2 Metrics (Secondary Indicators)
Provide context but are workload-dependent:

1. **cpu_percent** - CPU utilization
2. **ram_percent** - Memory utilization
3. **disk_percent** - Disk space usage
4. **swap_in_rate** - Memory pages swapped in/sec
5. **page_fault_rate** - Minor page faults/sec

---

## Next Steps

1. ✅ **Set up baselines** for all active systems
2. ✅ **Create weekly CFRS reports** for department heads
3. ✅ **Integrate CFRS** into maintenance prioritization workflow
4. ✅ **Monitor CFRS trends** to identify systemic issues
5. ✅ **Document CFRS patterns** in your environment

---

## Need Help?

- **Full Documentation**: [CFRS_IMPLEMENTATION.md](./CFRS_IMPLEMENTATION.md)
- **Technical Specification**: [CFRS_TECHNICAL_DEFINITION.md](./CFRS_TECHNICAL_DEFINITION.md)
- **Database Layer**: [CFRS_TIMESCALEDB_DOCUMENTATION.md](../database/CFRS_TIMESCALEDB_DOCUMENTATION.md)

---

**Quick Start Version**: 1.0.0  
**Last Updated**: January 29, 2026
