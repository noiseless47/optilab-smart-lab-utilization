# API Reference# API Reference Documentation

## Lab Resource Monitoring System REST API

Complete API documentation for OptiLab Smart Lab Resource Monitoring System.

**Base URL**: `http://localhost:8000`  

## Base URL**Version**: 1.0  

**Protocol**: HTTP/HTTPS  

```**Format**: JSON

http://localhost:8000

```---



## Authentication## 📋 Quick Reference



Currently, the API does not require authentication. For production deployments, implement OAuth2 or API key authentication.| Endpoint | Method | Purpose |

|----------|--------|---------|

## Response Format| `/` | GET | API information |

| `/health` | GET | Health check |

All responses are in JSON format with the following structure:| `/api/systems/register` | POST | Register/update system |

| `/api/metrics` | POST | Submit metrics |

**Success Response:**| `/api/systems` | GET | List all systems |

```json| `/api/systems/status` | GET | Current system status |

{| `/api/systems/{id}/metrics` | GET | System metrics history |

  "status": "success",| `/api/analytics/top-consumers/{type}` | GET | Top resource consumers |

  "data": { ... }| `/api/analytics/underutilized` | GET | Underutilized systems |

}| `/api/alerts/active` | GET | Active alerts |

```

---

**Error Response:**

```json## 🔌 Endpoints

{

  "status": "error",### 1. Root Endpoint

  "message": "Error description",

  "code": "ERROR_CODE"**GET /** 

}

```Get API information and available endpoints.



## Endpoints**Request:**

```bash

### System Managementcurl http://localhost:8000/

```

#### List All Systems

**Response:**

Returns a list of all monitored systems.```json

{

```http  "name": "Lab Resource Monitoring API",

GET /systems  "version": "1.0.0",

```  "status": "online",

  "endpoints": {

**Query Parameters:**    "systems": "/api/systems",

    "metrics": "/api/metrics",

| Parameter | Type | Required | Description |    "status": "/api/systems/status",

|-----------|------|----------|-------------|    "docs": "/docs"

| `department` | string | No | Filter by department name |  }

| `status` | string | No | Filter by status (online/offline) |}

| `limit` | integer | No | Maximum results (default: 100) |```



**Example Request:**---

```bash

curl http://localhost:8000/systems?department=Computer%20Science&limit=50### 2. Health Check

```

**GET /health**

**Example Response:**

```jsonCheck API and database connectivity.

{

  "systems": [**Request:**

    {```bash

      "id": 1,curl http://localhost:8000/health

      "hostname": "lab-pc-01",```

      "ip_address": "192.168.0.10",

      "department": "Computer Science",**Response (Healthy):**

      "os_type": "Linux",```json

      "os_version": "Ubuntu 22.04",{

      "status": "online",  "status": "healthy",

      "last_seen": "2025-10-25T14:30:00Z",  "database": "connected",

      "created_at": "2025-10-20T10:00:00Z"  "timestamp": "2025-10-21T10:30:00.000Z"

    },}

    {```

      "id": 2,

      "hostname": "lab-pc-02",**Response (Unhealthy):**

      "ip_address": "192.168.0.11",```json

      "department": "Computer Science",{

      "os_type": "Linux",  "status": "unhealthy",

      "os_version": "Ubuntu 22.04",  "database": "disconnected",

      "status": "online",  "error": "Connection error details",

      "last_seen": "2025-10-25T14:30:00Z",  "timestamp": "2025-10-21T10:30:00.000Z"

      "created_at": "2025-10-20T10:00:00Z"}

    }```

  ],

  "total": 2---

}

```### 3. Register System



---**POST /api/systems/register**



#### Get System DetailsRegister a new system or update existing system information.



Returns detailed information about a specific system.**Request Headers:**

```

```httpContent-Type: application/json

GET /systems/{system_id}```

```

**Request Body:**

**Path Parameters:**```json

{

| Parameter | Type | Required | Description |  "system_id": "550e8400-e29b-41d4-a716-446655440000",

|-----------|------|----------|-------------|  "hostname": "lab-pc-01",

| `system_id` | integer | Yes | System ID |  "ip_address": "192.168.1.10",

  "location": "Computer Lab A",

**Example Request:**  "department": "Computer Science",

```bash  "cpu_model": "Intel Core i7-9700",

curl http://localhost:8000/systems/1  "cpu_cores": 8,

