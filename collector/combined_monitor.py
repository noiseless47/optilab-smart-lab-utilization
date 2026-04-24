#!/usr/bin/env python3
"""
OptiLab Combined Network Scanner and Metrics Collector
Continuously scans department subnets and collects metrics from systems
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
import ipaddress
from datetime import datetime

# Configuration
CONFIG_FILE = os.path.join(os.path.dirname(__file__), "config.json")
COLLECTION_INTERVAL = 10  # Collect metrics every 10 seconds
SCAN_INTERVAL = 300  # Scan subnets every 5 minutes
SSH_TIMEOUT = 10

# Global flag for graceful shutdown
shutdown_event = Event()

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    print("\n[!] Shutting down combined monitor...")
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

# Utility functions from scanner
def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return ""

# Scanner functions
def validate_dept_config(conn, dept):
    """Validate that department exists."""
    cur = conn.cursor()
    try:
        # Check if department exists
        cur.execute("SELECT dept_id FROM departments WHERE dept_id = %s", (dept["dept_id"],))
        if not cur.fetchone():
            raise ValueError(f"Department {dept['dept_id']} does not exist in database")

        print(f"    ✓ Department {dept['dept_id']} ({dept['dept_name']}) validated")
    except Exception as e:
        print(f"    ✗ Department validation failed: {e}")
        raise
    finally:
        cur.close()

def ssh_identify(ip, ssh_cfg):
    """Attempt SSH auth and gather static system data."""
    script_path = os.path.join(os.path.dirname(__file__), "../scanner/get_system_info.sh")
    remote_script = "/tmp/get_system_info.sh"

    print(f"    [SSH] Attempting connection to {ip}...")

    # Transfer script
    scp_cmd = (
        f"scp -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"-i {ssh_cfg['private_key']} {script_path} {ssh_cfg['user']}@{ip}:{remote_script}"
    )
    scp_result = run_cmd(scp_cmd)
    if scp_result is None:
        print(f"    [SSH] ✗ Script transfer failed for {ip}")
        return None
    print(f"    [SSH] ✓ Script transferred to {ip}")

    # Run script
    ssh_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
        f"'bash {remote_script} --json'"
    )
    output = run_cmd(ssh_cmd)

    # Debug: Check if output contains JSON
    if output and output.strip().startswith('{'):
        print(f"    [SSH] ✓ JSON output detected")
    else:
        print(f"    [SSH] ⚠ Non-JSON output received, checking script...")
        # Try running without --json to see what we get
        debug_cmd = (
            f"ssh -oBatchMode=yes "
            f"-oConnectTimeout={ssh_cfg['timeout']} "
            f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
            f"'bash {remote_script} | head -20'"
        )
        debug_output = run_cmd(debug_cmd)
        print(f"    [SSH] Debug output: {debug_output[:200]}...")
        return None

    # Cleanup
    cleanup_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
        f"'rm -f {remote_script}'"
    )
    run_cmd(cleanup_cmd)

    if not output:
        print(f"    [SSH] ✗ No output received from {ip}")
        return None

    print(f"    [SSH] ✓ Received data from {ip}")

    try:
        data = json.loads(output)
        print(f"    [SSH] ✓ JSON parsed successfully for {ip}")
        return data
    except json.JSONDecodeError as e:
        print(f"    [SSH] ✗ JSON parsing failed for {ip}: {e}")
        print(f"    [SSH] Raw output: {output[:200]}...")
        return None

def upsert_system(conn, ip, data, lab_id, dept_id):
    print(f"    [DB] Inserting system {ip} into dept {dept_id}" + (f", lab {lab_id}" if lab_id else ""))

    cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO systems (
                lab_id, dept_id, hostname, ip_address, mac_address,
                cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory,
                status, notes, updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'active', %s, NOW())
            ON CONFLICT (ip_address) DO UPDATE
            SET hostname = EXCLUDED.hostname,
                mac_address = EXCLUDED.mac_address,
                cpu_model = EXCLUDED.cpu_model,
                cpu_cores = EXCLUDED.cpu_cores,
                ram_total_gb = EXCLUDED.ram_total_gb,
                disk_total_gb = EXCLUDED.disk_total_gb,
                gpu_model = EXCLUDED.gpu_model,
                gpu_memory = EXCLUDED.gpu_memory,
                status = 'active',
                updated_at = NOW()
            RETURNING system_id;
        """, (
            lab_id, dept_id, data.get("hostname"), ip, data.get("mac_address"),
            data.get("cpu_model"), data.get("cpu_cores"), data.get("ram_total_gb"),
            data.get("disk_total_gb"), data.get("gpu_model"), data.get("gpu_memory"),
            None
        ))

        result = cur.fetchone()
        if result:
            system_id = result['system_id'] if isinstance(result, dict) else result[0]
            print(f"    [DB] ✓ System inserted/updated with ID: {system_id}")
        else:
            print(f"    [DB] ✗ No result returned from RETURNING clause for {ip}")

        conn.commit()
        print(f"    [DB] ✓ Transaction committed for {ip}")

    except Exception as e:
        conn.rollback()
        print(f"    [DB] ✗ Transaction rolled back for {ip}: {e}")
        raise
    finally:
        cur.close()

