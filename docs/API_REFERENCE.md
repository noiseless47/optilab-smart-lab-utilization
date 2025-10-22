# API Reference Documentation
## Lab Resource Monitoring System REST API

**Base URL**: `http://localhost:8000`  
**Version**: 1.0  
**Protocol**: HTTP/HTTPS  
**Format**: JSON

---

## 📋 Quick Reference

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/` | GET | API information |
| `/health` | GET | Health check |
| `/api/systems/register` | POST | Register/update system |
| `/api/metrics` | POST | Submit metrics |
| `/api/systems` | GET | List all systems |
| `/api/systems/status` | GET | Current system status |
| `/api/systems/{id}/metrics` | GET | System metrics history |
| `/api/analytics/top-consumers/{type}` | GET | Top resource consumers |
| `/api/analytics/underutilized` | GET | Underutilized systems |
| `/api/alerts/active` | GET | Active alerts |

---

## 🔌 Endpoints

### 1. Root Endpoint

**GET /** 

Get API information and available endpoints.

**Request:**
```bash
curl http://localhost:8000/
```

**Response:**
```json
{
  "name": "Lab Resource Monitoring API",
  "version": "1.0.0",
  "status": "online",
  "endpoints": {
    "systems": "/api/systems",
    "metrics": "/api/metrics",
    "status": "/api/systems/status",
    "docs": "/docs"
  }
}
```

---

### 2. Health Check

**GET /health**

Check API and database connectivity.

**Request:**
```bash
curl http://localhost:8000/health
```

**Response (Healthy):**
```json
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2025-10-21T10:30:00.000Z"
}
```

**Response (Unhealthy):**
```json
{
  "status": "unhealthy",
  "database": "disconnected",
  "error": "Connection error details",
  "timestamp": "2025-10-21T10:30:00.000Z"
}
```

---

### 3. Register System

**POST /api/systems/register**

Register a new system or update existing system information.

**Request Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "system_id": "550e8400-e29b-41d4-a716-446655440000",
  "hostname": "lab-pc-01",
  "ip_address": "192.168.1.10",
  "location": "Computer Lab A",
  "department": "Computer Science",
  "cpu_model": "Intel Core i7-9700",
  "cpu_cores": 8,
  "cpu_threads": 8,
  "cpu_base_freq": 3.0,
  "ram_total_gb": 16,
  "ram_type": "DDR4",
  "gpu_model": "NVIDIA RTX 3060",
  "gpu_memory_gb": 12,
  "gpu_count": 1,
  "disk_total_gb": 512,
  "disk_type": "NVMe",
  "os_name": "Windows 10",
  "os_version": "10.0.19044"
}
```

**Response (201 Created):**
```json
{
  "message": "System registered",
  "system_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response (Existing System):**
```json
{
  "message": "System updated",
  "system_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Python Example:**
```python
import requests

system_data = {
    "system_id": "550e8400-e29b-41d4-a716-446655440000",
    "hostname": "lab-pc-01",
    "location": "Computer Lab A",
    # ... other fields
}

response = requests.post(
    "http://localhost:8000/api/systems/register",
    json=system_data
)
print(response.json())
```

---

### 4. Submit Metrics

**POST /api/metrics**

Submit system performance metrics.

**Request Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "system_id": "550e8400-e29b-41d4-a716-446655440000",
  "timestamp": "2025-10-21T10:30:00.000Z",
  "cpu_percent": 45.5,
  "cpu_per_core": [42.1, 48.3, 44.2, 47.1, 43.5, 46.8, 44.9, 45.2],
  "cpu_freq_current": 2800.0,
  "cpu_temp": 65.5,
  "ram_used_gb": 10.2,
  "ram_available_gb": 5.8,
  "ram_percent": 63.75,
  "swap_used_gb": 0.5,
  "swap_percent": 2.0,
  "gpu_utilization": 25.5,
  "gpu_memory_used_gb": 3.2,
  "gpu_memory_percent": 26.7,
  "gpu_temp": 55.0,
  "disk_read_mb_s": 15.3,
  "disk_write_mb_s": 8.7,
  "disk_read_ops": 120,
  "disk_write_ops": 85,
  "disk_io_wait_percent": 5.2,
  "disk_used_gb": 320.5,
  "disk_percent": 62.6,
  "net_sent_mb_s": 1.2,
  "net_recv_mb_s": 3.5,
  "net_packets_sent": 1500,
  "net_packets_recv": 2200,
  "process_count": 156,
  "thread_count": 892,
  "load_avg_1min": 2.3,
  "load_avg_5min": 2.1,
  "load_avg_15min": 1.9,
  "collection_duration_ms": 245
}
```

**Response (201 Created):**
```json
{
  "message": "Metrics ingested successfully",
  "timestamp": "2025-10-21T10:30:00.000Z"
}
```

**Error Responses:**

**404 - System Not Found:**
```json
{
  "detail": "System 550e8400-... not found. Please register first."
}
```

**500 - Server Error:**
```json
{
  "detail": "Internal server error message"
}
```

**Python Example:**
```python
import requests
from datetime import datetime

