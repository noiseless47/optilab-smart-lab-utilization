# OptiLab Architecture Diagrams

## Complete System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           PRESENTATION LAYER                             │
│                                                                          │
│  ┌──────────────┐      ┌──────────────┐       ┌──────────────┐        │
│  │   Dashboard  │      │   Grafana    │       │  Lab Mentor  │        │
│  │   (FastAPI)  │      │  (Optional)  │       │   (User)     │        │
│  └──────┬───────┘      └──────┬───────┘       └──────┬───────┘        │
│         │                     │                       │                │
└─────────┼─────────────────────┼───────────────────────┼────────────────┘
          │                     │                       │
          │ HTTP/REST           │ SQL                   │ SSH (manual)
          │                     │                       │
┌─────────▼─────────────────────▼───────────────────────▼────────────────┐
│                         APPLICATION LAYER                               │
│                                                                          │
│  ┌───────────────────────────────────────────────────────────┐         │
│  │                    FastAPI Application                     │         │
│  │  • REST Endpoints  • Analytics  • Alerts                  │         │
│  └────────────────────────────┬──────────────────────────────┘         │
│                               │                                         │
└───────────────────────────────┼─────────────────────────────────────────┘
                                │ SQL/Async
                                │
┌───────────────────────────────▼─────────────────────────────────────────┐
│                          DATA LAYER                                      │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────┐          │
│  │          PostgreSQL 18 + TimescaleDB                      │          │
│  │  • Hypertables  • Compression  • Continuous Aggregates   │          │
│  │  • Tables: systems, metrics, network_scans, departments  │          │
│  └────────────────────────────▲──────────────────────────────┘          │
│                               │                                         │
└───────────────────────────────┼─────────────────────────────────────────┘
                                │ Writes
                                │
        ┌───────────────────────┴────────────────────────┐
        │                                                │
        │ (Direct Write)              (Queued Write)    │
        │                                                │
        ▼                                                ▼
┌───────────────────────────────┐        ┌──────────────────────────────┐
│                               │        │    MESSAGE QUEUE LAYER       │
│                               │        │                              │
│                               │        │  ┌────────────────────────┐  │
│                               │        │  │      RabbitMQ/Redis     │  │
│                               │        │  │  • discovery_queue     │  │
│                               │        │  │  • metrics_queue       │  │
│                               │        │  │  • alert_queue         │  │
│                               │        │  └──────────┬─────────────┘  │
│                               │        │             │                │
│                               │        │             ▼                │
│                               │        │  ┌────────────────────────┐  │
│                               │        │  │   Queue Consumer       │  │
│                               │        │  │  (queue_consumer.py)   │  │
│                               │        │  └──────────┬─────────────┘  │
│                               │        │             │                │
│                               │        └─────────────┼────────────────┘
│                               │                      │
│                               │                      │ Inserts
│                               │                      │
└───────────────┬───────────────┘                      │
                │                                      │
                └──────────────────┬───────────────────┘
                                   │
                                   │
┌──────────────────────────────────▼──────────────────────────────────────┐
│                        COLLECTION LAYER                                  │
│                                                                          │
│  ┌─────────────────────┐          ┌─────────────────────┐              │
│  │   Network Scanner   │          │   SSH Collector     │              │
│  │   (scanner.sh)      │          │   (ssh_script.sh)   │              │
│  │                     │          │                     │              │
│  │  • Ping sweep       │          │  • Transfer script  │              │
│  │  • CIDR parsing     │          │  • Execute remote   │              │
│  │  • System discovery │          │  • Parse JSON       │              │
│  │  • DB logging       │          │  • Store metrics    │              │
│  └─────────┬───────────┘          └─────────┬───────────┘              │
│            │                                 │                          │
│            │ Scan IP Range                   │ SSH + SCP                │
│            │                                 │                          │
└────────────┼─────────────────────────────────┼──────────────────────────┘
             │                                 │
             │                                 │
             ▼                                 ▼
    ┌────────────────┐              ┌─────────────────────┐
    │  Department    │              │   Target Systems    │
    │  WiFi Router   │              │   (Lab Computers)   │
    │                │              │                     │
    │  VLAN 30       │              │  • metrics_collector│
    │  10.30.0.0/16  │              │    runs here        │
    └────────────────┘              │  • Returns JSON     │
            │                       │                     │
            │                       └─────────────────────┘
            │ Network Scan
            │
            ▼
    ┌────────────────────────────┐
    │    Target Systems          │
    │    10.30.5.0/24           │
    │                           │
    │  ┌──────┐ ┌──────┐ ┌──────┐
    │  │ PC 1 │ │ PC 2 │ │ PC 3 │
    │  └──────┘ └──────┘ └──────┘
    └────────────────────────────┘
