# Dynamic System Status

## Overview

The system status in OptiLab is **automatically updated** based on metrics collection and maintenance operations. Status is stored in the `systems` table and updated via triggers and periodic jobs.

## How It Works

### Status Values

| Status | Condition | Meaning |
|--------|-----------|---------|
| `active` | Metrics received within last 10 minutes | System is online and collecting metrics |
| `offline` | No metrics for 10+ minutes | System is down or unreachable |
| `maintenance` | Added to maintenance logs | System is under maintenance (manual override) |
| `discovered` | Initial state, never monitored | System discovered but not yet monitored |

### Automatic Status Updates

#### 1. Active Status (Trigger-based)
When metrics are inserted, the system is automatically marked as `active`:

```sql
CREATE OR REPLACE FUNCTION update_system_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Only update status if not in maintenance
    IF (SELECT status FROM systems WHERE system_id = NEW.system_id) != 'maintenance' THEN
        UPDATE systems 
        SET status = 'active', updated_at = NOW()
        WHERE system_id = NEW.system_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_metrics_update_status
    AFTER INSERT ON metrics
    FOR EACH ROW
    EXECUTE FUNCTION update_system_status();
```

#### 2. Offline Status (Periodic Job)
A periodic job marks systems offline if no metrics in 10+ minutes:

```sql
CREATE OR REPLACE FUNCTION mark_systems_offline()
RETURNS TABLE(system_id INT, hostname VARCHAR, old_status VARCHAR, new_status VARCHAR) AS $$
BEGIN
    RETURN QUERY
    UPDATE systems s
    SET status = 'offline', updated_at = NOW()
    FROM (
        SELECT sys.system_id, sys.hostname, sys.status as old_status
        FROM systems sys
        LEFT JOIN (
            SELECT m.system_id, MAX(m.timestamp) as last_metric_time
            FROM metrics m
            GROUP BY m.system_id
        ) recent_metrics ON sys.system_id = recent_metrics.system_id
        WHERE sys.status NOT IN ('maintenance')
        AND (
            recent_metrics.last_metric_time IS NULL 
            OR recent_metrics.last_metric_time < NOW() - INTERVAL '10 minutes'
        )
        AND sys.status != 'offline'
    ) offline_systems
    WHERE s.system_id = offline_systems.system_id
    RETURNING s.system_id, s.hostname, offline_systems.old_status, s.status as new_status;
END;
$$ LANGUAGE plpgsql;
```

**Run via cron (every 5 minutes):**
```bash
*/5 * * * * /path/to/scripts/update_offline_systems.sh >> /var/log/optilab/offline_check.log 2>&1
```

**Or use pg_cron:**
```sql
CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('mark-offline-systems', '*/5 * * * *', 'SELECT mark_systems_offline();');
```

#### 3. Maintenance Status (Application-level)
When a system is added to maintenance logs, status is set to `maintenance`:

```javascript
async addMaintainence(system_id, date_at, isACK, ACKat, ACKby, resolved_at, severity, message) {
    // Insert maintenance log
    const insertQuery = this.sql`
        INSERT INTO maintainence_logs(...) VALUES(...) RETURNING *
    `
    const result = await this.query(insertQuery, 'Failed to add maintainence log')
    
    // Update system status to 'maintenance'
    const updateStatusQuery = this.sql`
        UPDATE systems 
        SET status = 'maintenance', updated_at = NOW()
        WHERE system_id = ${system_id}
    `
    await this.query(updateStatusQuery, 'Failed to update system status')
    
    return result
}
```

When maintenance is resolved or deleted, status reverts to `active` or `offline`:

```javascript
async restoreSystemStatus(system_id) {
    // Check if system has recent metrics (within last 10 minutes)
    const statusQuery = this.sql`
        UPDATE systems s
        SET status = CASE 
            WHEN m.last_metric_time IS NOT NULL AND m.last_metric_time >= NOW() - INTERVAL '10 minutes' 
                THEN 'active'
            ELSE 'offline'
        END,
        updated_at = NOW()
        FROM (
            SELECT system_id, MAX(timestamp) as last_metric_time
            FROM metrics
            WHERE system_id = ${system_id}
            GROUP BY system_id
        ) m
        WHERE s.system_id = m.system_id AND s.system_id = ${system_id}
    `
    await this.query(statusQuery, 'Failed to restore system status')
}
```

## Implementation

### Database Setup

1. Apply schema changes:
```bash
psql -U postgres -d optilab -f database/schema.sql
```

2. Set up cron job:
```bash
chmod +x scripts/update_offline_systems.sh
crontab -e
# Add: */5 * * * * /path/to/scripts/update_offline_systems.sh >> /var/log/optilab/offline_check.log 2>&1
```

**OR** use pg_cron (recommended for production):
```sql
psql -U postgres -d optilab -f scripts/update_offline_systems.sql
```

### Backend Implementation

The maintenance endpoints automatically handle status updates:

