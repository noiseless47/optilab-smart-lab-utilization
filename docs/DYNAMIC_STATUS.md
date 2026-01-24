# Dynamic System Status

## Overview

The system status in OptiLab is **dynamically calculated** based on the last metrics timestamp, not stored as a static field. This provides real-time status tracking without manual updates.

## How It Works

### Status Calculation Logic

A system's status is determined by when it last sent metrics to the database:

```sql
CASE 
    WHEN last_metric_time IS NULL THEN 'unknown'     -- Never sent metrics
    WHEN last_metric_time < NOW() - INTERVAL '10 minutes' THEN 'offline'  -- No metrics in 10+ minutes
    ELSE 'active'  -- Received metrics within last 10 minutes
END as status
```

### Status Values

| Status | Condition | Meaning |
|--------|-----------|---------|
| `active` | Metrics received within last 10 minutes | System is online and collecting metrics |
| `offline` | No metrics for 10+ minutes | System is down or unreachable |
| `unknown` | Never sent any metrics | System discovered but not yet monitored |

## Implementation

### Database View

A SQL view `v_systems_with_status` provides systems with computed status:

```sql
CREATE OR REPLACE VIEW v_systems_with_status AS
SELECT 
    s.*,
    m.last_metric_time,
    CASE 
        WHEN m.last_metric_time IS NULL THEN 'unknown'
        WHEN m.last_metric_time < NOW() - INTERVAL '10 minutes' THEN 'offline'
        ELSE 'active'
    END as computed_status
FROM systems s
LEFT JOIN (
    SELECT system_id, MAX(timestamp) as last_metric_time
    FROM metrics
    GROUP BY system_id
) m ON s.system_id = m.system_id;
```

### Backend Queries

All queries that fetch systems now include dynamic status calculation:

**`getSystemsByLab(labID)`**
```javascript
SELECT 
    s.*,
    CASE 
        WHEN m.last_metric_time IS NULL THEN 'unknown'
        WHEN m.last_metric_time < NOW() - INTERVAL '10 minutes' THEN 'offline'
        ELSE 'active'
    END as status
FROM systems s
LEFT JOIN (
    SELECT system_id, MAX(timestamp) as last_metric_time
    FROM metrics
    GROUP BY system_id
) m ON s.system_id = m.system_id
WHERE s.lab_id = ${labID}
ORDER BY s.system_number
```

### Frontend Display

The Lab page displays status with color-coded badges:

```tsx
const getStatusColor = (status: string) => {
  switch (status?.toLowerCase()) {
    case 'active':
      return 'bg-green-100 text-green-700'  // Green for online
    case 'offline':
      return 'bg-gray-100 text-gray-700'     // Gray for offline
    case 'unknown':
    default:
      return 'bg-blue-100 text-blue-700'     // Blue for unknown
  }
}
```

## Benefits

### 1. **Real-Time Accuracy**
- No manual status updates needed
- Status automatically reflects current state
- Eliminates stale status data

### 2. **Automatic Detection**
- System going offline is detected within 10 minutes
- System coming online is detected on first metric receipt
- No polling or heartbeat mechanisms required

### 3. **Zero Configuration**
- Works automatically with metrics collection
- No additional services or jobs needed
- Leverages existing TimescaleDB infrastructure

### 4. **Performance**
- Uses indexed timestamp queries (fast)
- Computed on-demand (no storage overhead)
- Scales with metrics retention policy

## Metrics Collection Interval

The collector sends metrics every **5 minutes**. With a 10-minute threshold:
- If 1 collection cycle fails: System still shows as active
- If 2 consecutive cycles fail: System marked offline

This provides resilience against temporary network issues while maintaining quick offline detection.

## Adjusting the Threshold

To change the offline threshold, update the interval in all queries:

```sql
-- Current: 10 minutes
WHEN m.last_metric_time < NOW() - INTERVAL '10 minutes' THEN 'offline'

-- Example: 15 minutes for slower collection
WHEN m.last_metric_time < NOW() - INTERVAL '15 minutes' THEN 'offline'

-- Example: 5 minutes for faster detection
WHEN m.last_metric_time < NOW() - INTERVAL '5 minutes' THEN 'offline'
```

**Recommended**: Set threshold to 2x the collection interval for reliability.

## Monitoring

### Check System Status Distribution

```sql
SELECT 
    CASE 
        WHEN last_metric_time IS NULL THEN 'unknown'
        WHEN last_metric_time < NOW() - INTERVAL '10 minutes' THEN 'offline'
        ELSE 'active'
    END as status,
    COUNT(*) as count
FROM systems s
LEFT JOIN (
    SELECT system_id, MAX(timestamp) as last_metric_time
    FROM metrics
    GROUP BY system_id
) m ON s.system_id = m.system_id
GROUP BY status;
```

### Find Recently Offline Systems

```sql
SELECT s.hostname, s.ip_address, m.last_metric_time,
       NOW() - m.last_metric_time as time_since_last_metric
FROM systems s
INNER JOIN (
    SELECT system_id, MAX(timestamp) as last_metric_time
    FROM metrics
    GROUP BY system_id
) m ON s.system_id = m.system_id
WHERE m.last_metric_time < NOW() - INTERVAL '10 minutes'
ORDER BY m.last_metric_time DESC;
```

## Future Enhancements

### 1. Custom Status Rules
Add additional status types based on metrics content:
- `degraded`: High CPU/RAM but still sending metrics
- `maintenance`: Manually marked for scheduled maintenance

### 2. Status History
Track status changes over time:
```sql
CREATE TABLE system_status_log (
    system_id INT,
    status VARCHAR(20),
    changed_at TIMESTAMPTZ,
    duration INTERVAL
);
```

### 3. Alerting Integration
Trigger alerts when systems go offline:
```sql
-- Alert if system offline for > 30 minutes
SELECT * FROM v_systems_with_status
WHERE computed_status = 'offline'
AND last_metric_time < NOW() - INTERVAL '30 minutes';
```

## Architecture Decision

**Why not use a trigger to update a status column?**

While we could use a trigger on metrics insert to update `systems.status`, the dynamic calculation approach is superior because:

1. **Eliminates race conditions**: No concurrent updates to status field
2. **Handles offline detection**: Trigger only fires on insert, not absence of inserts
3. **Simpler maintenance**: No additional trigger code to maintain
4. **Audit trail**: Status derivation is transparent and reproducible
5. **Performance**: Modern PostgreSQL handles subqueries efficiently with proper indexes

The only downside is slightly more complex queries, but the benefits far outweigh this minor cost.
