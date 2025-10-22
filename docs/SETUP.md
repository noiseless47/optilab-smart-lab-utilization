# Setup Guide
## Smart Resource Utilization & Hardware Optimization System

This guide will walk you through setting up the complete system from scratch.

---

## 📋 Prerequisites

### System Requirements
- **Operating System**: Windows 10/11, Ubuntu 20.04+, or macOS
- **RAM**: Minimum 4 GB (8 GB recommended)
- **Disk Space**: 10 GB free space

### Software Requirements
- **PostgreSQL** 14+ or **TimescaleDB** 2.0+
- **Python** 3.8 or higher
- **pip** (Python package manager)
- **Git** (optional, for version control)

---

## 🗄️ Step 1: Database Setup

### Option A: PostgreSQL Installation

#### Windows (PowerShell):
```powershell
# Download PostgreSQL installer from postgresql.org
# Or use Chocolatey:
choco install postgresql

# Start PostgreSQL service
Start-Service postgresql
```

#### Ubuntu/Linux:
```bash
sudo apt update
sudo apt install postgresql postgresql-contrib
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

### Option B: TimescaleDB Installation (Recommended for better time-series performance)

#### Ubuntu/Linux:
```bash
# Add TimescaleDB repository
sudo sh -c "echo 'deb https://packagecloud.io/timescale/timescaledb/ubuntu/ $(lsb_release -c -s) main' > /etc/apt/sources.list.d/timescaledb.list"
wget --quiet -O - https://packagecloud.io/timescale/timescaledb/gpgkey | sudo apt-key add -
sudo apt update

# Install TimescaleDB
sudo apt install timescaledb-2-postgresql-14

# Tune PostgreSQL configuration
sudo timescaledb-tune --quiet --yes

# Restart PostgreSQL
sudo systemctl restart postgresql
```

#### Windows:
Download TimescaleDB installer from: https://docs.timescale.com/install/latest/windows/

### Create Database

```powershell
# Connect to PostgreSQL (Windows PowerShell)
psql -U postgres

# Or on Linux:
# sudo -u postgres psql
```

```sql
-- In PostgreSQL prompt:
CREATE DATABASE lab_resource_monitor;
\c lab_resource_monitor

-- Create user for the application
CREATE USER lab_monitor WITH PASSWORD 'your_secure_password';
GRANT ALL PRIVILEGES ON DATABASE lab_resource_monitor TO lab_monitor;

-- Exit
\q
```

### Load Database Schema

```powershell
# Navigate to project directory
cd d:\dbms

# Load schema
psql -U postgres -d lab_resource_monitor -f database/schema.sql

# If using TimescaleDB, also run:
psql -U postgres -d lab_resource_monitor -f database/timescale_setup.sql

# Load stored procedures
psql -U postgres -d lab_resource_monitor -f database/stored_procedures.sql

# Load triggers
psql -U postgres -d lab_resource_monitor -f database/triggers.sql

# Create indexes
psql -U postgres -d lab_resource_monitor -f database/indexes.sql
```

### Verify Database Setup

```sql
-- Connect to database
psql -U postgres -d lab_resource_monitor

-- Check tables
\dt

-- Check functions
\df

-- Check triggers
SELECT trigger_name, event_object_table FROM information_schema.triggers;

-- Check TimescaleDB hypertables (if applicable)
SELECT * FROM timescaledb_information.hypertables;
```

---

## 🐍 Step 2: Python Environment Setup

### Create Virtual Environment (Recommended)

```powershell
# Windows PowerShell
cd d:\dbms
python -m venv venv
.\venv\Scripts\Activate.ps1

# Linux/Mac
cd /path/to/dbms
python3 -m venv venv
source venv/bin/activate
```

### Install Agent Dependencies

```powershell
cd agent
pip install -r requirements.txt
```

**Common Issues:**
- If `GPUtil` installation fails on Linux, you may need: `sudo apt install python3-dev`
- On Windows, ensure you have Visual C++ Build Tools if compilation is needed

---

## 🚀 Step 3: API Server Setup

### Install API Dependencies

```powershell
cd ..\api
pip install -r requirements.txt
```

### Configure Environment Variables

```powershell
# Create .env file from example
cp .env.example .env

# Edit .env with your database credentials
# Use notepad or any text editor:
notepad .env
```

**.env Configuration:**
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=lab_resource_monitor
DB_USER=lab_monitor
DB_PASSWORD=your_secure_password
```

### Test API Server

```powershell
# Start the API server
python main.py
```

The server should start on `http://localhost:8000`

**Verify:**
- Open browser to: `http://localhost:8000`
- API docs: `http://localhost:8000/docs`
- Health check: `http://localhost:8000/health`

---

## 📊 Step 4: Configure Data Collection Agent

### Configure Agent Settings

```powershell
cd ..\agent
notepad config.yaml
```

**Update config.yaml:**
```yaml
api:
  endpoint: "http://localhost:8000/api/metrics"
  
system:
  location: "Computer Lab A"  # Update with actual location
  department: "Computer Science"  # Update with department
```

### Test Agent

```powershell
# Run agent once to test
python collector.py
```

**Expected Output:**
```
INFO - Metrics collector initialized for HOSTNAME (ID: ...)
INFO - System registered successfully
INFO - Metrics collected in XXXms
INFO - Metrics sent successfully
```

Press `Ctrl+C` to stop after one successful collection.

---

## 🔧 Step 5: Deploy to Multiple Systems

### On Each Lab Machine:

1. **Copy agent files:**
```powershell
# Copy the agent folder to each machine
# d:\dbms\agent\
```

2. **Install dependencies:**
```powershell
cd d:\dbms\agent
pip install -r requirements.txt
```

