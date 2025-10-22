# Database Design Documentation
## Smart Resource Utilization & Hardware Optimization System

---

## 📊 Entity-Relationship Overview

The database follows a **star schema** pattern optimized for time-series analytics, with `usage_metrics` as the central fact table and `systems`, `users`, and reference tables as dimensions.

```
┌─────────────┐
│   systems   │─────┐
└─────────────┘     │
                    ▼
┌─────────────┐   ┌──────────────────┐   ┌─────────────┐
│    users    │──→│  usage_metrics   │←──│ alert_rules │
└─────────────┘   └──────────────────┘   └─────────────┘
                    │       │       │
         ┌──────────┘       │       └─────────────┐
         ▼                  ▼                     ▼
┌──────────────────┐  ┌─────────────┐   ┌──────────────┐
│ user_sessions    │  │alert_logs   │   │ process_     │
└──────────────────┘  └─────────────┘   │ snapshots    │
                                        └──────────────┘
         │                  │
         └────────┬─────────┘
                  ▼
      ┌──────────────────────┐
      │ performance_summaries│
      └──────────────────────┘
                  │
                  ▼
      ┌──────────────────────┐
      │ optimization_reports │
      └──────────────────────┘
```

---

## 🗂️ Core Tables

### 1. `systems`
**Purpose**: Master table for lab machine hardware specifications

**Key Columns**:
- `system_id` (UUID, PK): Unique system identifier
- `hostname` (VARCHAR, UNIQUE): Machine hostname
- `cpu_cores`, `ram_total_gb`, `gpu_model`: Hardware specs
- `status`: System status (active, maintenance, retired, offline)
- `last_seen`: Last metric collection timestamp

**Indexes**:
- Primary: `system_id`
- Secondary: `hostname`, `status`, `location`, `last_seen`

**Relationships**:
- **1:N** with `usage_metrics`
- **1:N** with `user_sessions`
- **1:N** with `performance_summaries`

**Design Rationale**:
- UUID primary key for distributed system compatibility
- Denormalized hardware specs for fast lookup without joins
- `last_seen` enables offline system detection

---

### 2. `usage_metrics` (Hypertable)
**Purpose**: Time-series storage of system performance metrics

**Key Columns**:
- `system_id` (UUID, FK → systems)
- `timestamp` (TIMESTAMPTZ): Metric collection time
- CPU metrics: `cpu_percent`, `cpu_per_core`, `cpu_temp`
- RAM metrics: `ram_percent`, `swap_percent`
- GPU metrics: `gpu_utilization`, `gpu_temp`
- Disk metrics: `disk_read_mb_s`, `disk_io_wait_percent`
- Network metrics: `net_sent_mb_s`, `net_recv_mb_s`

**Primary Key**: Composite `(system_id, timestamp)`

**Indexes**:
- `(system_id, timestamp DESC)` - System-specific queries
- `(timestamp DESC)` - Global time-range queries
- Partial indexes on high-usage conditions (CPU > 80%, RAM > 80%)

**TimescaleDB Optimization**:
- **Hypertable** with 1-day chunks
- **Compression** after 7 days (segmented by `system_id`)
- **Retention policy**: 1 year automatic deletion

**Design Rationale**:
- Optimized for **high-frequency inserts** (every 5 minutes per system)
- Composite PK prevents duplicate timestamps per system
- JSONB `cpu_per_core` allows flexible per-core analysis
- TimescaleDB compression reduces storage by 90%+

---

### 3. `performance_summaries`
**Purpose**: Pre-aggregated performance statistics by time period

**Key Columns**:
- `system_id` (UUID, FK)
- `period_type`: hourly, daily, weekly, monthly
- `period_start`, `period_end`: Time window
- Aggregates: `avg_cpu_percent`, `p95_cpu_percent`, `max_ram_percent`
- Flags: `is_underutilized`, `is_overutilized`, `has_bottleneck`
- `utilization_score`: Composite efficiency metric (0-100)

**Unique Constraint**: `(system_id, period_type, period_start)`

**Design Rationale**:
- **Materialized aggregations** avoid repeated expensive calculations
- Flags enable instant filtering without WHERE clause computations
- Supports **roll-up queries** (hourly → daily → monthly)
- Updated via stored procedures or TimescaleDB continuous aggregates

---

### 4. `user_sessions`
**Purpose**: Track user login sessions and activity patterns

