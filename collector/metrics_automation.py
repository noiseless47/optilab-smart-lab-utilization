#!/usr/bin/env python3
"""
OptiLab Metrics Collection Automation
Continuously collects metrics from systems and inserts into database
"""

import json
import time
import subprocess
import sys
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Event
import signal

# Configuration
CONFIG_FILE = os.path.join(os.path.dirname(__file__), "config.json")
COLLECTION_INTERVAL = 10  # Collect metrics every 30 seconds
SSH_TIMEOUT = 10

# Global flag for graceful shutdown
shutdown_event = Event()

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    print("\n[!] Shutting down metrics collection...")
    shutdown_event.set()

# Register signal handler
signal.signal(signal.SIGINT, signal_handler)

def load_config():
    """Load configuration from config.json"""
    with open(CONFIG_FILE) as f:
        return json.load(f)

def db_connect(cfg):
    """Connect to PostgreSQL database"""
    return psycopg2.connect(cfg["db"]["dsn"], cursor_factory=RealDictCursor)

def get_active_systems(conn):
    """Get all active systems from database"""
    cur = conn.cursor()
    cur.execute("""
        SELECT system_id, ip_address, hostname 
        FROM systems 
        WHERE status = 'active'
        ORDER BY system_id
    """)
    systems = cur.fetchall()
    cur.close()
    return systems

def collect_metrics_ssh(ip, ssh_cfg):
    """Collect metrics from remote system via SSH"""
    script_path = os.path.join(os.path.dirname(__file__), "metrics_collector.sh")
    remote_script = "/tmp/metrics_collector.sh"
    
    try:
        # Transfer script
        scp_cmd = (
            f"scp -oBatchMode=yes "
            f"-oConnectTimeout={SSH_TIMEOUT} "
            f"-oStrictHostKeyChecking=no "
            f"-i {ssh_cfg['private_key']} "
            f"{script_path} {ssh_cfg['user']}@{ip}:{remote_script}"
        )
        result = subprocess.run(scp_cmd, shell=True, capture_output=True, text=True, timeout=SSH_TIMEOUT)
        
        if result.returncode != 0:
            print(f"  [!] SCP failed for {ip}: {result.stderr}")
            return None
        
        # Run metrics collection script
        ssh_cmd = (
            f"ssh -oBatchMode=yes "
            f"-oConnectTimeout={SSH_TIMEOUT} "
            f"-oStrictHostKeyChecking=no "
            f"-i {ssh_cfg['private_key']} "
            f"{ssh_cfg['user']}@{ip} "
            f"'bash {remote_script} --json'"
        )
        result = subprocess.run(ssh_cmd, shell=True, capture_output=True, text=True, timeout=SSH_TIMEOUT)
        
        if result.returncode != 0:
            print(f"  [!] SSH metrics collection failed for {ip}")
            return None
        
        # Cleanup
        cleanup_cmd = (
            f"ssh -oBatchMode=yes "
            f"-oConnectTimeout={SSH_TIMEOUT} "
            f"-oStrictHostKeyChecking=no "
            f"-i {ssh_cfg['private_key']} "
            f"{ssh_cfg['user']}@{ip} "
            f"'rm -f {remote_script}'"
        )
        subprocess.run(cleanup_cmd, shell=True, capture_output=True, timeout=SSH_TIMEOUT)
        
        # Parse JSON response
        try:
            metrics = json.loads(result.stdout)
            return metrics
        except json.JSONDecodeError as e:
            print(f"  [!] JSON parse failed for {ip}: {e}")
            return None
            
    except subprocess.TimeoutExpired:
        print(f"  [!] SSH timeout for {ip}")
        return None
    except Exception as e:
        print(f"  [!] Error collecting metrics from {ip}: {e}")
        return None

