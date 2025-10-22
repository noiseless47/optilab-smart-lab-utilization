# 🚀 Quick Start Guide
## Get Your System Running in 15 Minutes

---

## Prerequisites Checklist

- [ ] PostgreSQL 14+ installed
- [ ] Python 3.8+ installed
- [ ] Git (optional)

---

## Step 1: Database Setup (5 minutes)

### Create Database

Open PowerShell:

```powershell
# Connect to PostgreSQL
psql -U postgres

# In psql prompt:
CREATE DATABASE lab_resource_monitor;
\c lab_resource_monitor
\q
```

### Load Schema

```powershell
cd d:\dbms

# Load all database files
psql -U postgres -d lab_resource_monitor -f database/schema.sql
psql -U postgres -d lab_resource_monitor -f database/stored_procedures.sql
psql -U postgres -d lab_resource_monitor -f database/triggers.sql
psql -U postgres -d lab_resource_monitor -f database/indexes.sql
```

**Optional (TimescaleDB):**
```powershell
psql -U postgres -d lab_resource_monitor -f database/timescale_setup.sql
```

---

## Step 2: Python Setup (3 minutes)

### Install Dependencies

```powershell
# Create virtual environment
cd d:\dbms
python -m venv venv
.\venv\Scripts\Activate.ps1

# Install agent dependencies
cd agent
pip install -r requirements.txt

# Install API dependencies
cd ..\api
pip install -r requirements.txt
```

---

## Step 3: Configuration (2 minutes)

### Configure API

```powershell
cd d:\dbms\api

# Copy environment template
cp .env.example .env

# Edit .env file (use notepad or your preferred editor)
notepad .env
```

Update `.env`:
```env
DB_HOST=localhost
DB_PORT=5432
DB_NAME=lab_resource_monitor
DB_USER=postgres
DB_PASSWORD=your_password
```

### Configure Agent

```powershell
cd ..\agent
notepad config.yaml
```

Update `config.yaml`:
```yaml
api:
  endpoint: "http://localhost:8000/api/metrics"
  
system:
  location: "Your Lab Name"
  department: "Your Department"
```

---

## Step 4: Run the System (5 minutes)

### Terminal 1: Start API Server

```powershell
cd d:\dbms\api
.\venv\Scripts\Activate.ps1
python main.py
```

**Expected output:**
```
INFO:     Started server process [XXXX]
INFO:     Uvicorn running on http://0.0.0.0:8000
```

**Verify**: Open browser to http://localhost:8000
You should see API info page.

### Terminal 2: Start Collection Agent

```powershell
# Open new PowerShell window
cd d:\dbms\agent
.\venv\Scripts\Activate.ps1
python collector.py
```

**Expected output:**
```
INFO - Metrics collector initialized for HOSTNAME (ID: ...)
INFO - System registered successfully
INFO - Metrics collected in XXXms
INFO - Metrics sent successfully
```

---

## Step 5: Verify Data Collection (2 minutes)

### Check Database

```powershell
psql -U postgres -d lab_resource_monitor
```

```sql
-- Check registered systems
SELECT system_id, hostname, location, created_at FROM systems;

-- Check collected metrics (wait 5-10 minutes for first collection)
SELECT 
    s.hostname, 
    um.timestamp, 
    um.cpu_percent, 
    um.ram_percent 
FROM usage_metrics um
JOIN systems s ON um.system_id = s.system_id
ORDER BY um.timestamp DESC
LIMIT 5;

-- Exit
\q
```

---

## Step 6: Test Analytics (Optional)

### Run Sample Queries

```sql
-- Current system status
SELECT * FROM current_system_status;

-- Generate daily summary (after collecting data for a day)
CALL generate_daily_summary(
    (SELECT system_id FROM systems LIMIT 1),
    CURRENT_DATE - 1
);

-- View summaries
SELECT * FROM performance_summaries ORDER BY created_at DESC;

-- Check active alerts
SELECT * FROM alert_logs WHERE resolved_at IS NULL;
```

---

## 🎉 Success!

Your system is now:
- ✅ Collecting metrics every 5 minutes
- ✅ Storing data in PostgreSQL
- ✅ Auto-generating alerts via triggers
- ✅ Ready for analytics queries

---

## 📊 Next Steps

### 1. Explore the API

Open browser to:
- **API Documentation**: http://localhost:8000/docs
- **Health Check**: http://localhost:8000/health
- **Systems Status**: http://localhost:8000/api/systems/status

### 2. Try Analytics Queries

See `database/sample_queries.sql` for ready-to-use queries:
- Underutilized systems
- Hardware upgrade recommendations
- Peak usage analysis
- Resource consumption rankings

### 3. Deploy to Multiple Machines

Copy `agent/` folder to other lab machines and update their `config.yaml` with unique locations.

### 4. Set Up Dashboard (Optional)

Install Grafana and connect to your PostgreSQL database for visualization.

---

## 🐛 Troubleshooting

### Agent Can't Connect to API

**Error**: `Connection refused` or `Failed to send metrics`

**Fix**:
```powershell
# Check if API is running
curl http://localhost:8000/health

# Check firewall (Windows)
New-NetFirewallRule -DisplayName "Lab Monitor API" -Direction Inbound -LocalPort 8000 -Protocol TCP -Action Allow
```

### Database Connection Failed

**Error**: `password authentication failed`

**Fix**:
```powershell
# Reset PostgreSQL password
psql -U postgres
ALTER USER postgres PASSWORD 'new_password';
```

Update `.env` file with new password.

### No Metrics Appearing

**Check**:
1. Agent is running without errors
2. System is registered: `SELECT * FROM systems;`
3. Wait 5 minutes for first collection cycle

---

## 📚 Documentation

For detailed information, see:

- **Full Setup Guide**: `docs/SETUP.md`
- **Database Design**: `docs/DATABASE_DESIGN.md`
- **Presentation Guide**: `docs/PRESENTATION_GUIDE.md`
- **Sample Queries**: `database/sample_queries.sql`

---

## 💡 Quick Commands Reference

### Start API Server
```powershell
cd d:\dbms\api
.\venv\Scripts\Activate.ps1
python main.py
```

### Start Agent
```powershell
cd d:\dbms\agent
.\venv\Scripts\Activate.ps1
python collector.py
```

### Connect to Database
```powershell
psql -U postgres -d lab_resource_monitor
```

### Check Logs
```powershell
# Agent logs
type d:\dbms\agent\agent.log

# API logs (in terminal where API is running)
```

---

## 🎯 System Verification Checklist

After setup, verify:

- [ ] API responds at http://localhost:8000
- [ ] Agent running without errors
- [ ] System registered in `systems` table
- [ ] Metrics appearing in `usage_metrics` table
- [ ] Alerts created when thresholds exceeded
- [ ] Sample queries return results

---

**All working? Congratulations! 🎊**

Your Smart Resource Utilization & Hardware Optimization System is fully operational!
