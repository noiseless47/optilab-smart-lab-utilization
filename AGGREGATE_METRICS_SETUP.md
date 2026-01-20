# Aggregate Metrics Setup Guide

## Overview
The system now supports both **Live Metrics** (real-time data) and **Aggregate Metrics** (historical summaries) with a toggle interface in the SystemDetail page.

## Features Implemented

### Frontend (SystemDetail.tsx)
- **Mode Toggle**: Switch between Live and Aggregate views
- **View Toggle**: In Live mode, switch between Graphs and Numeric displays
- **Live Metrics**:
  - Graphs View: All 13 metric charts with dynamic Y-axis
  - Numeric View: Card-based display with latest values
- **Aggregate Metrics**: Time-bucketed statistics (hourly/daily)

### Backend Updates

#### New Endpoint
```
GET /departments/:deptId/labs/:labId/:sysID/metrics/aggregate?type=hourly&limit=24
```

**Parameters:**
- `type`: 'hourly' or 'daily' (default: 'hourly')
- `limit`: Number of records to return (default: 24)

**Response:**
```json
[
  {
    "system_id": 1,
    "hour_bucket": "2026-01-20T06:00:00Z",
    "avg_cpu_percent": 25.5,
    "max_cpu_percent": 45.2,
    "p95_cpu_percent": 42.1,
    "avg_ram_percent": 35.8,
    "max_ram_percent": 50.3,
    "p95_ram_percent": 48.9,
    "total_disk_read_gb": 2.45,
    "total_disk_write_gb": 3.21,
    "metric_count": 60
  }
]
```

## Setup Instructions

### 1. Update Database Schema

Run the TimescaleDB aggregate update script:

```bash
psql -U your_user -d your_database -f database/update_timescale_aggregates.sql
```

Or manually execute the SQL in your database client.

### 2. Verify Continuous Aggregates

Check that the views were created:

```sql
SELECT view_name, materialized_only, compression_enabled
FROM timescaledb_information.continuous_aggregates
WHERE view_name LIKE '%performance_stats';
```

You should see:
- `hourly_performance_stats`
- `daily_performance_stats`

### 3. Check Refresh Policies

Verify the automatic refresh is configured:

```sql
SELECT job_id, application_name, schedule_interval
FROM timescaledb_information.job_stats
WHERE hypertable_name = 'metrics';
```

### 4. Manual Refresh (if needed)

If you want to immediately populate the aggregates:

```sql
CALL refresh_continuous_aggregate('hourly_performance_stats', NULL, NULL);
CALL refresh_continuous_aggregate('daily_performance_stats', NULL, NULL);
```

### 5. Restart Backend

```bash
cd backend
npm restart
# or
pm2 restart ecosystem.config.json
```

## How It Works

### TimescaleDB Continuous Aggregates

The system uses TimescaleDB's continuous aggregates feature:

1. **Hourly Aggregates**: 
   - Buckets data into 1-hour windows
   - Calculates avg, max, min, P95 for CPU/RAM
   - Sums disk read/write operations
   - Auto-refreshes every hour

2. **Daily Aggregates**:
   - Buckets data into 1-day windows
   - Includes utilization flags (under/over utilized)
   - Tracks high-usage periods
   - Auto-refreshes daily

### Data Flow

```
Metrics Collector → metrics table (TimescaleDB hypertable)
                          ↓
              Continuous Aggregates (auto-refresh)
                          ↓
         hourly_performance_stats / daily_performance_stats
                          ↓
              Backend API (/metrics/aggregate)
                          ↓
                    Frontend UI
```

## Usage Examples

### Frontend
Users can now:
1. Click **Live** tab to see real-time metrics
2. Toggle between **Graphs** (charts) and **Numeric** (cards)
3. Click **Aggregate** tab to see historical summaries
4. Aggregates show hourly statistics by default

### Backend API Calls

**Get hourly aggregates:**
```bash
curl http://localhost:8000/departments/1/labs/1/5/metrics/aggregate?type=hourly&limit=24
```

**Get daily aggregates:**
```bash
curl http://localhost:8000/departments/1/labs/1/5/metrics/aggregate?type=daily&limit=7
```

## Troubleshooting

### No aggregate data showing
1. Check if metrics exist: `SELECT COUNT(*) FROM metrics WHERE system_id = 1;`
2. Manually refresh aggregates (see step 4 above)
3. Check TimescaleDB jobs: `SELECT * FROM timescaledb_information.job_stats;`

### Aggregate refresh not working
```sql
-- Check job status
SELECT * FROM timescaledb_information.jobs WHERE hypertable_name = 'metrics';

-- Re-add refresh policy if needed
SELECT add_continuous_aggregate_policy('hourly_performance_stats',
    start_offset => INTERVAL '3 hours',
    end_offset => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists => TRUE);
```

### Backend errors
- Check `npm logs` or `pm2 logs`
- Verify database connection in `backend/src/models/db.js`
- Test query manually in psql to verify column names

## Performance Notes

- Continuous aggregates are **much faster** than querying raw metrics
- Hourly aggregates refresh every hour (low overhead)
- Daily aggregates refresh once per day
- Old raw metrics can be compressed/deleted while keeping aggregates
- Queries on aggregates use indexes and are optimized by TimescaleDB

## Future Enhancements

Possible additions:
- Weekly/monthly aggregates for long-term trends
- Custom time range selection in UI
- Export aggregate data to CSV
- Comparison view (compare multiple time periods)
- Alert thresholds based on aggregates

## Files Modified

### Frontend
- `frontend/src/pages/SystemDetail.tsx`

### Backend
- `backend/src/routes/departments/deptID/labs/labID/sysID/sysID.routes.js`
- `backend/src/models/metrics_models.js`

### Database
- `database/timescale_setup.sql` (updated)
- `database/update_timescale_aggregates.sql` (new)