**Key Columns**:
- `session_id` (UUID, PK)
- `user_id` (FK → users), `system_id` (FK → systems)
- `login_time`, `logout_time`
- `session_duration_minutes`: Auto-calculated generated column
- `active_processes`: JSONB array of major processes
- `peak_cpu_usage`, `peak_ram_usage`: Session maximums

**Indexes**:
- `(user_id)`, `(system_id)`, `(login_time DESC)`
- Partial index on `is_active = TRUE`

**Design Rationale**:
- Links resource usage to **user behavior**
- JSONB `active_processes` supports flexible process tracking
- Generated column for `session_duration` ensures consistency

---

### 5. `alert_logs`
**Purpose**: Record of triggered alerts and anomalies

**Key Columns**:
- `alert_id` (BIGSERIAL, PK)
- `rule_id` (FK → alert_rules)
- `system_id` (FK → systems)
- `triggered_at`, `resolved_at`: Alert lifecycle
- `metric_name`, `actual_value`, `threshold_value`
- `is_acknowledged`, `acknowledged_by`

**Indexes**:
- `(triggered_at DESC)`, `(system_id, triggered_at DESC)`
- Partial index on `resolved_at IS NULL` (active alerts)

**Design Rationale**:
- Tracks **alert lifecycle** from trigger to resolution
- Enables **MTTR** (Mean Time To Resolution) analysis
- Acknowledgement tracking for operational accountability

---

### 6. `optimization_reports`
**Purpose**: Store generated hardware recommendations

**Key Columns**:
- `report_id` (UUID, PK)
- `system_id` (FK → systems)
- `report_type`: hardware_upgrade, reallocation, configuration
- `severity`: low, medium, high, critical
- `recommendations`: JSONB structured suggestions
- `priority_score`: 1-10 ranking
- `status`: pending, approved, implemented, rejected

**Indexes**:
- `(status)`, `(severity)`, `(created_at DESC)`
- GIN index on `recommendations` JSONB

**Design Rationale**:
- **JSONB recommendations** allow flexible, structured advice
- Status tracking enables **workflow management**
- Historical record of optimization decisions

---

## 🔗 Relationships & Constraints

### Foreign Key Relationships

| Child Table | Parent Table | Cascade Rule |
|------------|-------------|--------------|
| usage_metrics | systems | ON DELETE CASCADE |
| user_sessions | systems | ON DELETE CASCADE |
| user_sessions | users | ON DELETE SET NULL |
| alert_logs | systems | ON DELETE CASCADE |
| alert_logs | alert_rules | ON DELETE SET NULL |
| optimization_reports | systems | ON DELETE SET NULL |

**Design Decision**: 
- `ON DELETE CASCADE` for metrics/logs (disposable data)
- `ON DELETE SET NULL` for reports (preserve history)

---

## 📈 Time-Series Optimization (TimescaleDB)

### Hypertables

1. **usage_metrics**: Partitioned by `timestamp` (1-day chunks)
2. **alert_logs**: Partitioned by `triggered_at` (7-day chunks)
3. **process_snapshots**: Partitioned by `timestamp` (1-day chunks)

### Continuous Aggregates

**hourly_performance_stats**:
```sql
SELECT
    time_bucket('1 hour', timestamp),
    system_id,
    AVG(cpu_percent), MAX(cpu_percent),
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_percent)
FROM usage_metrics
GROUP BY time_bucket, system_id;
```

**Refresh Policy**: Every 1 hour, covering last 2 hours

**Benefits**:
- **50-100x faster** aggregate queries
- Automatic materialization & refresh
- Compression-compatible

---

## 🔍 Indexes Strategy

### Index Types Used

1. **B-tree** (default): Equality & range queries
   - `(system_id, timestamp DESC)` on usage_metrics
   
2. **GIN (Generalized Inverted Index)**: JSONB & full-text search
   - `cpu_per_core` JSONB in usage_metrics
   - `recommendations` JSONB in optimization_reports
   
3. **Partial Indexes**: Filtered subsets
   - `WHERE cpu_percent > 80` (high-usage queries)
   - `WHERE is_active = TRUE` (active sessions)
   
4. **BRIN (Block Range Indexes)**: Large sequential data
   - Optional for archived `usage_metrics` (>1M rows)

### Index Maintenance