- **POST `/maintenance`** → Sets status to `maintenance`
- **PUT `/maintenance/:id`** (with `resolved_at`) → Restores status to `active`/`offline`
- **DELETE `/maintenance/:id`** → Restores status to `active`/`offline`

### Frontend Display

Status is displayed with color-coded badges in [Lab.tsx](../frontend/src/pages/Lab.tsx):

```tsx
const getStatusColor = (status: string) => {
  switch (status?.toLowerCase()) {
    case 'active':
      return 'bg-green-100 text-green-700'  // Green for online
    case 'offline':
      return 'bg-gray-100 text-gray-700'    // Gray for offline
    case 'maintenance':
      return 'bg-yellow-100 text-yellow-700' // Yellow for maintenance
    default:
      return 'bg-blue-100 text-blue-700'     // Blue for unknown
  }
}
```

## Benefits

### 1. **Real-Time Accuracy**
- Trigger-based updates on metrics insert (immediate)
- Periodic offline detection (5-10 minute delay)
- Maintenance status manually controlled

### 2. **No Race Conditions**
- Status stored in database, not calculated on-read
- Triggers ensure consistent updates
- Maintenance mode prevents accidental status changes

### 3. **Maintenance Override**
- Systems in maintenance stay in maintenance
- Not affected by offline detection
- Manual control when needed

### 4. **Performance**
- No complex joins on every query
- Direct status column reads (fast)
- Indexed status field for filtering

## Metrics Collection Interval

The collector sends metrics every **5 minutes**. With a 10-minute threshold:
- If 1 collection cycle fails: System still shows as active
- If 2 consecutive cycles fail: System marked offline (via periodic job)

This provides resilience against temporary network issues while maintaining quick offline detection.

## Adjusting the Threshold

To change the offline threshold, update the interval in two places:

**1. In the trigger function:**
```sql
-- Current: 10 minutes
WHEN m.last_metric_time >= NOW() - INTERVAL '10 minutes'

-- Example: 15 minutes for slower collection
WHEN m.last_metric_time >= NOW() - INTERVAL '15 minutes'
```

**2. In the mark_systems_offline function:**
```sql
-- Current: 10 minutes
OR recent_metrics.last_metric_time < NOW() - INTERVAL '10 minutes'

-- Example: 15 minutes
OR recent_metrics.last_metric_time < NOW() - INTERVAL '15 minutes'
```

**Recommended**: Set threshold to 2x the collection interval for reliability.

## Monitoring

### Check System Status Distribution

```sql
SELECT status, COUNT(*) as count
FROM systems
GROUP BY status
ORDER BY count DESC;
```

### Find Recently Offline Systems

```sql
SELECT s.hostname, s.ip_address, s.status, s.updated_at,
       NOW() - s.updated_at as time_since_update
FROM systems s
WHERE s.status = 'offline'
ORDER BY s.updated_at DESC;
```

### View Systems That Need Attention

```sql
SELECT s.hostname, s.ip_address, s.status, 
       MAX(m.timestamp) as last_metric,
       NOW() - MAX(m.timestamp) as time_since_metric
FROM systems s
LEFT JOIN metrics m ON s.system_id = m.system_id
WHERE s.status IN ('offline', 'maintenance')
GROUP BY s.system_id, s.hostname, s.ip_address, s.status
ORDER BY last_metric DESC;
```

### Test the Offline Detection Function

```sql
-- See what systems would be marked offline (dry run)
SELECT sys.system_id, sys.hostname, sys.status, 
       recent_metrics.last_metric_time,
       NOW() - recent_metrics.last_metric_time as time_since_metric
FROM systems sys
LEFT JOIN (
    SELECT m.system_id, MAX(m.timestamp) as last_metric_time
    FROM metrics m
    GROUP BY m.system_id
) recent_metrics ON sys.system_id = recent_metrics.system_id
WHERE sys.status NOT IN ('maintenance')
AND (
    recent_metrics.last_metric_time IS NULL 
    OR recent_metrics.last_metric_time < NOW() - INTERVAL '10 minutes'
)
AND sys.status != 'offline';
```

## Maintenance Workflow

### Adding a System to Maintenance

```bash
# Via API
curl -X POST http://localhost:3000/api/departments/1/labs/2/maintenance \
  -H "Content-Type: application/json" \
  -d '{
    "system_id": 123,
    "severity": "high",
    "message": "Disk replacement scheduled",
    "date_at": "2026-01-24T10:00:00Z"
  }'
```

**What happens:**
1. Maintenance log created
2. System status → `maintenance`
3. System will NOT be marked offline by periodic job

### Resolving Maintenance

```bash
# Via API
curl -X PUT http://localhost:3000/api/departments/1/labs/2/maintenance/456 \
  -H "Content-Type: application/json" \
  -d '{
    "resolved_at": "2026-01-24T14:30:00Z"
  }'
```

**What happens:**
1. Maintenance log updated with `resolved_at`
2. System status checked:
   - If metrics within 10 min → status = `active`
   - If no recent metrics → status = `offline`

### Deleting Maintenance Log

