# OptiLab Network Scanner

A simple network scanner for discovering and monitoring computer systems in lab environments.

## How It Works

The scanner performs network discovery by:
1. Scanning IP ranges defined in `config.json`
2. Using SSH to connect to discovered systems
3. Executing `get_system_info.sh` to collect static hardware information
4. Storing system details in the PostgreSQL database

## Usage

### Prerequisites
- PostgreSQL database running with the schema from `../database/schema.sql`
- SSH keys configured for passwordless access to target systems

### Configuration
Edit `config.json` to set:
- Lab IP ranges
- SSH credentials (user: "rvce", private key path)
- Database connection details

### Running the Scanner

```bash
# Discover new systems
python3 network_monitor.py scan

# Check status of known systems
python3 network_monitor.py heartbeat
```

### Scripts
- `network_monitor.py`: Main scanner application
- `get_system_info.sh`: Collects system hardware information via SSH
- `config.json`: Configuration file

## Output
- Discovered systems are stored in the `systems` table
- Hardware specs (CPU, RAM, disk, GPU) are collected and stored
- Status updates are logged to the database