```  "cpu_threads": 8,

  "cpu_base_freq": 3.0,

**Example Response:**  "ram_total_gb": 16,

```json  "ram_type": "DDR4",

{  "gpu_model": "NVIDIA RTX 3060",

  "id": 1,  "gpu_memory_gb": 12,

  "hostname": "lab-pc-01",  "gpu_count": 1,

  "ip_address": "192.168.0.10",  "disk_total_gb": 512,

  "department": "Computer Science",  "disk_type": "NVMe",

  "os_type": "Linux",  "os_name": "Windows 10",

  "os_version": "Ubuntu 22.04",  "os_version": "10.0.19044"

  "status": "online",}

  "last_seen": "2025-10-25T14:30:00Z",```

  "created_at": "2025-10-20T10:00:00Z",

  "current_metrics": {**Response (201 Created):**

    "cpu_usage": 25.5,```json

    "ram_usage": 42.3,{

    "disk_usage": 68.9,  "message": "System registered",

    "timestamp": "2025-10-25T14:30:00Z"  "system_id": "550e8400-e29b-41d4-a716-446655440000"

  },}

  "health_state": "healthy"```

}

```**Response (Existing System):**

```json

---{

  "message": "System updated",

### Metrics  "system_id": "550e8400-e29b-41d4-a716-446655440000"

}

#### Get System Metrics```



Returns time-series metrics for a specific system.**Python Example:**

```python

```httpimport requests

GET /systems/{system_id}/metrics

```system_data = {

    "system_id": "550e8400-e29b-41d4-a716-446655440000",

**Path Parameters:**    "hostname": "lab-pc-01",

    "location": "Computer Lab A",

| Parameter | Type | Required | Description |    # ... other fields

|-----------|------|----------|-------------|}

| `system_id` | integer | Yes | System ID |

response = requests.post(

**Query Parameters:**    "http://localhost:8000/api/systems/register",

    json=system_data

| Parameter | Type | Required | Description |)

|-----------|------|----------|-------------|print(response.json())

| `start_time` | string | No | ISO 8601 timestamp (default: 24 hours ago) |```

| `end_time` | string | No | ISO 8601 timestamp (default: now) |

| `limit` | integer | No | Maximum results (default: 1000) |---



**Example Request:**### 4. Submit Metrics

```bash

curl "http://localhost:8000/systems/1/metrics?start_time=2025-10-24T00:00:00Z&limit=100"**POST /api/metrics**

```

Submit system performance metrics.

**Example Response:**

```json**Request Headers:**

{```

  "system_id": 1,Content-Type: application/json

  "hostname": "lab-pc-01",```

  "metrics": [

    {**Request Body:**

      "timestamp": "2025-10-25T14:30:00Z",```json

      "cpu_usage": 25.5,{

      "ram_usage": 42.3,  "system_id": "550e8400-e29b-41d4-a716-446655440000",

      "disk_usage": 68.9  "timestamp": "2025-10-21T10:30:00.000Z",

    },  "cpu_percent": 45.5,

    {  "cpu_per_core": [42.1, 48.3, 44.2, 47.1, 43.5, 46.8, 44.9, 45.2],

      "timestamp": "2025-10-25T14:25:00Z",  "cpu_freq_current": 2800.0,

      "cpu_usage": 22.1,  "cpu_temp": 65.5,

      "ram_usage": 41.8,  "ram_used_gb": 10.2,

      "disk_usage": 68.9  "ram_available_gb": 5.8,

    }  "ram_percent": 63.75,

  ],  "swap_used_gb": 0.5,

  "total": 2,  "swap_percent": 2.0,

  "start_time": "2025-10-24T00:00:00Z",  "gpu_utilization": 25.5,

  "end_time": "2025-10-25T14:30:00Z"  "gpu_memory_used_gb": 3.2,

}  "gpu_memory_percent": 26.7,

```  "gpu_temp": 55.0,

  "disk_read_mb_s": 15.3,

---  "disk_write_mb_s": 8.7,

  "disk_read_ops": 120,

#### Get Latest Metrics for All Systems  "disk_write_ops": 85,

  "disk_io_wait_percent": 5.2,

Returns the most recent metrics for all systems.  "disk_used_gb": 320.5,

  "disk_percent": 62.6,

```http  "net_sent_mb_s": 1.2,

GET /metrics/latest  "net_recv_mb_s": 3.5,

