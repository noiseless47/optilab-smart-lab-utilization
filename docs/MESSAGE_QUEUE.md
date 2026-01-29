# Message Queue Integration Guide

## Architecture Overview

Based on the system diagram and implementation, the **Message Queue** should be positioned between the **Collector** and the **Database/Dashboard** layers. This decouples data collection from data processing and enables:

1. **Asynchronous Processing**: Collectors can continue scanning without waiting for DB writes
2. **Load Balancing**: Multiple workers can process metrics in parallel
3. **Fault Tolerance**: Messages persist if database is temporarily unavailable
4. **Scalability**: Easy to add more collectors or processors

## Message Flow

```
┌─────────────┐         ┌──────────────┐         ┌──────────────┐
│   Scanner   │────────>│   Message    │────────>│   Database   │
│  (scanner.sh)│         │    Queue     │         │  (Postgres)  │
└─────────────┘         │  (RabbitMQ)  │         └──────────────┘
                        │              │                ▲
┌─────────────┐         │              │                │
│  Collector  │────────>│  - discovery │                │
│(ssh_script.sh)        │  - metrics   │         ┌──────────────┐
└─────────────┘         │  - alerts    │         │   Consumer   │
                        └──────────────┘         │   Workers    │
                               │                 └──────────────┘
                               │
                               ▼
                        ┌──────────────┐
                        │  Dashboard   │
                        │   (FastAPI)  │
                        └──────────────┘
```

## Queue Structure

### 1. Discovery Queue
- **Purpose**: Store discovered systems from scanner
- **Queue Name**: `discovery_queue`
- **Message Format**:
```json
{
  "scan_id": 123,
  "dept_id": 1,
  "ip_address": "10.30.5.10",
  "hostname": "lab-pc-01",
  "mac_address": "00:1B:44:11:3A:B7",
  "discovered_at": "2025-11-25T10:30:00Z",
  "scan_type": "ping"
}
```
- **Routing Key**: `discovery.new`

### 2. Metrics Queue
- **Purpose**: Store collected metrics from systems
- **Queue Name**: `metrics_queue`
- **Message Format**:
```json
{
  "system_id": 42,
  "collected_at": "2025-11-25T10:35:00Z",
  "metrics": {
    "cpu_percent": 45.23,
    "ram_percent": 67.89,
    "disk_percent": 55.12,
    "network_sent_mbps": 12.45,
    "network_recv_mbps": 8.32,
    "gpu_percent": 78.90,
    "uptime_seconds": 345600,
    "logged_in_users": 3
  }
}
```
- **Routing Key**: `metrics.collected`

### 3. Alert Queue
- **Purpose**: Store alert events for immediate processing
- **Queue Name**: `alert_queue`
- **Message Format**:
```json
{
  "system_id": 42,
  "alert_type": "cpu_high",
  "severity": "warning",
  "value": 95.5,
  "threshold": 90.0,
  "timestamp": "2025-11-25T10:40:00Z"
}
```
- **Routing Key**: `alerts.{severity}`

## Queue Position in Architecture

### Where the Queue Fits:

**1. Scanner → Queue → Database**
```bash
scanner.sh discovers systems
    ↓
Publishes to discovery_queue
    ↓
Consumer reads from discovery_queue
    ↓
Inserts into systems table
```

**2. Collector → Queue → Database**
```bash
ssh_script.sh collects metrics
    ↓
Publishes to metrics_queue
    ↓
Consumer reads from metrics_queue
    ↓
Inserts into metrics table
```

**3. Triggers → Queue → Dashboard**
```bash
Database triggers detect alerts
    ↓
Publishes to alert_queue (via pg_notify)
    ↓
Consumer reads from alert_queue
    ↓
Sends notifications/webhooks
```

## Benefits of Queue Placement

### For Scanner (scanner.sh):
- **Faster Scans**: Don't wait for DB writes
- **Batch Processing**: Group discoveries before inserting
- **Retry Logic**: Failed DB inserts can be retried
- **Deduplication**: Can check if system already exists before inserting

### For Collector (ssh_script.sh):
- **Non-blocking**: Continue collecting while previous metrics are being processed
- **Aggregation**: Can aggregate metrics before storing (e.g., 5-min averages)
- **Compression**: Can compress time-series data before DB insert
- **Multiple Consumers**: Scale out processing with multiple workers

### For System:
- **Decoupling**: Collectors and database can scale independently
- **Reliability**: Messages persist even if DB is down
- **Monitoring**: Queue depth indicates system load
- **Reprocessing**: Can replay messages if needed

## Implementation Options

### Option 1: RabbitMQ (Recommended)
- **Pros**: Mature, reliable, excellent routing
- **Cons**: Additional service to manage
- **Use Case**: Production environments

### Option 2: Redis (Simple)
- **Pros**: Fast, simple, can also cache
- **Cons**: Less reliable than RabbitMQ
- **Use Case**: Development/testing

### Option 3: PostgreSQL LISTEN/NOTIFY (Built-in)
- **Pros**: No additional service needed
- **Cons**: Not persistent, limited throughput
- **Use Case**: Small deployments

## Integration Steps

### Phase 1: Add Queue Support to Scripts (Already Done)
- ✅ `scanner.sh`: Added queue placeholder
- ✅ `ssh_script.sh`: Added `--queue-enabled` flag
- ✅ Message format defined in JSON

### Phase 2: Set Up Message Queue
```bash
# Install RabbitMQ
docker run -d --name rabbitmq \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:3-management

# Create queues and exchanges
# (Use queue_setup.sh script)
```

### Phase 3: Create Consumer Workers
- Python script to read from queues
- Insert into database with error handling
- See `queue_consumer.py` (to be created)

### Phase 4: Enable Queue in Scripts
```bash
# Scanner with queue
./scanner.sh 10.30.5.0/24 1 --queue-enabled

# Collector with queue
./ssh_script.sh --all --queue-enabled
```

## Configuration

### Environment Variables
```bash
# Message Queue
export QUEUE_ENABLED=true
export QUEUE_TYPE=rabbitmq  # or redis, postgres
export QUEUE_HOST=localhost
export QUEUE_PORT=5672
export QUEUE_USER=guest
export QUEUE_PASSWORD=guest

# Queues
export DISCOVERY_QUEUE=discovery_queue
export METRICS_QUEUE=metrics_queue
export ALERT_QUEUE=alert_queue
```

### Script Usage
```bash
# Enable queue in scanner
QUEUE_ENABLED=true ./scanner.sh 10.30.5.0/24 1

# Enable queue in collector
./ssh_script.sh --all --queue-enabled --queue-host rabbitmq.example.com
```

## Monitoring Queue Health

### Check Queue Depth
```bash
# RabbitMQ
curl -u guest:guest http://localhost:15672/api/queues/%2F/metrics_queue

# Redis
redis-cli LLEN metrics_queue
```

### Alert on Queue Backlog
- If queue depth > 1000: Increase consumers
- If queue depth > 10000: Alert operations team
- If consumers are down: Automatic restart

## Future Enhancements

1. **Priority Queues**: Process critical systems first
2. **Dead Letter Queues**: Handle failed messages
3. **Message TTL**: Expire old metrics if not processed
4. **Stream Processing**: Use Apache Kafka for high-throughput scenarios
5. **Event Sourcing**: Store all events for replay/audit

## See Also
- `queue_setup.sh` - Queue initialization script
- `queue_consumer.py` - Consumer worker implementation
- `collector/README.md` - Collector documentation
