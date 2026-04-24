# CFRS Metrics Viewer - Implementation Guide

## Overview
Added a comprehensive CFRS (Composite Fault Risk Score) metrics viewer to the OptiLab system. This allows real-time visualization and verification of all CFRS-relevant metrics.

## What Was Added

### Backend Changes

#### 1. New Model Methods (`backend/src/models/metrics_models.js`)
- `getCFRSMetrics(systemID, hours)` - Fetch raw CFRS metrics time-series
- `getCFRSHourlyStats(systemID, hours)` - Fetch CFRS hourly aggregates (if available)
- `getLatestCFRSMetrics(systemID)` - Fetch latest CFRS metrics
- `getCFRSMetricsSummary(systemID, hours)` - Comprehensive CFRS data summary

#### 2. New API Endpoints (`backend/src/routes/systems.routes.js`)
- `GET /api/systems/:systemId/metrics/cfrs?hours=24` - Raw CFRS metrics
- `GET /api/systems/:systemId/metrics/cfrs/hourly?hours=24` - Hourly aggregates
- `GET /api/systems/:systemId/metrics/cfrs/latest` - Latest values
- `GET /api/systems/:systemId/metrics/cfrs/summary?hours=24` - Complete summary

### Frontend Changes

#### 1. New Component (`frontend/src/components/CFRSMetricsViewer.tsx`)
A comprehensive React component that displays:
- **Latest Values Card** - Real-time readings for all CFRS metrics
- **Tier-1 Charts** - 6 primary CFRS drivers with trend graphs
- **Tier-2 Charts** - 5 secondary contributors with trend graphs
- **Time Range Selector** - 1h, 6h, 24h, 72h options
- **View Mode Selector** - Toggle between Tier-1, Tier-2, or All metrics

#### 2. Updated System Detail Page (`frontend/src/pages/SystemDetail.tsx`)
- Added "CFRS" tab alongside "Live" and "Aggregate" views
- Integrated CFRSMetricsViewer component
- Added Zap icon for CFRS mode

## Metrics Displayed

### Tier-1 (Primary CFRS Drivers)
1. **CPU I/O Wait %** - Storage/network bottleneck indicator
2. **Context Switch Rate** - System thrashing indicator (per second)
3. **Swap Out Rate** - Memory pressure critical (pages/sec)
4. **Major Page Fault Rate** - Storage latency spike (faults/sec)
5. **CPU Temperature** - Thermal stress indicator (°C)
6. **GPU Temperature** - GPU cooling degradation (°C)

### Tier-2 (Secondary Contributors)
1. **CPU %** - Overall CPU usage
2. **RAM %** - Memory utilization
3. **Disk %** - Storage usage
4. **Swap In Rate** - Memory reclaim activity (pages/sec)
5. **Page Fault Rate** - Memory access patterns (faults/sec)

## Usage

### Access CFRS Metrics
1. Navigate to any system detail page
2. Click the **CFRS** tab (with lightning bolt icon)
3. Select time range: 1h, 6h, 24h, or 72h
4. Toggle view mode: Tier-1, Tier-2, or All

### Interpret Metrics

#### Normal vs Critical Values
| Metric | Normal Range | Critical Threshold |
|--------|--------------|-------------------|
| CPU I/O Wait | 0-5% | >20% sustained |
| Context Switch | <10k/sec | >100k/sec |
| Swap Out Rate | 0 pages/sec | >100 pages/sec |
| Major Page Faults | 0-10/sec | >100/sec |
| CPU Temperature | 30-70°C | >85°C |
| GPU Temperature | 30-80°C | >90°C |

#### Status Indicators
- **N/A** - Metric not available (collector not running or sensor missing)
- **0** - No activity (normal for swap/page faults)
- **NULL** - Database has NULL value (expected for some metrics)

## Troubleshooting

### Issue: All Metrics Show "N/A"
**Cause:** Advanced metrics not being collected  
**Solution:**
1. Ensure `metrics_collector.sh` includes CFRS metric collection functions
2. Verify `combined_monitor.py` inserts CFRS columns
3. Check if metrics table has CFRS columns:
   ```sql
   SELECT column_name FROM information_schema.columns 
   WHERE table_name = 'metrics' AND column_name LIKE '%iowait%';
   ```