```  "net_packets_sent": 1500,

  "net_packets_recv": 2200,

**Query Parameters:**  "process_count": 156,

  "thread_count": 892,

| Parameter | Type | Required | Description |  "load_avg_1min": 2.3,

|-----------|------|----------|-------------|  "load_avg_5min": 2.1,

| `department` | string | No | Filter by department |  "load_avg_15min": 1.9,

  "collection_duration_ms": 245

**Example Request:**}

```bash```

curl http://localhost:8000/metrics/latest

```**Response (201 Created):**

```json

**Example Response:**{

```json  "message": "Metrics ingested successfully",

{  "timestamp": "2025-10-21T10:30:00.000Z"

  "metrics": [}

    {```

      "system_id": 1,

      "hostname": "lab-pc-01",**Error Responses:**

      "ip_address": "192.168.0.10",

      "department": "Computer Science",**404 - System Not Found:**

      "timestamp": "2025-10-25T14:30:00Z",```json

      "cpu_usage": 25.5,{

      "ram_usage": 42.3,  "detail": "System 550e8400-... not found. Please register first."

      "disk_usage": 68.9}

    },```

    {

      "system_id": 2,**500 - Server Error:**

      "hostname": "lab-pc-02",```json

      "ip_address": "192.168.0.11",{

      "department": "Computer Science",  "detail": "Internal server error message"

      "timestamp": "2025-10-25T14:30:00Z",}

      "cpu_usage": 18.2,```

      "ram_usage": 38.7,

      "disk_usage": 55.4**Python Example:**

    }```python

  ],import requests

  "timestamp": "2025-10-25T14:30:00Z"from datetime import datetime

}

```metrics = {

    "system_id": "550e8400-e29b-41d4-a716-446655440000",

---    "timestamp": datetime.utcnow().isoformat(),

    "cpu_percent": 45.5,

### Departments    "ram_percent": 63.75,

    # ... other metrics

#### List All Departments}



Returns a list of all departments with system counts.response = requests.post(

    "http://localhost:8000/api/metrics",

```http    json=metrics

GET /departments)

```print(response.status_code)  # 201

```

**Example Request:**

```bash---

curl http://localhost:8000/departments

```### 5. List All Systems



**Example Response:****GET /api/systems**

```json

{Get information about all registered systems.

  "departments": [

    {**Request:**

      "name": "Computer Science",```bash

      "system_count": 15,curl http://localhost:8000/api/systems

      "online_count": 12,```

      "offline_count": 3

    },**Response (200 OK):**

    {```json

      "name": "Information Systems",[

      "system_count": 10,  {

      "online_count": 9,    "system_id": "550e8400-e29b-41d4-a716-446655440000",

      "offline_count": 1    "hostname": "lab-pc-01",

    }    "location": "Computer Lab A",

  ],    "department": "Computer Science",

  "total": 2    "status": "active",

}    "cpu_cores": 8,

```    "ram_total_gb": 16,

    "gpu_model": "NVIDIA RTX 3060",

---    "last_seen": "2025-10-21T10:30:00.000Z",

    "created_at": "2025-10-15T08:00:00.000Z"

#### Get Department Systems  },

  // ... more systems

Returns all systems in a specific department.]

```

```http

GET /departments/{department_name}/systems---

```

### 6. System Status

**Path Parameters:**

**GET /api/systems/status**

| Parameter | Type | Required | Description |

|-----------|------|----------|-------------|Get current real-time status of all systems.

| `department_name` | string | Yes | Department name (URL encoded) |

**Request:**

**Example Request:**```bash

```bashcurl http://localhost:8000/api/systems/status

curl http://localhost:8000/departments/Computer%20Science/systems```

```

**Response (200 OK):**

**Example Response:**```json

```json[

{  {

  "department": "Computer Science",    "system_id": "550e8400-e29b-41d4-a716-446655440000",

  "systems": [    "hostname": "lab-pc-01",

    {    "status": "active",

      "id": 1,    "last_seen": "2025-10-21T10:30:00.000Z",

      "hostname": "lab-pc-01",    "current_cpu": 45.5,

      "ip_address": "192.168.0.10",    "current_ram": 63.75,

      "status": "online",    "utilization_status": "normal"

      "current_cpu": 25.5,  },

      "current_ram": 42.3,  // ... more systems

      "current_disk": 68.9]

    }```

  ],

  "total": 15,**Utilization Status Values:**

  "online": 12,- `"overloaded"`: CPU > 90% or RAM > 90%

  "offline": 3- `"underutilized"`: CPU < 20% and RAM < 20%

}- `"normal"`: Within normal range