```

---

## Detailed Collection Flow

### 1. Discovery Phase (scanner.sh)

```
┌─────────────────┐
│  Lab Mentor     │
│  Runs:          │
│  scanner.sh     │
│  10.30.5.0/24 1 │
└────────┬────────┘
         │
         │ 1. Parse CIDR
         │ 2. Generate IP list
         │
         ▼
    ┌─────────────────┐
    │  For each IP:   │
    │  ping -c 2 IP   │
    └────┬───────┬────┘
         │       │
    Alive│       │Dead
         │       │
         ▼       ▼
    ┌────────┐  (Skip)
    │ Alive! │
    └────┬───┘
         │
         │ 3. Resolve hostname
         │
         ▼
    ┌──────────────────┐
    │  INSERT INTO     │
    │  systems         │
    │  (ip, hostname)  │
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │  UPDATE          │
    │  network_scans   │
    │  SET systems_    │
    │  found = count   │
    └──────────────────┘
```

### 2. Collection Phase (ssh_script.sh)

```
┌─────────────────┐
│  Lab Mentor     │
│  Runs:          │
│  ssh_script.sh  │
│  --all          │
└────────┬────────┘
         │
         │ 1. Query database for targets
         │
         ▼
    ┌───────────────────┐
    │  SELECT systems   │
    │  WHERE status =   │
    │  'active'         │
    └────────┬──────────┘
             │
             ▼
    ┌─────────────────────────┐
    │  For each system:       │
    │  1. Test SSH connection │
    └────────┬────────────────┘
             │
        Success│
             │
             ▼
    ┌───────────────────────────┐
    │  2. SCP metrics_collector │
    │     to /tmp/              │
    └────────┬──────────────────┘
             │
             ▼
    ┌───────────────────────────┐
    │  3. SSH execute:          │
    │     bash /tmp/metrics_    │
    │     collector.sh          │
    └────────┬──────────────────┘
             │
             ▼
    ┌───────────────────────────┐
    │  4. Capture JSON output   │
    │     {cpu: 45.2, ram: ..}  │
    └────────┬──────────────────┘
             │
             ▼
    ┌───────────────────────────┐
    │  5. Parse JSON            │
    └────────┬──────────────────┘
             │
             ▼
        ┌────┴─────┐
        │          │
   Queue│          │Direct
  Enabled          Disabled
        │          │
        ▼          ▼
    ┌────────┐  ┌────────────┐
    │ Publish│  │ INSERT INTO│
    │ to     │  │ metrics    │
    │ Queue  │  │            │
    └────┬───┘  └────────────┘
         │
         ▼
    ┌────────────────┐
    │ Consumer reads │
    │ from queue     │
    └────┬───────────┘
         │
         ▼
    ┌────────────────┐
    │ INSERT INTO    │
    │ metrics        │
    └────────────────┘
```

### 3. Metrics Collection (metrics_collector.sh)

**Runs ON the target system**

```
┌──────────────────────────┐
│  Target System           │
│  Receives script via SCP │
└───────────┬──────────────┘
            │
            ▼
    ┌────────────────────┐
    │  Execute script    │
    │  bash metrics_     │
    │  collector.sh      │
    └─────────┬──────────┘
              │
              ▼
    ┌──────────────────────┐
    │  Collect Metrics:    │
    │                      │
    │  1. CPU %            │
    │     /proc/stat       │
    │                      │
    │  2. RAM %            │
    │     /proc/meminfo    │
    │                      │
    │  3. Disk %           │
    │     df -h /          │
    │                      │
    │  4. Disk I/O         │
    │     /proc/diskstats  │
    │                      │
    │  5. Network I/O      │
    │     /sys/class/net   │
    │                      │
    │  6. GPU (optional)   │
    │     nvidia-smi       │
    │                      │
    │  7. System Info      │
    │     uptime, users    │
    └─────────┬────────────┘
              │
              ▼
    ┌──────────────────────┐
    │  Format as JSON:     │
    │  {                   │
    │    "cpu_percent": 45,│
    │    "ram_percent": 67,│
    │    ...               │
    │  }                   │
    └─────────┬────────────┘
              │
              ▼
    ┌──────────────────────┐
    │  Output to stdout    │
    │  (Captured by SSH)   │
    └──────────────────────┘
```

---

## Message Queue Architecture Detail

### Queue Position and Data Flow

```
┌────────────────────────────────────────────────────────────────┐
│                      DECOUPLED ARCHITECTURE                     │
└────────────────────────────────────────────────────────────────┘

                    ┌─────────────┐
                    │  Scanner/   │
                    │  Collector  │
                    └──────┬──────┘
                           │
                           │ Publish message
                           │
                           ▼
                    ┌─────────────────────┐
                    │   Message Queue     │
                    │   (RabbitMQ/Redis)  │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │discovery_queue│  │
                    │  ├───────────────┤  │
                    │  │metrics_queue  │  │
                    │  ├───────────────┤  │
                    │  │alert_queue    │  │
                    │  └───────────────┘  │
                    └──────────┬──────────┘
                               │
                               │ Consumer polls
                               │
                               ▼
                    ┌─────────────────────┐
                    │  Queue Consumer     │
                    │  (Python Worker)    │
                    │                     │
                    │  • Parse message    │
                    │  • Validate data    │
                    │  • Batch inserts    │
                    │  • Error handling   │
                    └──────────┬──────────┘
                               │
                               │ SQL INSERT
                               │
                               ▼
                    ┌─────────────────────┐
                    │   PostgreSQL DB     │
                    │                     │
                    │  • systems table    │
                    │  • metrics table    │
                    └─────────────────────┘