3. **Update config.yaml:**
```yaml
api:
  endpoint: "http://YOUR_SERVER_IP:8000/api/metrics"
  
system:
  location: "Lab B - Station 5"  # Unique location per machine
  department: "Computer Science"
```

4. **Run agent as background service:**

**Windows (Task Scheduler):**
- Create task: `Task Scheduler` → `Create Basic Task`
- Trigger: `At startup`
- Action: `Start a program`
- Program: `pythonw.exe`
- Arguments: `d:\dbms\agent\collector.py`

**Linux (systemd):**
```bash
sudo nano /etc/systemd/system/lab-monitor.service
```

```ini
[Unit]
Description=Lab Resource Monitor Agent
After=network.target

[Service]
Type=simple
User=labuser
WorkingDirectory=/opt/dbms/agent
ExecStart=/usr/bin/python3 /opt/dbms/agent/collector.py
Restart=always

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable lab-monitor
sudo systemctl start lab-monitor
sudo systemctl status lab-monitor
```

---

## 📈 Step 6: Verification & Testing

### Check Data Collection

```sql
-- Connect to database
psql -U postgres -d lab_resource_monitor

-- Check registered systems
SELECT system_id, hostname, location, last_seen FROM systems;

-- Check recent metrics
SELECT 
    s.hostname, 
    um.timestamp, 
    um.cpu_percent, 
    um.ram_percent 
FROM usage_metrics um
JOIN systems s ON um.system_id = s.system_id
ORDER BY um.timestamp DESC
LIMIT 10;

-- Check alerts
SELECT * FROM alert_logs ORDER BY triggered_at DESC LIMIT 5;
```

### Generate Test Summary

```sql
-- Generate daily summary for yesterday
CALL generate_daily_summary(
    (SELECT system_id FROM systems LIMIT 1),
    CURRENT_DATE - 1
);

-- Check summary
SELECT * FROM performance_summaries ORDER BY created_at DESC LIMIT 5;
```

---

## 🎨 Step 7: Optional - Grafana Dashboard

### Install Grafana

**Windows:**
```powershell
choco install grafana
```

**Linux:**
```bash
sudo apt-get install -y software-properties-common
sudo add-apt-repository "deb https://packages.grafana.com/oss/deb stable main"
wget -q -O - https://packages.grafana.com/gpg.key | sudo apt-key add -
sudo apt-get update
sudo apt-get install grafana
sudo systemctl start grafana-server
sudo systemctl enable grafana-server
```

### Configure Data Source

1. Open Grafana: `http://localhost:3000` (default login: admin/admin)
2. Add PostgreSQL data source:
   - **Host**: `localhost:5432`
   - **Database**: `lab_resource_monitor`
   - **User**: `lab_monitor`
   - **SSL Mode**: `disable` (for local testing)
   - **TimescaleDB**: Enable if using TimescaleDB

3. Import dashboard (sample queries from `sample_queries.sql`)

---

## 🔒 Security Hardening (Production)

### Database Security

```sql
-- Create read-only role for Grafana
CREATE ROLE grafana_readonly;
GRANT CONNECT ON DATABASE lab_resource_monitor TO grafana_readonly;
GRANT USAGE ON SCHEMA public TO grafana_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_readonly;

-- Create limited write role for agents
CREATE ROLE agent_writer;
GRANT CONNECT ON DATABASE lab_resource_monitor TO agent_writer;
GRANT INSERT ON usage_metrics, user_sessions TO agent_writer;
GRANT SELECT ON systems TO agent_writer;
```

### API Security

Add to `api/main.py`:
```python
from fastapi.security import APIKeyHeader

API_KEY = os.getenv('API_KEY')
api_key_header = APIKeyHeader(name="X-API-Key")

async def verify_api_key(api_key: str = Depends(api_key_header)):
    if api_key != API_KEY:
        raise HTTPException(status_code=403, detail="Invalid API key")
```

### Network Security

- Run API behind **nginx** or **Apache** reverse proxy with HTTPS
- Use **firewall rules** to restrict database access
- Enable **SSL/TLS** for PostgreSQL connections

---

## 🐛 Troubleshooting

### Agent Can't Connect to API

```powershell
# Test API endpoint
curl http://localhost:8000/health

# Check firewall
# Windows: Add inbound rule for port 8000
# Linux: sudo ufw allow 8000
```

### Database Connection Issues

```sql
-- Check PostgreSQL is running
# Windows:
Get-Service postgresql*

# Linux:
sudo systemctl status postgresql

-- Check connection
psql -U postgres -d lab_resource_monitor
```

### No Metrics Being Collected

1. Check agent logs: `agent/agent.log`
2. Verify system is registered: `SELECT * FROM systems;`
3. Check API logs for errors
4. Verify network connectivity between agent and API

---

## 📚 Next Steps

1. **Set up automated reporting**: Use stored procedures to generate weekly/monthly reports
2. **Configure alerts**: Adjust alert thresholds in `alert_rules` table
3. **Customize dashboards**: Create Grafana dashboards for your specific needs
4. **Scale**: Deploy to all lab machines
5. **Analyze**: Use sample queries to identify optimization opportunities

---

## 📞 Support & Resources

- **Database Schema**: See `docs/DATABASE_DESIGN.md`
- **API Reference**: See `docs/API_REFERENCE.md`
- **Sample Queries**: `database/sample_queries.sql`
- **PostgreSQL Docs**: https://www.postgresql.org/docs/
- **TimescaleDB Docs**: https://docs.timescale.com/

---

**Setup Complete! 🎉**

Your Smart Resource Utilization & Hardware Optimization System is now running!
