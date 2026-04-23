# Composite Fault Risk Score (CFRS)
## Technical Implementation Documentation v1.0

## Table of Contents
1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Database Layer](#database-layer)
4. [Backend Implementation](#backend-implementation)
5. [API Endpoints](#api-endpoints)
6. [Frontend Integration](#frontend-integration)
7. [Usage Guide](#usage-guide)
8. [Configuration](#configuration)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The Composite Fault Risk Score (CFRS) is a sophisticated risk ranking system designed to quantify early operational degradation and instability in shared computing systems. CFRS combines three orthogonal statistical components to provide a comprehensive risk assessment.

### Key Characteristics
- **Relative Risk Ranking**: CFRS is a comparative score, not an absolute predictor
- **Threshold-Free**: No arbitrary thresholds; uses statistical deviation analysis
- **Multi-Component**: Combines deviation, variance, and trend analysis
- **Scientifically Grounded**: Based on proven statistical methods suitable for academic publication

### CFRS Formula
```
CFRS = (w_D × D) + (w_V × V) + (w_S × S)
```

Where:
- **D** (Deviation): Short-term abnormality from baseline (default: 40%)
- **V** (Variance): Instability/unpredictability (default: 30%)
- **S** (Trend): Long-term degradation (default: 30%)

---

## Architecture

### System Components

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend Layer                        │
│  ┌──────────────────┐  ┌──────────────────────────────────┐ │
│  │ CFRSScoreDisplay │  │    CFRSMetricsViewer             │ │
│  │  - Score Display │  │    - Raw Metrics Display         │ │
│  │  - Component     │  │    - Hourly Aggregates           │ │
│  │    Breakdown     │  │                                   │ │
│  └──────────────────┘  └──────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                        Backend Layer                         │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              CFRSModel (cfrs_models.js)               │  │
│  │                                                         │  │
│  │  ┌─────────────────┐  ┌──────────────────────────┐   │  │
│  │  │ Baseline Mgmt   │  │ CFRS Computation         │   │  │
│  │  │ - Compute       │  │ - Deviation Component    │   │  │
│  │  │ - Store         │  │ - Variance Component     │   │  │
│  │  │ - Retrieve      │  │ - Trend Component        │   │  │
│  │  └─────────────────┘  └──────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Database Layer (PostgreSQL + TimescaleDB) │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ Continuous       │  │ Baseline Storage              │   │
│  │ Aggregates       │  │                               │   │
│  │ - Hourly Stats   │  │ cfrs_system_baselines         │   │
│  │ - Daily Stats    │  │ - Mean, Stddev, MAD           │   │
│  │                  │  │ - Per system, per metric      │   │
│  └──────────────────┘  └──────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## Database Layer

### Tables and Views

#### 1. `cfrs_hourly_stats` (Continuous Aggregate)
**Purpose**: Provides hourly statistical derivatives for Deviation and Variance components

**Key Columns** (per metric):
- `avg_{metric}`: Hourly average
- `stddev_{metric}`: Standard deviation (for Variance component)
- `p95_{metric}`: 95th percentile
- `cnt_{metric}`: Sample count (data quality indicator)

**Metrics Tracked**:
- **Tier-1** (Primary drivers): cpu_iowait, context_switch, swap_out, major_page_faults, cpu_temp, gpu_temp
- **Tier-2** (Secondary): cpu_percent, ram_percent, disk_percent, swap_in, page_faults

**Refresh Policy**: Every 1 hour, covering last 3 hours

#### 2. `cfrs_daily_stats` (Continuous Aggregate)
**Purpose**: Provides daily aggregates for Trend component (slope computation)

**Key Columns**:
- `day_bucket`: Date bucket
- `avg_{metric}`: Daily average (used in linear regression)
- `stddev_{metric}`: Daily standard deviation
- `cnt_{metric}`: Sample count

**Refresh Policy**: Daily, covering last 3 days

#### 3. `cfrs_system_baselines` (Table)
**Purpose**: Stores baseline statistics for Deviation computation

**Schema**:
```sql
CREATE TABLE cfrs_system_baselines (
    baseline_id SERIAL PRIMARY KEY,
    system_id INT NOT NULL,
    metric_name VARCHAR(50) NOT NULL,
    baseline_mean NUMERIC(12,4) NOT NULL,
    baseline_stddev NUMERIC(12,4),
    baseline_mad NUMERIC(12,4),          -- Median Absolute Deviation
    baseline_median NUMERIC(12,4),
    baseline_window_days INT NOT NULL,   -- Baseline period length
    baseline_start TIMESTAMPTZ NOT NULL,
    baseline_end TIMESTAMPTZ NOT NULL,
    sample_count INT NOT NULL,
    computed_at TIMESTAMPTZ DEFAULT NOW(),
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT
);
```

**Indexes**:
- `idx_cfrs_baselines_system_metric` on (system_id, metric_name, is_active)
- `idx_cfrs_baselines_active` on (is_active)
- `idx_cfrs_baselines_computed` on (computed_at DESC)

---

## Backend Implementation

### CFRSModel Class (`backend/src/models/cfrs_models.js`)

#### Configuration
```javascript
{
  weights: {
    deviation: 0.40,  // 40%
    variance: 0.30,   // 30%
    trend: 0.30       // 30%
  },
  tier1Metrics: [
    'cpu_iowait', 'context_switch', 'swap_out',
    'major_page_faults', 'cpu_temp', 'gpu_temp'
  ],
  tier2Metrics: [
    'cpu_percent', 'ram_percent', 'disk_percent',
    'swap_in', 'page_faults'
  ],
  metricWeights: {
    deviation: { tier1: 0.70, tier2: 0.30 },
    variance: { tier1: 0.70, tier2: 0.30 },
    trend: { tier1: 1.0, tier2: 0.0 }  // Only Tier-1 for trend
  },
  trendWindow: 30,           // Days for trend analysis
  minTrendDays: 20,          // Minimum days for reliable trend
  baselineWindow: 30,        // Days for baseline computation
  minBaselineSamples: 100    // Minimum samples for reliable baseline
}
```

#### Key Methods

##### 1. Baseline Management

**`computeBaseline(systemId, metricName, windowDays)`**
- Computes baseline statistics from hourly aggregates
- Returns: mean, stddev, median, MAD, sample count
- Validates minimum sample requirement

**`storeBaseline(baselineStats, notes)`**
- Stores or updates baseline in database
- Handles conflicts via upsert

**`computeAllBaselines(systemId, windowDays)`**
- Computes baselines for all 11 metrics
- Returns success/error breakdown

**`getBaseline(systemId, metricName)`**
- Retrieves active baseline for a metric

##### 2. Component Computation

**`computeDeviation(currentStats, baselines, useMAD)`**
- Computes z-scores: `D_m = |x_m - μ_m| / σ_m`
- Alternative MAD-based: `D_m = |x_m - median_m| / MAD_m`
- Returns deviation scores for all metrics

**`computeVariance(currentStats)`**
- Computes Coefficient of Variation: `V_m = σ_m / (μ_m + ε)`
- Measures instability/volatility
- Returns variance scores for all metrics

**`computeTrend(systemId, windowDays)`**
- Computes linear regression slopes from daily aggregates
- Uses PostgreSQL `REGR_SLOPE()` function
- Returns slopes (per day) and R² values
- Positive slope = degradation

##### 3. CFRS Computation

**`computeCFRS(systemId, options)`**

**Parameters**:
```javascript
{
  useMAD: false,           // Use MAD instead of stddev
  trendWindow: null,       // Days for trend (default: 30)
  customWeights: null      // Custom component weights
}
```

**Returns**:
```javascript
{
  system_id: number,
  cfrs_score: number,      // Final CFRS score
  computed_at: timestamp,
  components: {
    deviation: {
      score: number,
      weight: number,
      tier1: number,
      tier2: number,
      details: { /* per-metric deviations */ }
    },
    variance: { /* similar structure */ },
    trend: {
      score: number,
      weight: number,
      tier1: number,
      days_analyzed: number,
      details: { /* per-metric slopes */ },
      r2_scores: { /* goodness of fit */ }
    }
  },
  hour_bucket: timestamp,
  total_samples: number,
  baselines_used: number,
  config: { /* configuration used */ }
}
```

**Algorithm**:
```
1. Fetch latest hourly statistics
2. Retrieve all active baselines
3. Compute Deviation component:
   - Calculate z-scores for all metrics
   - Weighted average: Tier-1 (70%), Tier-2 (30%)
4. Compute Variance component:
   - Calculate CV for all metrics
   - Weighted average: Tier-1 (70%), Tier-2 (30%)
5. Compute Trend component:
   - Linear regression slopes for Tier-1 metrics (100%)
   - Normalize positive slopes
6. Final CFRS = w_D×D + w_V×V + w_S×S
```

---

## API Endpoints

### Baseline Management

#### Compute Baseline for a Metric
```http
POST /systems/:systemId/cfrs/baseline/:metricName
Content-Type: application/json

{
  "windowDays": 30,
  "notes": "Initial baseline computation"
}
```

**Response**:
```json
{
  "message": "Baseline computed and stored successfully",
  "baseline": {
    "baseline_id": 123,
    "system_id": 45,
    "metric_name": "cpu_iowait",
    "baseline_mean": 5.2345,
    "baseline_stddev": 1.2345,
    "baseline_median": 5.1234,
    "baseline_mad": 0.9876,
    "sample_count": 720,
    "baseline_window_days": 30,
    "computed_at": "2026-01-29T10:30:00Z"
  }
}
```

#### Compute All Baselines
```http
POST /systems/:systemId/cfrs/baselines/compute
Content-Type: application/json

{
  "windowDays": 30
}
```

**Response**:
```json
{
  "message": "Baselines computation completed",
  "system_id": 45,
  "computed": 11,
  "total": 11,
  "results": [ /* array of baselines */ ],
  "errors": []
}
```

#### Get Baseline for a Metric
```http
GET /systems/:systemId/cfrs/baseline/:metricName
```

#### Get All Baselines
```http
GET /systems/:systemId/cfrs/baselines
```

### CFRS Score Computation

#### Compute CFRS Score
```http
GET /systems/:systemId/cfrs/score?useMAD=false&trendWindow=30
```

**Query Parameters**:
- `useMAD` (boolean): Use MAD-based deviation (default: false)
- `trendWindow` (number): Days for trend analysis (default: 30)
- `weights` (JSON): Custom component weights

**Response**: See "CFRS Computation Returns" section above

#### Batch CFRS Computation
```http
POST /systems/cfrs/batch
Content-Type: application/json

{
  "systemIds": [1, 2, 3, 4, 5],
  "useMAD": false,
  "trendWindow": 30,
  "customWeights": null
}
```

**Response**:
```json
{
  "computed": 5,
  "total": 5,
  "results": [ /* array of CFRS scores */ ],
  "errors": []
}
```

### Configuration Management

#### Get CFRS Configuration
```http
GET /systems/cfrs/config
```

#### Update CFRS Configuration
```http
PUT /systems/cfrs/config
Content-Type: application/json

{
  "weights": {
    "deviation": 0.45,
    "variance": 0.30,
    "trend": 0.25
  },
  "trendWindow": 45
}
```

---

## Frontend Integration

### Components

#### 1. CFRSScoreDisplay
**Location**: `frontend/src/components/CFRSScoreDisplay.tsx`

**Props**:
```typescript
interface CFRSScoreDisplayProps {
  systemId: string
}
```

**Features**:
- Displays overall CFRS score with risk level (Low/Medium/High/Critical)
- Component breakdown with visualizations
- Detailed metric-level scores
- Active baselines summary
- Baseline computation interface
- Interpretation guide

**Risk Levels**:
- **Low**: CFRS < 1.0 (Green)
- **Medium**: 1.0 ≤ CFRS < 2.0 (Yellow)
- **High**: 2.0 ≤ CFRS < 3.0 (Orange)
- **Critical**: CFRS ≥ 3.0 (Red)

#### 2. Integration in SystemDetail
**Location**: `frontend/src/pages/SystemDetail.tsx`

**Usage**:
```tsx
{metricsMode === 'cfrs' && (
  <>
    <CFRSScoreDisplay systemId={systemId || ''} />
    <div className="mt-8">
      <h3 className="text-xl font-bold">CFRS Raw Metrics</h3>
      <CFRSMetricsViewer systemId={systemId || ''} />
    </div>
  </>
)}
```

---

## Usage Guide

### Step-by-Step CFRS Setup

#### 1. Ensure TimescaleDB Aggregates are Active
```sql
-- Check continuous aggregate status
SELECT view_name, refresh_lag, last_run_duration
FROM timescaledb_information.continuous_aggregate_stats
WHERE view_name LIKE 'cfrs_%';
```

#### 2. Compute Baselines (One-time Setup)
```bash
# For a specific system
curl -X POST http://localhost:3000/systems/45/cfrs/baselines/compute \
  -H "Content-Type: application/json" \
  -d '{"windowDays": 30}'
```

**Best Practices**:
- Use 30-day baseline window for production systems
- Recompute baselines quarterly or after major changes
- Require minimum 100 samples per metric

#### 3. Compute CFRS Score
```bash
# Standard z-score based
curl http://localhost:3000/systems/45/cfrs/score

# MAD-based (more robust to outliers)
curl "http://localhost:3000/systems/45/cfrs/score?useMAD=true"

# Custom trend window
curl "http://localhost:3000/systems/45/cfrs/score?trendWindow=45"
```

#### 4. View in Frontend
1. Navigate to System Detail page
2. Click "CFRS" tab in metrics mode selector
3. View comprehensive CFRS analysis

### Batch Processing

For department-wide analysis:
```javascript
const systemIds = [1, 2, 3, 4, 5];
const response = await api.post('/systems/cfrs/batch', {
  systemIds,
  useMAD: false,
  trendWindow: 30
});

// Sort by CFRS score descending (highest risk first)
const rankedSystems = response.data.results
  .sort((a, b) => b.cfrs_score - a.cfrs_score);
```

---

## Configuration

### Customizing Component Weights

Example: Emphasize trend analysis for aging infrastructure
```javascript
await api.put('/systems/cfrs/config', {
  weights: {
    deviation: 0.30,
    variance: 0.25,
    trend: 0.45  // Increased emphasis on long-term degradation
  }
});
```

**Constraint**: Weights must sum to 1.0

### Adjusting Metric Tier Weights

Edit `backend/src/models/cfrs_models.js`:
```javascript
metricWeights: {
  deviation: {
    tier1: 0.80,  // Increase Tier-1 emphasis
    tier2: 0.20
  },
  variance: {
    tier1: 0.80,
    tier2: 0.20
  },
  trend: {
    tier1: 1.0,
    tier2: 0.0
  }
}
```

### Baseline Window Configuration

```javascript
this.config = {
  baselineWindow: 45,        // Increase to 45 days
  minBaselineSamples: 200    // Require more samples
}
```

---

## Troubleshooting

### Issue: "No baselines available"
**Symptom**: CFRS computation fails with baseline error

**Solution**:
```bash
# Compute baselines
curl -X POST http://localhost:3000/systems/{systemId}/cfrs/baselines/compute
```

### Issue: "Insufficient samples for baseline"
**Symptom**: Baseline computation fails

**Causes**:
- System recently added (< 30 days of data)
- Sparse metrics collection
- TimescaleDB aggregates not refreshed

**Solutions**:
```sql
-- Force refresh continuous aggregates
CALL refresh_continuous_aggregate('cfrs_hourly_stats', NULL, NULL);
CALL refresh_continuous_aggregate('cfrs_daily_stats', NULL, NULL);
```

Or reduce baseline window:
```bash
curl -X POST http://localhost:3000/systems/45/cfrs/baselines/compute \
  -d '{"windowDays": 14}'
```

### Issue: "Insufficient days for trend analysis"
**Symptom**: Trend component computation fails

**Cause**: Less than 20 days of daily aggregates

**Solution**:
- Wait for more data accumulation
- Reduce `minTrendDays` in configuration
- Use shorter `trendWindow`

### Issue: High CFRS but system appears normal
**Analysis Steps**:
1. Check component breakdown (which component is elevated?)
2. Inspect per-metric scores
3. Review R² values for trend (low R² = unreliable trend)
4. Verify baseline is current (recompute if > 90 days old)
5. Check for recent workload changes

**Possible Causes**:
- Baseline computed during atypical usage period
- Legitimate workload intensification
- False positive from metric noise

---

## Metric Tier Classification

### Tier-1 Metrics (Primary CFRS Drivers)
These metrics are universally indicative of system stress and degradation:

1. **cpu_iowait_percent**: CPU time waiting for I/O (storage bottlenecks)
2. **context_switch_rate**: Context switches per second (scheduler stress)
3. **swap_out_rate**: Pages swapped out per second (memory pressure)
4. **major_page_fault_rate**: Major page faults (storage access latency)
5. **cpu_temperature**: CPU thermal stress
6. **gpu_temperature**: GPU thermal stress

**Weight Distribution**:
- Deviation: 70%
- Variance: 70%
- Trend: 100%

### Tier-2 Metrics (Secondary Contributors)
Workload-dependent metrics that provide context:

1. **cpu_percent**: CPU utilization
2. **ram_percent**: Memory utilization
3. **disk_percent**: Disk space utilization
4. **swap_in_rate**: Pages swapped in per second
5. **page_fault_rate**: Minor page faults

**Weight Distribution**:
- Deviation: 30%
- Variance: 30%
- Trend: 0%

---

## Mathematical Foundations

### Deviation Component (Z-Score)
```
D_m = |x_m - μ_m| / σ_m

where:
  x_m = current hourly average of metric m
  μ_m = baseline mean
  σ_m = baseline standard deviation
```

**Alternative (MAD-based)**:
```
D_m = |x_m - median_m| / MAD_m

where:
  MAD_m = Median Absolute Deviation (robust to outliers)
```

### Variance Component (Coefficient of Variation)
```
V_m = σ_m / (μ_m + ε)

where:
  σ_m = hourly standard deviation
  μ_m = hourly average
  ε = small constant (10^-6) to prevent division by zero
```

### Trend Component (Linear Regression Slope)
```
S_m = REGR_SLOPE(avg_m, day_epoch)

Computed over N-day rolling window (default: 30 days)
Positive slope indicates degradation
```

**Normalization**:
```
Normalized_Slope = max(0, raw_slope) × scaling_factor
```

### Final CFRS
```
CFRS = w_D × (0.7×D_tier1 + 0.3×D_tier2)
     + w_V × (0.7×V_tier1 + 0.3×V_tier2)
     + w_S × (1.0×S_tier1)

Default weights:
  w_D = 0.40
  w_V = 0.30
  w_S = 0.30
```

---

## Performance Considerations

### Database Query Optimization
- Continuous aggregates pre-compute statistics (minimal runtime overhead)
- Baseline retrieval uses indexed lookups
- Trend computation leverages PostgreSQL's native regression functions

### Caching Strategies
CFRS scores can be cached with TTL:
- Cache key: `cfrs:{system_id}:{config_hash}`
- TTL: 1 hour (aligns with hourly aggregates)
- Invalidate on config changes

### Batch Processing
For large deployments:
```javascript
// Process systems in chunks to avoid memory issues
const chunkSize = 50;
for (let i = 0; i < systemIds.length; i += chunkSize) {
  const chunk = systemIds.slice(i, i + chunkSize);
  await cfrsModel.computeBatchCFRS(chunk);
}
```

---

## Future Enhancements

### Planned Features
1. **Automated Baseline Refresh**: Scheduled recomputation of baselines
2. **Anomaly Detection**: Integrate with alerting system for critical CFRS
3. **Historical CFRS Tracking**: Store CFRS time series for trend analysis
4. **Comparative Analysis**: Department-wide CFRS rankings
5. **Machine Learning Integration**: Predictive maintenance based on CFRS patterns
6. **Custom Metric Weights**: Per-system metric weight profiles

### Research Opportunities
- Correlation analysis: CFRS vs. actual failure events
- Optimization: Adaptive component weights based on system type
- Validation: Statistical significance testing of CFRS predictions
- Extension: Multi-system CFRS (cluster-wide risk assessment)

---

## References

### Academic Foundations
1. Z-score normalization: Statistical Process Control literature
2. Coefficient of Variation: Reliability engineering metrics
3. Linear regression trends: Time series analysis in system monitoring

### Related Documentation
- [CFRS Technical Definition v1.0](./CFRS_TECHNICAL_DEFINITION.md)
- [TimescaleDB Layer Documentation](../database/CFRS_TIMESCALEDB_DOCUMENTATION.md)
- [Metrics Collection Guide](../collector/README.md)

---

## Changelog

### v1.0.0 (2026-01-29)
- Initial CFRS implementation
- Backend computation engine
- Database layer with TimescaleDB aggregates
- Frontend visualization components
- Comprehensive API endpoints
- Documentation

---

## Support

For questions or issues:
1. Check troubleshooting section
2. Review database aggregate status
3. Verify baseline coverage
4. Consult API response error messages

## License

[Project License]

---

**Document Version**: 1.0.0  
**Last Updated**: January 29, 2026  
**Maintainer**: CFRS Development Team
