# Installation Guide

Complete installation instructions for OptiLab Smart Lab Resource Monitoring System.

## Table of Contents

- [System Requirements](#system-requirements)
- [Database Setup](#database-setup)
- [Python Environment](#python-environment)
- [Configuration](#configuration)
- [Optional Components](#optional-components)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

## System Requirements

### Minimum Requirements

- **Operating System**: Windows 10/11, Linux (Ubuntu 20.04+), macOS 12+
- **Python**: 3.11 or higher
- **PostgreSQL**: 18.x
- **RAM**: 4 GB minimum, 8 GB recommended
- **Disk**: 10 GB free space
- **Network**: Access to monitored systems via SSH

### Target Systems Requirements

- **Linux systems**: SSH enabled
- **Network**: Accessible from monitoring server
- **Firewall**: Port 22 (SSH) open

## Database Setup

### 1. Install PostgreSQL

**Windows:**
```powershell
# Download installer from postgresql.org
# Run installer and note the password

# Verify installation
psql --version
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

**macOS:**
```bash
brew install postgresql@18
brew services start postgresql@18
```

### 2. Create Database

```bash
# Connect to PostgreSQL
psql -U postgres

# Create database
CREATE DATABASE lab_resource_monitor;

# Create user (optional)
CREATE USER lab_monitor WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE lab_resource_monitor TO lab_monitor;

# Exit
\q
```

### 3. Initialize Schema

```bash
# Run schema creation
psql -U postgres -d lab_resource_monitor -f database/schema.sql

# Verify tables
psql -U postgres -d lab_resource_monitor -c "\dt"
```

Expected output:
```
              List of relations
 Schema |      Name       | Type  |  Owner   
--------+-----------------+-------+----------
 public | systems         | table | postgres
 public | usage_metrics   | table | postgres
 public | alerts          | table | postgres
```

## Python Environment

### 1. Clone Repository

```bash
git clone https://github.com/noiseless47/optilab-smart-lab-utilization.git
cd optilab-smart-lab-utilization
```

### 2. Create Virtual Environment

**Windows:**
```powershell
python -m venv venv
venv\Scripts\activate
```

**Linux/macOS:**
```bash
python3 -m venv venv
source venv/bin/activate
```

### 3. Install Dependencies

```bash
# Install collector dependencies
pip install -r collector/requirements.txt

# Install API dependencies
pip install -r api/requirements.txt
```

Installed packages include:
- **Collector**: paramiko, psycopg2-binary, pika, asyncssh, gevent, structlog
- **API**: fastapi, uvicorn, psycopg2-binary, prometheus-client

## Configuration

### 1. Create Environment File

Create a `.env` file in the project root:

```bash
# Database Configuration
DB_HOST=localhost
DB_PORT=5432
DB_NAME=lab_resource_monitor
DB_USER=postgres
DB_PASSWORD=your_password

# SSH Configuration
SSH_USERNAME=your_ssh_user
SSH_PASSWORD=your_ssh_password

# Optional: RabbitMQ Configuration
RABBITMQ_HOST=localhost
RABBITMQ_PORT=5672
RABBITMQ_USER=guest
RABBITMQ_PASSWORD=guest

# Optional: API Configuration
API_HOST=0.0.0.0
API_PORT=8000
```

### 2. Configure Collector Settings

Edit `collector/network_collector.py` if needed:

```python
# Polling interval (seconds)
POLL_INTERVAL = 300  # 5 minutes

# Alert thresholds
CPU_THRESHOLD = 80    # 80%
RAM_THRESHOLD = 85    # 85%
DISK_THRESHOLD = 90   # 90%

# Network scan settings
SCAN_TIMEOUT = 2      # seconds
```

### 3. Test Database Connection

```bash
cd collector
python -c "import psycopg2; conn = psycopg2.connect(
    host='localhost',
    port=5432,
    database='lab_resource_monitor',
    user='postgres',
    password='your_password'
); print('✓ Database connection successful'); conn.close()"
```

## Optional Components

### TimescaleDB (Recommended)

TimescaleDB improves query performance by 75x and reduces storage by 90%.

**1. Install TimescaleDB Extension**

**Windows:**
```powershell
# Download from https://docs.timescale.com/install/latest/self-hosted/installation-windows/
# Run installer
```

**Linux (Ubuntu/Debian):**
```bash
# Add TimescaleDB repository
sudo sh -c "echo 'deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main' > /etc/apt/sources.list.d/timescaledb.list"
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add -
sudo apt update

# Install TimescaleDB
sudo apt install timescaledb-2-postgresql-18

# Configure
sudo timescaledb-tune

# Restart PostgreSQL
sudo systemctl restart postgresql
```

**2. Enable TimescaleDB**

```bash
# Run setup script
psql -U postgres -d lab_resource_monitor -f database/setup_timescaledb.sql
```

**3. Verify Installation**

```bash
psql -U postgres -d lab_resource_monitor -c "SELECT * FROM timescaledb_information.hypertables;"
```

### RabbitMQ (Optional)

For high-scale deployments with message queue processing.

**Using Docker (Recommended):**
```bash
docker run -d \
  --name rabbitmq \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:3-management
```

**Without Docker:**

**Windows:**
```powershell
# Download from https://www.rabbitmq.com/download.html
# Run installer
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt install rabbitmq-server
sudo systemctl start rabbitmq-server
sudo systemctl enable rabbitmq-server
```

**Verify:**
- Management UI: http://localhost:15672
- Default credentials: `guest` / `guest`

## Verification

### 1. Test System Discovery

```bash
cd collector
python network_collector.py --scan 192.168.0.0/24 --dept "Test Department"
```

Expected output:
```
Scanning network 192.168.0.0/24...
Found 5 systems:
  - 192.168.0.10 (Ubuntu 22.04)
  - 192.168.0.11 (Ubuntu 22.04)
  - 192.168.0.12 (Ubuntu 22.04)
✓ Saved 5 systems to database
```

### 2. Test Metric Collection

```bash
python network_collector.py --collect --once
```

Expected output:
```
Collecting metrics from 5 systems...
✓ 192.168.0.10 - CPU: 15%, RAM: 45%, Disk: 60%
✓ 192.168.0.11 - CPU: 22%, RAM: 38%, Disk: 55%
✓ Saved 5 metric readings to database
```

### 3. Start API Server

```bash
cd ../api
uvicorn main:app --reload
```

Expected output:
```
INFO:     Uvicorn running on http://127.0.0.1:8000
INFO:     Application startup complete.
```

### 4. Test API Endpoints

```bash
# Health check
curl http://localhost:8000/health

# Get all systems
curl http://localhost:8000/systems

# Get Prometheus metrics
curl http://localhost:8000/metrics
```

## Troubleshooting

### Database Connection Issues

**Problem**: `psycopg2.OperationalError: could not connect to server`

**Solutions**:
1. Check PostgreSQL is running:
   ```bash
   # Windows
   sc query postgresql
   
   # Linux
   sudo systemctl status postgresql
   ```

2. Verify credentials in `.env`
3. Check `pg_hba.conf` allows local connections
4. Ensure PostgreSQL is listening on port 5432:
   ```bash
   netstat -an | grep 5432
   ```

### SSH Connection Failed

**Problem**: `paramiko.ssh_exception.AuthenticationException`

**Solutions**:
1. Verify SSH credentials
2. Test manual connection:
   ```bash
   ssh username@192.168.0.10
   ```
3. Check SSH is enabled on target systems
4. Verify firewall allows port 22

### No Systems Discovered

**Problem**: Network scan finds 0 systems

**Solutions**:
1. Verify network range is correct
2. Check systems are powered on
3. Ping test: `ping 192.168.0.10`
4. Verify SSH port is open:
   ```bash
   nmap -p 22 192.168.0.10
   ```

### Module Import Errors

**Problem**: `ModuleNotFoundError: No module named 'paramiko'`

**Solutions**:
1. Ensure virtual environment is activated
2. Reinstall dependencies:
   ```bash
   pip install -r collector/requirements.txt
   ```
3. Check Python version: `python --version` (should be 3.11+)

### TimescaleDB Extension Not Found

**Problem**: `ERROR: could not open extension control file`

**Solutions**:
1. Verify TimescaleDB is installed:
   ```bash
   dpkg -l | grep timescaledb  # Linux
   ```
2. Check PostgreSQL version matches (18.x)
3. Restart PostgreSQL after installation
4. Run as superuser:
   ```bash
   psql -U postgres -d lab_resource_monitor
   ```

### High Memory Usage

**Problem**: Collector consuming excessive memory

**Solutions**:
1. Enable RabbitMQ for queue-based processing
2. Reduce connection pool size in `connection_pool.py`:
   ```python
   max_connections=5  # Default is 10
   ```
3. Increase polling interval in `network_collector.py`:
   ```python
   POLL_INTERVAL = 600  # 10 minutes instead of 5
   ```

### Port Already in Use

**Problem**: `OSError: [Errno 98] Address already in use`

**Solutions**:
1. Check what's using the port:
   ```bash
   # Windows
   netstat -ano | findstr :8000
   
   # Linux
   lsof -i :8000
   ```
2. Kill the process or use a different port:
   ```bash
   uvicorn main:app --port 8001
   ```

## Next Steps

After successful installation:

1. **Schedule regular collection**: Set up a cron job or Windows Task Scheduler
2. **Configure alerts**: Customize thresholds in the database
3. **Set up monitoring**: Add Prometheus scraping for the `/metrics` endpoint
4. **Enable TimescaleDB**: For production deployments
5. **Deploy RabbitMQ**: For high-scale environments

## Support

If you encounter issues not covered here:

1. Check the [API Reference](API_REFERENCE.md) for endpoint details
2. Review [Architecture](ARCHITECTURE.md) for system design
3. Open an issue on [GitHub](https://github.com/noiseless47/optilab-smart-lab-utilization/issues)