metrics = {
    "system_id": "550e8400-e29b-41d4-a716-446655440000",
    "timestamp": datetime.utcnow().isoformat(),
    "cpu_percent": 45.5,
    "ram_percent": 63.75,
    # ... other metrics
}

response = requests.post(
    "http://localhost:8000/api/metrics",
    json=metrics
)
print(response.status_code)  # 201
```

---

### 5. List All Systems

**GET /api/systems**

Get information about all registered systems.

**Request:**
```bash
curl http://localhost:8000/api/systems
```

**Response (200 OK):**
```json
[
  {
    "system_id": "550e8400-e29b-41d4-a716-446655440000",
    "hostname": "lab-pc-01",
    "location": "Computer Lab A",
    "department": "Computer Science",
    "status": "active",
    "cpu_cores": 8,
    "ram_total_gb": 16,
    "gpu_model": "NVIDIA RTX 3060",
    "last_seen": "2025-10-21T10:30:00.000Z",
    "created_at": "2025-10-15T08:00:00.000Z"
  },
  // ... more systems
]
```

---

### 6. System Status

**GET /api/systems/status**

Get current real-time status of all systems.

**Request:**
```bash
curl http://localhost:8000/api/systems/status
```

**Response (200 OK):**
```json
[
  {
    "system_id": "550e8400-e29b-41d4-a716-446655440000",
    "hostname": "lab-pc-01",
    "status": "active",
    "last_seen": "2025-10-21T10:30:00.000Z",
    "current_cpu": 45.5,
    "current_ram": 63.75,
    "utilization_status": "normal"
  },
  // ... more systems
]
```

**Utilization Status Values:**
- `"overloaded"`: CPU > 90% or RAM > 90%
- `"underutilized"`: CPU < 20% and RAM < 20%
- `"normal"`: Within normal range

---

### 7. System Metrics History

**GET /api/systems/{system_id}/metrics**

Get historical metrics for a specific system.

**Query Parameters:**
- `hours` (optional, default: 24): Hours of history to retrieve
- `limit` (optional, default: 100): Maximum number of records

**Request:**
```bash
curl "http://localhost:8000/api/systems/550e8400-e29b-41d4-a716-446655440000/metrics?hours=48&limit=200"
```

**Response (200 OK):**
```json
[
  {
    "timestamp": "2025-10-21T10:30:00.000Z",
    "cpu_percent": 45.5,
    "ram_percent": 63.75,
    "gpu_utilization": 25.5,
    "disk_percent": 62.6,
    "disk_io_wait_percent": 5.2,
    "load_avg_1min": 2.3,
    "load_avg_5min": 2.1,
    "load_avg_15min": 1.9
  },
  // ... more metrics
]
```

**Python Example:**
```python
import requests