```

---

---

### 7. System Metrics History

#### Get Department Statistics

**GET /api/systems/{system_id}/metrics**

Returns aggregated statistics for a department.

Get historical metrics for a specific system.

```http

GET /departments/{department_name}/stats**Query Parameters:**

```- `hours` (optional, default: 24): Hours of history to retrieve

- `limit` (optional, default: 100): Maximum number of records

**Query Parameters:**

**Request:**

| Parameter | Type | Required | Description |```bash

|-----------|------|----------|-------------|curl "http://localhost:8000/api/systems/550e8400-e29b-41d4-a716-446655440000/metrics?hours=48&limit=200"

| `start_time` | string | No | ISO 8601 timestamp |```

| `end_time` | string | No | ISO 8601 timestamp |

**Response (200 OK):**

**Example Request:**```json

```bash[

curl http://localhost:8000/departments/Computer%20Science/stats  {

```    "timestamp": "2025-10-21T10:30:00.000Z",

    "cpu_percent": 45.5,

**Example Response:**    "ram_percent": 63.75,

```json    "gpu_utilization": 25.5,

{    "disk_percent": 62.6,

  "department": "Computer Science",    "disk_io_wait_percent": 5.2,

  "period": {    "load_avg_1min": 2.3,

    "start": "2025-10-24T00:00:00Z",    "load_avg_5min": 2.1,

    "end": "2025-10-25T14:30:00Z"    "load_avg_15min": 1.9

  },  },

  "statistics": {  // ... more metrics

    "avg_cpu_usage": 28.5,]

    "max_cpu_usage": 85.2,```

    "min_cpu_usage": 5.1,

    "avg_ram_usage": 45.3,**Python Example:**

    "max_ram_usage": 92.1,```python

    "min_ram_usage": 15.4,import requests

    "avg_disk_usage": 62.7,

    "max_disk_usage": 89.3,response = requests.get(

    "min_disk_usage": 32.1    "http://localhost:8000/api/systems/550e8400-.../metrics",

  },    params={"hours": 48, "limit": 200}

  "system_count": 15)

}metrics = response.json()

``````



------



### Alerts### 8. Top Resource Consumers



#### List Alerts**GET /api/analytics/top-consumers/{resource_type}**



Returns a list of alerts.Get top N systems by resource usage.



```http**Path Parameters:**

GET /alerts- `resource_type`: `cpu`, `ram`, `gpu`, or `disk_io`

```

**Query Parameters:**

**Query Parameters:**- `limit` (optional, default: 10): Number of results

- `hours` (optional, default: 24): Time period

| Parameter | Type | Required | Description |

|-----------|------|----------|-------------|**Request:**

| `system_id` | integer | No | Filter by system ID |```bash

| `severity` | string | No | Filter by severity (warning/critical) |curl "http://localhost:8000/api/analytics/top-consumers/cpu?limit=5&hours=24"

| `start_time` | string | No | ISO 8601 timestamp |```

| `end_time` | string | No | ISO 8601 timestamp |

| `limit` | integer | No | Maximum results (default: 100) |**Response (200 OK):**

```json

**Example Request:**[

```bash  {

curl "http://localhost:8000/alerts?severity=critical&limit=50"    "hostname": "lab-pc-05",

```    "location": "Computer Lab A",

    "avg_usage": 78.5,

**Example Response:**    "max_usage": 95.2,

```json    "current_usage": 72.3

{  },

  "alerts": [  // ... more systems

    {]

      "id": 1,```

      "system_id": 3,

      "hostname": "lab-pc-03",**Python Example:**

      "alert_type": "high_cpu",```python

      "severity": "critical",response = requests.get(

      "message": "CPU usage is 92.5% (threshold: 80%)",    "http://localhost:8000/api/analytics/top-consumers/cpu",

      "value": 92.5,    params={"limit": 5, "hours": 24}

      "threshold": 80,)

      "timestamp": "2025-10-25T14:25:00Z"top_consumers = response.json()

    },```

    {

      "id": 2,---

      "system_id": 5,

      "hostname": "lab-pc-05",### 9. Underutilized Systems

      "alert_type": "high_ram",

      "severity": "warning",**GET /api/analytics/underutilized**

      "message": "RAM usage is 88.3% (threshold: 85%)",

      "value": 88.3,Get list of underutilized systems for optimization.

      "threshold": 85,

      "timestamp": "2025-10-25T14:20:00Z"**Query Parameters:**

    }- `days` (optional, default: 7): Analysis period in days

  ],

  "total": 2**Request:**

}```bash

```curl "http://localhost:8000/api/analytics/underutilized?days=30"