┌────────────────────────────────────────────────────────────────┐
│                      BENEFITS OF THIS DESIGN                    │
│                                                                 │
│  ✅ Non-blocking: Scanner continues without waiting for DB     │
│  ✅ Scalable: Add more consumers to process faster             │
│  ✅ Fault-tolerant: Messages persist if consumer crashes       │
│  ✅ Load balancing: Multiple consumers share the workload      │
│  ✅ Retry logic: Failed messages can be requeued               │
│  ✅ Monitoring: Queue depth indicates system health            │
└────────────────────────────────────────────────────────────────┘
```

### Direct vs Queued Comparison

```
DIRECT WRITE (Default)
======================
Scanner → Database
   ↓
Blocks until INSERT completes
If DB is slow/down, scanner stops
Simple, good for small deployments


QUEUED WRITE (Optional)
========================
Scanner → Queue → Consumer → Database
   ↓         ↓         ↓
Returns    Persists  Processes
immediately messages  async
Non-blocking, scalable, fault-tolerant
```

---

## Database Schema Relationships

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATABASE SCHEMA                           │
└─────────────────────────────────────────────────────────────────┘

┌───────────────┐
│  departments  │
│               │
│  dept_id (PK) │◄────────┐
│  dept_name    │         │
│  subnet_cidr  │         │
└───────────────┘         │
                          │
                          │ FK: dept_id
                          │
    ┌─────────────────────┼─────────────────────┐
    │                     │                     │
    │                     │                     │
    ▼                     ▼                     ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│     labs      │  │    systems    │  │network_scans  │
│               │  │               │  │               │
│  lab_id (PK)  │  │ system_id(PK) │  │ scan_id (PK)  │
│  dept_id (FK) │  │  hostname     │  │ dept_id (FK)  │
│  lab_number   │  │  ip_address   │  │ scan_type     │
└───────┬───────┘  │  dept_id (FK) │  │ target_range  │
        │          │  lab_id (FK)  │  │ systems_found │
        │          │  status       │  │ scan_start    │
        │          └───────┬───────┘  │ scan_end      │
        │                  │          └───────────────┘
        │ FK: lab_id       │
        │                  │
        └──────────────────┤
                           │ FK: system_id
                           │
                           ▼
                   ┌───────────────┐
                   │    metrics    │
                   │               │
                   │ system_id(FK) │
                   │ timestamp     │
                   │ cpu_percent   │
                   │ ram_percent   │
                   │ disk_percent  │
                   │ network_*     │
                   │ gpu_*         │
                   └───────────────┘
                   (Time-series data)
```

---

## Security Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        SECURITY LAYERS                           │
└─────────────────────────────────────────────────────────────────┘

Layer 1: Network Security
┌──────────────────────────────┐
│  • VLAN isolation            │
│  • Firewall rules            │
│  • SSH port filtering        │
└──────────────────────────────┘

Layer 2: Authentication
┌──────────────────────────────┐
│  • SSH key-based auth only   │
│  • No password authentication│
│  • Restricted key permissions│
│  • Key rotation policy       │
└──────────────────────────────┘

Layer 3: Authorization
┌──────────────────────────────┐
│  • Limited SSH user perms    │
│  • Database role restrictions│
│  • Minimal privilege access  │
└──────────────────────────────┘

Layer 4: Data Protection
┌──────────────────────────────┐
│  • Encrypted SSH connections │
│  • TLS for database (optional│
│  • Credential encryption     │
│  • No plaintext passwords    │
└──────────────────────────────┘

Layer 5: Audit & Monitoring
┌──────────────────────────────┐
│  • All scans logged to DB    │
│  • Collection audit trail    │
│  • Failed auth monitoring    │
│  • Alert on anomalies        │
└──────────────────────────────┘
```

---

## Deployment Scenarios

### Scenario 1: Small Lab (No Queue)
```
1 Bastion Host
    ↓
    Scanner + Collector scripts
    ↓
    Direct DB writes
    ↓
PostgreSQL (same host)

Good for: < 50 systems, simple deployment
```

### Scenario 2: Medium Department (With Queue)
```
Bastion Host 1: Scanner + Collector
    ↓
RabbitMQ Server (separate)
    ↓
Worker Nodes: Queue consumers (3x)
    ↓
PostgreSQL + TimescaleDB (separate)

Good for: 50-500 systems, high availability
```

### Scenario 3: Enterprise (Distributed)
```
Load Balancer
    ↓
Scanner Cluster (3x)
    ↓
RabbitMQ Cluster (3x, HA)
    ↓
Consumer Pool (10x workers)
    ↓
PostgreSQL Primary + Read Replicas
    ↓
Grafana/Dashboard (monitoring)

Good for: > 500 systems, multi-department
```

---

This architecture provides flexibility, scalability, and maintainability for the OptiLab system.