def insert_metrics(conn, system_id, metrics):
    """Insert metrics into database"""
    try:
        cur = conn.cursor()
        
        cur.execute("""
            INSERT INTO metrics (
                system_id, timestamp,
                cpu_percent, cpu_temperature,
                ram_percent,
                disk_percent, disk_read_mbps, disk_write_mbps,
                network_sent_mbps, network_recv_mbps,
                gpu_percent, gpu_memory_used_gb, gpu_temperature,
                uptime_seconds, logged_in_users
            )
            VALUES (
                %s, NOW(),
                %s, %s,
                %s,
                %s, %s, %s,
                %s, %s,
                %s, %s, %s,
                %s, %s
            )
            ON CONFLICT DO NOTHING
        """, (
            system_id,
            metrics.get("cpu_percent"), metrics.get("cpu_temperature"),
            metrics.get("ram_percent"),
            metrics.get("disk_percent"), metrics.get("disk_read_mbps"), metrics.get("disk_write_mbps"),
            metrics.get("network_sent_mbps"), metrics.get("network_recv_mbps"),
            metrics.get("gpu_percent"), metrics.get("gpu_memory_used_gb"), metrics.get("gpu_temperature"),
            metrics.get("uptime_seconds"), metrics.get("logged_in_users")
        ))
        
        conn.commit()
        cur.close()
        return True
        
    except Exception as e:
        print(f"  [!] Database insert error for system {system_id}: {e}")
        conn.rollback()
        return False

def collect_system_metrics(conn, system, ssh_cfg):
    """Collect and insert metrics for a single system"""
    system_id = system['system_id']
    ip = system['ip_address']
    hostname = system['hostname']
    
    print(f"  → Collecting metrics from {hostname} ({ip})...", end=" ", flush=True)
    
    metrics = collect_metrics_ssh(ip, ssh_cfg)
    
    if metrics:
        if insert_metrics(conn, system_id, metrics):
            print("✓")
            return True
        else:
            print("✗ (insert failed)")
            return False
    else:
        print("✗ (collection failed)")
        return False

def run_collection_cycle(cfg, conn):
    """Run one complete metrics collection cycle"""
    try:
        # Reconnect if needed
        try:
            conn.isolation_level
        except:
            print("[!] Database connection lost, reconnecting...")
            conn = db_connect(cfg)
        
        systems = get_active_systems(conn)
        
        if not systems:
            print("[*] No active systems found")
            return conn
        
        print(f"[+] Collecting metrics from {len(systems)} systems...")
        
        ssh_cfg = cfg["ssh"]
        successful = 0
        
        # Collect metrics in parallel
        with ThreadPoolExecutor(max_workers=cfg.get("max_workers", 5)) as executor:
            futures = {
                executor.submit(collect_system_metrics, conn, system, ssh_cfg): system['system_id']
                for system in systems
            }
            
            for future in as_completed(futures):
                if future.result():
                    successful += 1
        
        print(f"[✓] Metrics collection cycle complete: {successful}/{len(systems)} successful")
        
    except Exception as e:
        print(f"[!] Error in collection cycle: {e}")
    
    return conn

def main():
    """Main loop"""
    print("=" * 60)
    print("OptiLab Metrics Collection Automation")
    print("=" * 60)
    print(f"[*] Loading configuration from {CONFIG_FILE}")
    
    cfg = load_config()
    
    print(f"[*] Connecting to database: {cfg['db']['dsn']}")
    conn = db_connect(cfg)
    print("[✓] Connected to database")
    
    print(f"[*] Collection interval: {COLLECTION_INTERVAL} seconds")
    print("[*] Press Ctrl+C to stop\n")
    
    cycle = 0
    
    try:
        while not shutdown_event.is_set():
            cycle += 1
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            print(f"\n[{timestamp}] Cycle {cycle}")
            
            conn = run_collection_cycle(cfg, conn)
            
            # Wait for next cycle
            if not shutdown_event.is_set():
                time.sleep(COLLECTION_INTERVAL)
    
    except KeyboardInterrupt:
        pass
    finally:
        print("\n[*] Closing database connection...")
        conn.close()
        print("[✓] Metrics collection stopped")

if __name__ == "__main__":
    main()
