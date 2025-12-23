# OptiLab Smart Lab Utilization System - AI Assistant Prompt

## System Overview

You are assisting with the OptiLab Smart Lab Utilization system, which monitors computer systems in academic labs using SSH-based discovery and REST APIs.

## Architecture

### 1. Scanner Component (`scanner/`)
- **Purpose**: Network discovery and system monitoring
- **Main Script**: `network_monitor.py`
- **Configuration**: `config.json`
- **Data Collection**: `get_system_info.sh`

**Key Features:**
- SSH-based system discovery using user "rvce"
- Hardware data collection (CPU, RAM, disk, GPU)
- Database insertion with lab/department validation
- Heartbeat monitoring for system status

### 2. Backend API (`backend/`)
- **Framework**: Express.js with Node.js
- **Database**: PostgreSQL with TimescaleDB
- **Connection**: `postgres://aayush:Aayush1234@localhost:5433/optilab_mvp`
- **Port**: 3000

**API Endpoints:**
- `GET/POST /hod` - HOD management
- `GET/POST/PUT/DELETE /departments` - Department CRUD
- `GET/POST /departments/:deptID/labs` - Lab management
- `GET /departments/:deptID/labs/:labID/sysID/:sysID` - System metrics
- `GET /departments/:deptID/labs/:labID/maintenance` - Maintenance logs

### 3. Database Schema (`database/`)
- **Engine**: PostgreSQL 16 with TimescaleDB
- **Port**: 5433
- **Key Tables**:
  - `systems` - Discovered systems with hardware specs
  - `departments` - Academic departments
  - `labs` - Laboratory facilities
  - `hods` - Heads of departments
  - `metrics` - Time-series performance data

## Current System Status

### ✅ Working Components:
- SSH connections to target systems (user: "rvce")
- Hardware data collection via `get_system_info.sh --json`
- Database connections (scanner + backend)
- REST API endpoints with proper model instantiation
- Lab/department validation before system insertion

### 🔧 Recent Fixes Applied:
- Fixed route path duplication (`/hod/hod` → `/hod`)
- Added proper model class instantiation
- Fixed JSON output in `get_system_info.sh`
- Corrected database connection strings
- Added lab/department relationship validation

### 📊 Current Data:
- **Discovered System**: rvce-ThinkCentre-M75s-Gen-5 (192.168.0.11)
- **Hardware**: AMD Ryzen 7 8700G, 16 cores, 30.51GB RAM, 1.8T disk
- **Association**: Lab ID 1, Department ID 1

## Common Issues & Solutions

### SSH Connection Issues:
- Check SSH keys are properly configured for user "rvce"
- Verify target system is reachable on port 22
- Ensure `get_system_info.sh` has execute permissions

### Database Connection Issues:
- PostgreSQL must be running on port 5433
- User "aayush" must have password "Aayush1234"
- Database "optilab_mvp" must exist with proper schema

### API Route Issues:
- Ensure all model classes are properly instantiated: `const model = new ModelClass()`
- Check route paths don't have duplication
- Verify database connections in route handlers

### JSON Parsing Issues:
- `get_system_info.sh --json` should output ONLY JSON (no extra text)
- Check for bash syntax errors in the script
- Verify all required fields are present in JSON output

## Testing Commands

### Scanner Testing:
```bash
cd scanner
python3 network_monitor.py scan      # Discover systems
python3 network_monitor.py heartbeat # Check system status
```

### Backend Testing:
```bash
cd backend
npm run dev                          # Start API server
# Then use Thunder Client for API testing
```

### Database Testing:
```bash
PGPASSWORD=Aayush1234 psql -h localhost -p 5433 -U aayush -d optilab_mvp
# Check tables: \dt
# Query systems: SELECT * FROM systems;
```

## Current Issue Context

**Problem Description:** Scanner script was unable to properly parse system information due to `get_system_info.sh` outputting human-readable sections before JSON output. When the scanner called `get_system_info.sh --json`, it received formatted text headers (like "=== Network Information ===") mixed with actual system data, causing JSON parsing to fail.

**Error Messages:** 
```
[SSH] ⚠ Non-JSON output received, checking script...
[SSH] Debug output: === Network Information ===
Hostname: rvce-ThinkCentre-M75s-Gen-5
...
```

**Expected Behavior:** When called with `--json` flag, `get_system_info.sh` should output ONLY valid JSON with no additional text or formatting sections.

**Steps to Reproduce:** 
1. SSH into target system (192.168.0.11)
2. Run: `./get_system_info.sh --json`
3. Observe that output contains both formatted text and JSON (not valid JSON)

**Files Modified Recently:** 
- `scanner/get_system_info.sh` - Refactored to check for `--json` flag at script start and suppress all non-JSON output when flag is present

**System State:** 
- Database: ✅ Running (0 systems discovered, 0 metrics collected)
- Backend API: ✅ Ready (not tested yet after fix)
- Scanner: ⚠️ Fixed - ready for re-testing
- Data: Empty (awaiting first successful scan)

## Required Fix Approach

1. **Diagnose**: Identify the root cause by checking logs and testing components
2. **Isolate**: Determine which component (scanner/backend/database) is affected
3. **Fix**: Apply the appropriate solution based on established patterns
4. **Test**: Verify the fix works and doesn't break existing functionality
5. **Document**: Update this prompt with any new fixes or issues discovered

## Key Files to Check

- `scanner/network_monitor.py` - Main scanner logic
- `scanner/config.json` - Scanner configuration
- `scanner/get_system_info.sh` - Data collection script
- `backend/src/models/db.js` - Database connection
- `backend/src/routes/` - API endpoints
- `database/schema.sql` - Database structure

Please help diagnose and fix the current issue while maintaining system integrity and following established patterns.