response = requests.get(
    "http://localhost:8000/api/systems/550e8400-.../metrics",
    params={"hours": 48, "limit": 200}
)
metrics = response.json()
```

---

### 8. Top Resource Consumers

**GET /api/analytics/top-consumers/{resource_type}**

Get top N systems by resource usage.

**Path Parameters:**
- `resource_type`: `cpu`, `ram`, `gpu`, or `disk_io`

**Query Parameters:**
- `limit` (optional, default: 10): Number of results
- `hours` (optional, default: 24): Time period

**Request:**
```bash
curl "http://localhost:8000/api/analytics/top-consumers/cpu?limit=5&hours=24"
```

**Response (200 OK):**
```json
[
  {
    "hostname": "lab-pc-05",
    "location": "Computer Lab A",
    "avg_usage": 78.5,
    "max_usage": 95.2,
    "current_usage": 72.3
  },
  // ... more systems
]
```

**Python Example:**
```python
response = requests.get(
    "http://localhost:8000/api/analytics/top-consumers/cpu",
    params={"limit": 5, "hours": 24}
)
top_consumers = response.json()
```

---

### 9. Underutilized Systems

**GET /api/analytics/underutilized**

Get list of underutilized systems for optimization.

**Query Parameters:**
- `days` (optional, default: 7): Analysis period in days

**Request:**
```bash
curl "http://localhost:8000/api/analytics/underutilized?days=30"
```

**Response (200 OK):**
```json
[
  {
    "hostname": "lab-pc-12",
    "location": "Computer Lab B",
    "cpu_cores": 8,
    "ram_total_gb": 16,
    "avg_cpu_percent": 18.5,
    "avg_ram_percent": 22.3,
    "utilization_score": 42.5,
    "period_start": "2025-09-21T00:00:00.000Z"
  },
  // ... more systems
]
```

---

### 10. Active Alerts

**GET /api/alerts/active**

Get all unresolved alerts.

**Request:**
```bash
curl http://localhost:8000/api/alerts/active
```

**Response (200 OK):**
```json
[
  {
    "alert_id": 12345,
    "triggered_at": "2025-10-21T10:25:00.000Z",
    "severity": "critical",
    "message": "Alert: High CPU Usage on system. cpu_percent: 96.5 > 95 (threshold: 95) for 10 minutes",
    "hostname": "lab-pc-05",
    "location": "Computer Lab A",
    "metric_name": "cpu_percent",
    "actual_value": 96.5,
    "threshold_value": 95
  },
  // ... more alerts
]
```

---

## 🔒 Authentication (Future)

Currently, the API is open for development. For production deployment, implement:

**API Key Authentication:**
```python
headers = {
    "X-API-Key": "your-api-key-here",
    "Content-Type": "application/json"
}
```

**JWT Token Authentication:**
```python
headers = {
    "Authorization": "Bearer YOUR_JWT_TOKEN",
    "Content-Type": "application/json"
}
```

---

## 📊 Rate Limiting (Recommended for Production)

Suggested limits:
- **Data ingestion** (`/api/metrics`): 1 request per 5 minutes per system
- **Query endpoints**: 100 requests per minute per client
- **Analytics endpoints**: 10 requests per minute per client

---

## ⚠️ Error Codes

| Code | Meaning | Example |
|------|---------|---------|
| 200 | Success | GET requests |
| 201 | Created | POST metrics/systems |
| 400 | Bad Request | Invalid data format |
| 404 | Not Found | System/resource doesn't exist |
| 500 | Server Error | Database connection failed |

---

## 🧪 Testing

### Using cURL

```bash
# Health check
curl http://localhost:8000/health

# Get systems
curl http://localhost:8000/api/systems

# Post metrics
curl -X POST http://localhost:8000/api/metrics \
  -H "Content-Type: application/json" \
  -d '{"system_id": "...", "cpu_percent": 45.5, ...}'
```

### Using Python

```python
import requests

# Health check
response = requests.get("http://localhost:8000/health")
print(response.json())

# Get systems
response = requests.get("http://localhost:8000/api/systems")
systems = response.json()

# Post metrics
metrics = {"system_id": "...", "cpu_percent": 45.5}
response = requests.post("http://localhost:8000/api/metrics", json=metrics)
```

### Using Postman

1. Import collection from `/docs/api_collection.json` (if available)
2. Set base URL: `http://localhost:8000`
3. Test endpoints

---

## 📚 Interactive Documentation

Visit http://localhost:8000/docs for interactive Swagger UI:
- Test endpoints directly
- View request/response schemas
- Try out API calls

Alternative: http://localhost:8000/redoc for ReDoc documentation

---

## 🔗 WebSocket Support (Future Enhancement)

For real-time updates:

```python
# WebSocket endpoint (future)
ws://localhost:8000/ws/metrics/{system_id}

# Client code
import websockets
async with websockets.connect('ws://localhost:8000/ws/metrics/...') as websocket:
    while True:
        data = await websocket.recv()
        print(data)
```

---

## 📝 Notes

- All timestamps are in **ISO 8601 format** (UTC)
- All sizes are in **GB** (gigabytes)
- All rates are in **MB/s** (megabytes per second)
- All percentages are **0-100** range
- System IDs are **UUIDv4** format

---

**API Version**: 1.0  
**Last Updated**: October 21, 2025  
**Documentation**: Auto-generated from FastAPI