```

---

**Response (200 OK):**

### Health & Monitoring```json

[

#### Health Check  {

    "hostname": "lab-pc-12",

Returns the health status of the API and its dependencies.    "location": "Computer Lab B",

    "cpu_cores": 8,

```http    "ram_total_gb": 16,

GET /health    "avg_cpu_percent": 18.5,

```    "avg_ram_percent": 22.3,

    "utilization_score": 42.5,

**Example Request:**    "period_start": "2025-09-21T00:00:00.000Z"

```bash  },

curl http://localhost:8000/health  // ... more systems

```]

```

**Example Response:**

```json---

{

  "status": "healthy",### 10. Active Alerts

  "timestamp": "2025-10-25T14:30:00Z",

  "version": "1.0.0",**GET /api/alerts/active**

  "dependencies": {

    "database": {Get all unresolved alerts.

      "status": "healthy",

      "response_time_ms": 5**Request:**

    },```bash

    "rabbitmq": {curl http://localhost:8000/api/alerts/active

      "status": "healthy",```

      "response_time_ms": 2

    }**Response (200 OK):**

  },```json

  "uptime_seconds": 86400[

}  {

```    "alert_id": 12345,

    "triggered_at": "2025-10-21T10:25:00.000Z",

---    "severity": "critical",

    "message": "Alert: High CPU Usage on system. cpu_percent: 96.5 > 95 (threshold: 95) for 10 minutes",

#### Prometheus Metrics    "hostname": "lab-pc-05",

    "location": "Computer Lab A",

Returns metrics in Prometheus format for monitoring.    "metric_name": "cpu_percent",

    "actual_value": 96.5,

```http    "threshold_value": 95

GET /metrics  },

```  // ... more alerts

]

**Example Request:**```

```bash

curl http://localhost:8000/metrics---

```

## 🔒 Authentication (Future)

**Example Response:**

```Currently, the API is open for development. For production deployment, implement:

# HELP system_cpu_usage Current CPU usage percentage

# TYPE system_cpu_usage gauge**API Key Authentication:**

system_cpu_usage{hostname="lab-pc-01",ip="192.168.0.10",department="Computer Science"} 25.5```python

system_cpu_usage{hostname="lab-pc-02",ip="192.168.0.11",department="Computer Science"} 18.2headers = {

    "X-API-Key": "your-api-key-here",

# HELP system_ram_usage Current RAM usage percentage    "Content-Type": "application/json"

# TYPE system_ram_usage gauge}

system_ram_usage{hostname="lab-pc-01",ip="192.168.0.10",department="Computer Science"} 42.3```

system_ram_usage{hostname="lab-pc-02",ip="192.168.0.11",department="Computer Science"} 38.7

**JWT Token Authentication:**

# HELP system_disk_usage Current disk usage percentage```python

# TYPE system_disk_usage gaugeheaders = {

system_disk_usage{hostname="lab-pc-01",ip="192.168.0.10",department="Computer Science"} 68.9    "Authorization": "Bearer YOUR_JWT_TOKEN",

system_disk_usage{hostname="lab-pc-02",ip="192.168.0.11",department="Computer Science"} 55.4    "Content-Type": "application/json"

}

# HELP system_status System online status (1=online, 0=offline)```

# TYPE system_status gauge

system_status{hostname="lab-pc-01",ip="192.168.0.10",department="Computer Science"} 1---

system_status{hostname="lab-pc-02",ip="192.168.0.11",department="Computer Science"} 1

```## 📊 Rate Limiting (Recommended for Production)



---Suggested limits:

- **Data ingestion** (`/api/metrics`): 1 request per 5 minutes per system

## Error Codes- **Query endpoints**: 100 requests per minute per client

- **Analytics endpoints**: 10 requests per minute per client

| Code | Description |

|------|-------------|---

| `SYSTEM_NOT_FOUND` | System with specified ID does not exist |

| `DEPARTMENT_NOT_FOUND` | Department does not exist |## ⚠️ Error Codes

| `INVALID_PARAMETER` | Invalid query parameter value |

| `DATABASE_ERROR` | Database connection or query error || Code | Meaning | Example |

| `INTERNAL_ERROR` | Internal server error ||------|---------|---------|

| 200 | Success | GET requests |

---| 201 | Created | POST metrics/systems |

| 400 | Bad Request | Invalid data format |

## Rate Limiting| 404 | Not Found | System/resource doesn't exist |

| 500 | Server Error | Database connection failed |

Currently, no rate limiting is implemented. For production:

---

- Recommended: 1000 requests per minute per IP

- Implement using middleware or reverse proxy## 🧪 Testing



---### Using cURL



## CORS```bash