```bash
# Via API
curl -X DELETE http://localhost:3000/api/departments/1/labs/2/maintenance/456
```

**What happens:**
1. Maintenance log deleted
2. System status restored (same logic as resolve)

## Troubleshooting

### System Stuck in Maintenance

**Problem:** System resolved but still shows maintenance status

**Solution:**
```sql
-- Manually restore status
UPDATE systems
SET status = CASE 
    WHEN (SELECT MAX(timestamp) FROM metrics WHERE system_id = systems.system_id) >= NOW() - INTERVAL '10 minutes'
        THEN 'active'
    ELSE 'offline'
END,
updated_at = NOW()
WHERE status = 'maintenance'
AND system_id NOT IN (
    SELECT DISTINCT system_id 
    FROM maintainence_logs 
    WHERE resolved_at IS NULL
);
```

### Offline Job Not Running

**Problem:** Systems not being marked offline automatically

**Check cron:**
```bash
crontab -l | grep offline
tail -f /var/log/optilab/offline_check.log
```

**Check pg_cron:**
```sql
SELECT * FROM cron.job WHERE jobname = 'mark-offline-systems';
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;
```

**Manual run:**
```sql
SELECT * FROM mark_systems_offline();
```

### Status Not Updating on Metrics Insert

**Problem:** System receives metrics but stays offline

**Check trigger:**
```sql
SELECT tgname, tgenabled FROM pg_trigger WHERE tgname = 'trg_metrics_update_status';
```

**Re-create trigger if needed:**
```sql
DROP TRIGGER IF EXISTS trg_metrics_update_status ON metrics;
CREATE TRIGGER trg_metrics_update_status
    AFTER INSERT ON metrics
    FOR EACH ROW
    EXECUTE FUNCTION update_system_status();
```

## Architecture Decision

**Why use triggers + periodic jobs instead of calculated status?**

The original implementation calculated status on every query. The new approach is superior because:

### Advantages:
1. **Maintenance Override**: Manual control over system status
2. **Better Performance**: No complex joins on reads
3. **Audit Trail**: Status changes logged with `updated_at`
4. **Simpler Queries**: Direct column access
5. **Database Consistency**: Status in one place

### Trade-offs:
1. **Requires Cron/pg_cron**: Additional setup for offline detection
2. **Slight Delay**: Up to 5-10 minutes to detect offline (acceptable)
3. **More Triggers**: Additional database logic to maintain

The benefits far outweigh the costs, especially for production systems with maintenance workflows.

## Future Enhancements

### 1. Status History Tracking
Track all status changes over time:
```sql
CREATE TABLE system_status_history (
    history_id BIGSERIAL PRIMARY KEY,
    system_id INT REFERENCES systems(system_id),
    old_status VARCHAR(20),
    new_status VARCHAR(20),
    changed_at TIMESTAMPTZ DEFAULT NOW(),
    changed_by VARCHAR(100),
    reason TEXT
);

-- Trigger to log status changes
CREATE OR REPLACE FUNCTION log_status_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status != NEW.status THEN
        INSERT INTO system_status_history (system_id, old_status, new_status)
        VALUES (NEW.system_id, OLD.status, NEW.status);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_log_status_change
    AFTER UPDATE OF status ON systems
    FOR EACH ROW
    EXECUTE FUNCTION log_status_change();
```

### 2. Alerting on Status Changes
Send alerts when systems go offline:
```sql
CREATE OR REPLACE FUNCTION alert_on_offline()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.status = 'active' AND NEW.status = 'offline' THEN
        -- Insert into alerts table or call external API
        INSERT INTO alerts (system_id, severity, message, created_at)
        VALUES (NEW.system_id, 'warning', 
                'System ' || NEW.hostname || ' went offline', 
                NOW());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### 3. Smart Offline Detection
Use ML/heuristics to detect unusual offline patterns:
- Recurring offline times (scheduled shutdowns)
- Weekend/holiday patterns
- Gradual degradation (metrics declining before offline)

### 4. Auto-Recovery Tracking
Track how long systems take to recover:
```sql
SELECT s.hostname,
       sh1.changed_at as went_offline,
       sh2.changed_at as came_online,
       sh2.changed_at - sh1.changed_at as downtime
FROM system_status_history sh1
JOIN system_status_history sh2 
    ON sh1.system_id = sh2.system_id 
    AND sh2.history_id = (
        SELECT MIN(history_id) 
        FROM system_status_history 
        WHERE system_id = sh1.system_id 
        AND new_status = 'active' 
        AND history_id > sh1.history_id
    )
WHERE sh1.new_status = 'offline'
ORDER BY downtime DESC;
```

## Summary

The hybrid approach (triggers for active, periodic job for offline, application-level for maintenance) provides:

- ✅ **Immediate** active status on metrics receipt
- ✅ **Automatic** offline detection within 5-10 minutes
- ✅ **Manual** maintenance mode control
- ✅ **Performance** optimized with direct column reads
- ✅ **Reliability** with proper error handling and logging

This architecture scales well and provides the foundation for advanced monitoring features.

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