```sql
-- Automated via stored procedures
REINDEX TABLE usage_metrics;
ANALYZE usage_metrics;
```

**Recommendation**: Run weekly during maintenance window

---

## ⚙️ Stored Procedures & Functions

### Analytical Functions

| Function | Purpose | Returns |
|----------|---------|---------|
| `calculate_utilization_score()` | Compute efficiency score (0-100) | NUMERIC |
| `detect_bottleneck()` | Identify bottleneck type | TEXT |
| `generate_hardware_recommendations()` | Generate upgrade suggestions | TABLE |
| `get_top_resource_consumers()` | Top N systems by metric | TABLE |

### Maintenance Procedures

| Procedure | Purpose | Frequency |
|-----------|---------|-----------|
| `generate_daily_summary()` | Create daily performance summary | Daily (1 AM) |
| `create_optimization_report()` | Generate recommendations | Weekly |

---

## 🔐 Security & Permissions

### Role-Based Access Control

**Roles**:
1. `admin` - Full access
2. `data_collector` - INSERT on metrics, SELECT on systems
3. `dashboard_readonly` - SELECT only
4. `analyst` - SELECT + stored procedure execution

**Example Grants**:
```sql
-- Data collector (for agents)
GRANT INSERT ON usage_metrics, user_sessions TO data_collector;
GRANT SELECT ON systems TO data_collector;

-- Dashboard (Grafana)
GRANT SELECT ON ALL TABLES IN SCHEMA public TO dashboard_readonly;
```

---

## 📏 Data Volume Estimates

**Assumptions**:
- 50 lab systems
- 5-minute collection interval
- 1 year retention

| Table | Rows/Day | Rows/Year | Est. Size/Year |
|-------|----------|-----------|----------------|
| usage_metrics | 14,400 | 5.26M | ~5 GB (compressed: ~500 MB) |
| alert_logs | ~500 | 182K | ~50 MB |
| performance_summaries | 50 | 18K | ~10 MB |

**Total**: ~6 GB raw, ~1 GB with compression

---

## 🛠️ Design Patterns Applied

1. **Star Schema**: usage_metrics as fact table, systems/users as dimensions
2. **Slowly Changing Dimensions (SCD)**: System specs updated, not historized
3. **Generated Columns**: `session_duration_minutes` auto-calculated
4. **Temporal Tables**: Time-series with TimescaleDB optimization
5. **Materialized Views**: Continuous aggregates for performance
6. **Trigger-Based ETL**: Auto-update last_seen, generate alerts

---

## 🔄 Data Lifecycle

```
┌─────────────┐
│ Collection  │ (Every 5 min)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Insert    │ → usage_metrics (raw)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Aggregate  │ → hourly/daily summaries (1 hour/day)
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Compress   │ → Compress chunks >7 days old
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Archive   │ → Delete data >1 year old
└─────────────┘
```

---

## 📚 Advanced Features

### Anomaly Detection
- **Statistical**: Z-score deviation from 30-day baseline
- **Rule-based**: Threshold violations (alert_rules)
- **Trend-based**: Sudden spikes via percentile comparison

### Predictive Capabilities
- **Linear regression** on daily summaries for capacity planning
- **Seasonal decomposition** for usage pattern analysis
- Future: ML models for failure prediction

---

## 🎯 Performance Tuning

### PostgreSQL Configuration

```ini
# postgresql.conf recommendations
shared_buffers = 4GB            # 25% of RAM
effective_cache_size = 12GB     # 75% of RAM
work_mem = 32MB
maintenance_work_mem = 512MB

# TimescaleDB
timescaledb.max_background_workers = 8
max_worker_processes = 16
```

### Query Optimization Tips

1. **Use indexes**: Query planner prefers indexed columns
2. **EXPLAIN ANALYZE**: Always check query plans
3. **Continuous aggregates**: Prefer over manual GROUP BY on large datasets
4. **Partition pruning**: Query specific time ranges
5. **Connection pooling**: Use PgBouncer for high-concurrency

---

## 📖 References

- **PostgreSQL Documentation**: https://www.postgresql.org/docs/
- **TimescaleDB Best Practices**: https://docs.timescale.com/timescaledb/latest/how-to-guides/
- **Database Design Patterns**: Martin Fowler's "Patterns of Enterprise Application Architecture"

---

**Document Version**: 1.0  
**Last Updated**: October 21, 2025  
**Author**: DBMS Project Team