4. Run migration: `psql -d optilab_mvp -f database/add_cfrs_metrics.sql`

### Issue: "Error Loading CFRS Metrics"
**Cause:** API endpoint not accessible or database query failing  
**Solution:**
1. Check backend logs: `pm2 logs backend`
2. Test API endpoint: `curl http://localhost:3000/api/systems/1/metrics/cfrs/latest`
3. Verify database connection in backend
4. Check if metrics table exists: `psql -d optilab_mvp -c "\dt metrics"`

### Issue: Charts Not Rendering
**Cause:** Insufficient data points or Chart.js not loaded  
**Solution:**
1. Verify metrics exist: Click "Latest" tab first
2. Check browser console for Chart.js errors
3. Ensure Chart.js is properly imported in SystemDetail.tsx
4. Try different time range (increase hours)

### Issue: "No CFRS Metrics Available"
**Cause:** No data collected yet  
**Solution:**
1. Wait for collector to run (default: 5-minute intervals)
2. Manually trigger collection: `./collector/metrics_collector.sh`
3. Check collector logs: `tail -f /var/log/metrics_collector.log`
4. Verify SSH access to target system

## API Response Examples

### Latest CFRS Metrics
```bash
curl http://localhost:3000/api/systems/1/metrics/cfrs/latest
```
```json
{
  "timestamp": "2026-01-29T10:30:00Z",
  "cpu_iowait_percent": 2.5,
  "context_switch_rate": 8500,
  "swap_out_rate": 0,
  "major_page_fault_rate": 5.2,
  "cpu_temperature": 55.0,
  "gpu_temperature": 62.5,
  "cpu_percent": 45.2,
  "ram_percent": 68.5,
  "disk_percent": 72.0,
  "swap_in_rate": 0,
  "page_fault_rate": 150.5
}
```

### Raw CFRS Metrics (24h)
```bash
curl http://localhost:3000/api/systems/1/metrics/cfrs?hours=24
```
Returns array of 288 data points (5-min intervals × 12/hour × 24 hours)

## Development Notes

### Adding New CFRS Metrics
1. **Database:** Add column to `metrics` table in `schema.sql`
2. **Collector:** Add collection function to `metrics_collector.sh`
3. **Ingestion:** Update INSERT in `combined_monitor.py`
4. **Backend:** Add field to `getCFRSMetrics()` query
5. **Frontend:** Add to CFRSMetricsViewer component

### Performance Considerations
- Raw metrics queries limited to 10,000 rows by default
- Hourly aggregates reduce data volume by ~90%
- Use hourly stats for longer time ranges (>24h)
- Consider pagination for very large datasets

## Testing Checklist

- [ ] Backend starts without errors
- [ ] API endpoints return data (test with curl)
- [ ] CFRS tab appears in System Detail page
- [ ] Latest values display correctly
- [ ] Tier-1 charts render with data
- [ ] Tier-2 charts render with data
- [ ] Time range selector works
- [ ] View mode toggle works (Tier-1/Tier-2/All)
- [ ] Error handling displays correctly
- [ ] Loading state displays correctly
- [ ] "N/A" displays for missing metrics

## Future Enhancements

1. **Baseline Comparison** - Overlay baseline statistics on charts
2. **Anomaly Highlighting** - Mark data points that exceed thresholds
3. **Export Functionality** - Download CFRS metrics as CSV
4. **Real-time Updates** - WebSocket for live metric streaming
5. **Historical Analysis** - Compare current vs past periods
6. **CFRS Score Display** - Show computed CFRS components (D, V, S)

## Documentation References

- [CFRS_TIMESCALEDB_DOCUMENTATION.md](../database/CFRS_TIMESCALEDB_DOCUMENTATION.md) - Database layer
- [CFRS_METRICS_IMPLEMENTATION.md](../database/CFRS_METRICS_IMPLEMENTATION.md) - Metrics details
- [cfrs_query_cookbook.sql](../database/cfrs_query_cookbook.sql) - SQL query examples

---

**Document Version:** 1.0  
**Last Updated:** 2026-01-29  
**Author:** GitHub Copilot (Claude Sonnet 4.5)