# Health check

CORS is enabled for all origins in development. For production, configure allowed origins:curl http://localhost:8000/health



```python# Get systems

# api/main.pycurl http://localhost:8000/api/systems

app.add_middleware(

    CORSMiddleware,# Post metrics

    allow_origins=["https://yourdomain.com"],curl -X POST http://localhost:8000/api/metrics \

    allow_credentials=True,  -H "Content-Type: application/json" \

    allow_methods=["*"],  -d '{"system_id": "...", "cpu_percent": 45.5, ...}'

    allow_headers=["*"],```

)

```### Using Python



---```python

import requests

## Pagination

# Health check

For endpoints returning lists, use `limit` and `offset` parameters:response = requests.get("http://localhost:8000/health")

print(response.json())

```bash

# Get first 50 results# Get systems

curl "http://localhost:8000/systems?limit=50&offset=0"response = requests.get("http://localhost:8000/api/systems")

systems = response.json()

# Get next 50 results

curl "http://localhost:8000/systems?limit=50&offset=50"# Post metrics

```metrics = {"system_id": "...", "cpu_percent": 45.5}

response = requests.post("http://localhost:8000/api/metrics", json=metrics)

---```



## WebSocket Support (Future)### Using Postman



Real-time metric updates via WebSocket (planned for v2.0):1. Import collection from `/docs/api_collection.json` (if available)

2. Set base URL: `http://localhost:8000`

```javascript3. Test endpoints

const ws = new WebSocket('ws://localhost:8000/ws/metrics');

ws.onmessage = (event) => {---

  const data = JSON.parse(event.data);

  console.log('Real-time metrics:', data);## 📚 Interactive Documentation

};

```Visit http://localhost:8000/docs for interactive Swagger UI:

- Test endpoints directly

---- View request/response schemas

- Try out API calls

## Examples

Alternative: http://localhost:8000/redoc for ReDoc documentation

### Python

---

```python

import requests## 🔗 WebSocket Support (Future Enhancement)



# Get all systemsFor real-time updates:

response = requests.get('http://localhost:8000/systems')

systems = response.json()['systems']```python

# WebSocket endpoint (future)

# Get metrics for a systemws://localhost:8000/ws/metrics/{system_id}

response = requests.get('http://localhost:8000/systems/1/metrics')

metrics = response.json()['metrics']# Client code

import websockets

# Get department statsasync with websockets.connect('ws://localhost:8000/ws/metrics/...') as websocket:

response = requests.get('http://localhost:8000/departments/Computer%20Science/stats')    while True:

stats = response.json()['statistics']        data = await websocket.recv()

```        print(data)

```

### JavaScript

---

```javascript

// Get all systems## 📝 Notes

fetch('http://localhost:8000/systems')

  .then(response => response.json())- All timestamps are in **ISO 8601 format** (UTC)

  .then(data => console.log(data.systems));- All sizes are in **GB** (gigabytes)

- All rates are in **MB/s** (megabytes per second)

// Get metrics- All percentages are **0-100** range

fetch('http://localhost:8000/systems/1/metrics?limit=100')- System IDs are **UUIDv4** format

  .then(response => response.json())

  .then(data => console.log(data.metrics));---

```

**API Version**: 1.0  

### cURL**Last Updated**: October 21, 2025  

**Documentation**: Auto-generated from FastAPI

```bash
# Get health status
curl http://localhost:8000/health

# Get systems with filters
curl "http://localhost:8000/systems?department=Computer%20Science&status=online"

# Get metrics with time range
curl "http://localhost:8000/systems/1/metrics?start_time=2025-10-24T00:00:00Z&end_time=2025-10-25T00:00:00Z"

# Get Prometheus metrics
curl http://localhost:8000/metrics
```

---

## Support

For API issues or questions:

1. Check the [Installation Guide](INSTALLATION.md)
2. Review [Architecture Documentation](ARCHITECTURE.md)
3. Open an issue on [GitHub](https://github.com/noiseless47/optilab-smart-lab-utilization/issues)