def discover_department(dept, ssh_cfg, conn):
    # Validate department configuration
    validate_dept_config(conn, dept)

    # Get labs in this department
    cur = conn.cursor()
    cur.execute("SELECT lab_id FROM labs WHERE lab_dept = %s", (dept["dept_id"],))
    labs = cur.fetchall()
    cur.close()
    
    lab_id = labs[0]['lab_id'] if labs else None  # Assign to first lab if exists

    # Get all IPs in the subnet
    network = ipaddress.ip_network(dept["subnet_cidr"])
    ips = [str(ip) for ip in network.hosts()]
    
    responsive_hosts = []
    print(f"[+] Scanning department {dept['dept_id']} ({dept['dept_name']}) - {dept['subnet_cidr']} ({len(ips)} IPs)")

    # Step 1: Fast ping sweep
    cmd = f"nmap -sn {dept['subnet_cidr']} -oG -"
    nmap_out = run_cmd(cmd)
    for line in nmap_out.splitlines():
        if "Up" in line:
            ip = line.split()[1]
            if ip in ips:  # Ensure it's in our subnet
                responsive_hosts.append(ip)

    print(f"    Found {len(responsive_hosts)} responsive hosts")

    # Step 2: SSH validate + upsert
    with ThreadPoolExecutor(max_workers=10) as executor:
        futures = {
            executor.submit(ssh_identify, ip, ssh_cfg): ip
            for ip in responsive_hosts
        }
        for future in as_completed(futures):
            ip = futures[future]
            info = future.result()
            if not info:
                continue
            upsert_system(conn, ip, info, lab_id, dept["dept_id"])
            print(f"    [+] {ip} → {info['hostname']} (verified)")

def scan_departments(conn, cfg):
    """Run one complete department scan cycle"""
    try:
        print(f"[SCAN] Starting department scan at {datetime.now()}")
        # Query departments from database
        cur = conn.cursor()
        cur.execute("SELECT dept_id, dept_name, subnet_cidr FROM departments WHERE subnet_cidr IS NOT NULL")
        departments = cur.fetchall()
        cur.close()
        
        for dept in departments:
            discover_department(dict(dept), cfg["ssh"], conn)
        print(f"[SCAN] Department scan completed at {datetime.now()}")
    except Exception as e:
        print(f"[SCAN] Error in scan cycle: {e}")

# Metrics collection functions
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
    print("OptiLab Combined Network Scanner and Metrics Collector")
    print("=" * 60)
    print(f"[*] Loading configuration from {CONFIG_FILE}")
    
    cfg = load_config()
    
    print(f"[*] Connecting to database: {cfg['db']['dsn']}")
    conn = db_connect(cfg)
    print("[✓] Connected to database")
    
    print(f"[*] Scan interval: {SCAN_INTERVAL} seconds")
    print(f"[*] Collection interval: {COLLECTION_INTERVAL} seconds")
    print("[*] Press Ctrl+C to stop\n")
    
    last_scan = 0
    last_collection = 0
    cycle = 0
    
    try:
        while not shutdown_event.is_set():
            current_time = time.time()
            
            # Check if it's time to scan
            if current_time - last_scan >= SCAN_INTERVAL:
                scan_departments(conn, cfg)
                last_scan = current_time
            
            # Check if it's time to collect metrics
            if current_time - last_collection >= COLLECTION_INTERVAL:
                cycle += 1
                timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
                print(f"\n[{timestamp}] Collection cycle {cycle}")
                
                conn = run_collection_cycle(cfg, conn)
                last_collection = current_time
            
            # Sleep briefly to avoid high CPU usage
            time.sleep(1)
    
    except KeyboardInterrupt:
        pass
    finally:
        print("\n[*] Closing database connection...")
        conn.close()
        print("[✓] Combined monitor stopped")

if __name__ == "__main__":
    main()