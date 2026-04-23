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

def expand_range(from_ip, to_ip):
    start = int(ipaddress.IPv4Address(from_ip))
    end = int(ipaddress.IPv4Address(to_ip))
    return [str(ipaddress.IPv4Address(i)) for i in range(start, end + 1)]

def get_configured_ranges(cfg):
    ranges = []
    for lab in cfg.get("labs", []):
        ip_range = lab.get("ip_range", {})
        from_ip = ip_range.get("from")
        to_ip = ip_range.get("to")
        if from_ip and to_ip:
            ranges.extend(expand_range(from_ip, to_ip))
    return ranges

def ip_in_configured_ranges(ip, cfg):
    configured_ips = set(get_configured_ranges(cfg))
    return ip in configured_ips

# Utility functions from scanner
def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return ""

def run_cmd_capture(cmd, timeout=5):
    try:
        return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return None

def get_effective_ssh_config(cfg):
    ssh_cfg = dict(cfg.get("ssh", {}))
    if "bastion" not in ssh_cfg and "bastion" in cfg:
        ssh_cfg["bastion"] = cfg.get("bastion", {})
    return ssh_cfg

def build_ssh_transport_options(ssh_cfg):
    bastion_cfg = ssh_cfg.get("bastion", {})
    if not bastion_cfg.get("enabled"):
        return "", ""

    bastion_host = bastion_cfg.get("host")
    bastion_port = bastion_cfg.get("port", 22)
    bastion_user = bastion_cfg.get("user", ssh_cfg["user"])
    if not bastion_host:
        return "", ""

    proxy_jump = f"-o ProxyJump={bastion_user}@{bastion_host}:{bastion_port}"
    return proxy_jump, proxy_jump

def verify_bastion_connection(ssh_cfg):
    bastion_cfg = ssh_cfg.get("bastion", {})
    if not bastion_cfg.get("enabled"):
        return True

    bastion_host = bastion_cfg.get("host")
    bastion_port = bastion_cfg.get("port", 22)
    bastion_user = bastion_cfg.get("user", ssh_cfg.get("user"))
    bastion_key = bastion_cfg.get("private_key", ssh_cfg.get("private_key"))

    if not bastion_host:
        print("[BASTION] Bastion enabled but host is not configured")
        return False

    check_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg.get('timeout', 3)} "
        f"-oStrictHostKeyChecking=no "
        f"-i {bastion_key} "
        f"-p {bastion_port} {bastion_user}@{bastion_host} 'exit 0'"
    )
    result = run_cmd_capture(check_cmd, timeout=ssh_cfg.get("timeout", 3) + 5)
    if not result or result.returncode != 0:
        stderr = result.stderr.strip()[:300] if result and result.stderr else "unreachable"
        print(f"[BASTION] Connection check failed for {bastion_user}@{bastion_host}:{bastion_port}: {stderr}")
        return False

    return True

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
    scp_transport, ssh_transport = build_ssh_transport_options(ssh_cfg)

    print(f"    [SSH] Attempting connection to {ip}...")

    # Transfer script
    scp_cmd = (
        f"scp -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"{scp_transport} "
        f"-i {ssh_cfg['private_key']} {script_path} {ssh_cfg['user']}@{ip}:{remote_script}"
    )
    scp_result = run_cmd_capture(scp_cmd, timeout=ssh_cfg['timeout'] + 5)
    if not scp_result or scp_result.returncode != 0:
        print(f"    [SSH] ✗ Script transfer failed for {ip}")
        if scp_result:
            if scp_result.stdout.strip():
                print(f"    [SSH] scp stdout: {scp_result.stdout.strip()[:200]}")
            if scp_result.stderr.strip():
                print(f"    [SSH] scp stderr: {scp_result.stderr.strip()[:200]}")
        return None
    print(f"    [SSH] ✓ Script transferred to {ip}")

    # Run script
    ssh_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"{ssh_transport} "
        f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
        f"'bash {remote_script} --json'"
    )
    ssh_result = run_cmd_capture(ssh_cmd, timeout=ssh_cfg['timeout'] + 10)
    output = ssh_result.stdout.strip() if ssh_result else ""

    # Debug: Check if output contains JSON
    if output and output.strip().startswith('{'):
        print(f"    [SSH] ✓ JSON output detected")
    else:
        print(f"    [SSH] ⚠ Non-JSON output received, checking script...")
        if ssh_result:
            if ssh_result.stdout.strip():
                print(f"    [SSH] stdout: {ssh_result.stdout.strip()[:500]}")
            if ssh_result.stderr.strip():
                print(f"    [SSH] stderr: {ssh_result.stderr.strip()[:500]}")
            print(f"    [SSH] exit code: {ssh_result.returncode}")
        return None

    # Cleanup
    cleanup_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"{ssh_transport} "
        f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
        f"'rm -f {remote_script}'"
    )
    run_cmd_capture(cleanup_cmd, timeout=ssh_cfg['timeout'] + 5)

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

def upsert_system(conn, ip, data, dept_id):
    print(f"    [DB] Inserting discovered system {ip} into dept {dept_id} (lab unassigned)")

    cur = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO systems (
                lab_id, dept_id, hostname, ip_address, mac_address,
                cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory,
                status, notes, updated_at
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, 'discovered', %s, NOW())
            ON CONFLICT (ip_address) DO UPDATE
            SET hostname = EXCLUDED.hostname,
                mac_address = EXCLUDED.mac_address,
                dept_id = EXCLUDED.dept_id,
                cpu_model = EXCLUDED.cpu_model,
                cpu_cores = EXCLUDED.cpu_cores,
                ram_total_gb = EXCLUDED.ram_total_gb,
                disk_total_gb = EXCLUDED.disk_total_gb,
                gpu_model = EXCLUDED.gpu_model,
                gpu_memory = EXCLUDED.gpu_memory,
                status = CASE WHEN systems.lab_id IS NULL THEN 'discovered' ELSE systems.status END,
                updated_at = NOW()
            RETURNING system_id;
        """, (
            None, dept_id, data.get("hostname"), ip, data.get("mac_address"),
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

def discover_department(dept, ssh_cfg, conn, ip_list=None):
    # Validate department configuration
    validate_dept_config(conn, dept)

    if ip_list is None:
        # Get all IPs in the subnet
        network = ipaddress.ip_network(dept["subnet_cidr"])
        ips = [str(ip) for ip in network.hosts()]
        scan_label = dept["subnet_cidr"]
    else:
        ips = ip_list
        scan_label = f"{ips[0]} - {ips[-1]}"
    
    responsive_hosts = []
    print(f"[+] Scanning department {dept['dept_id']} ({dept['dept_name']}) - {scan_label} ({len(ips)} IPs)")

    # Step 1: Fast ping sweep
    if ip_list is None:
        cmd = f"nmap -sn {dept['subnet_cidr']} -oG -"
        nmap_out = run_cmd(cmd)
        for line in nmap_out.splitlines():
            if "Up" in line:
                ip = line.split()[1]
                if ip in ips:  # Ensure it's in our subnet
                    responsive_hosts.append(ip)
    else:
        for cidr in ipaddress.summarize_address_range(ipaddress.IPv4Address(ips[0]), ipaddress.IPv4Address(ips[-1])):
            cmd = f"nmap -sn {cidr} -oG -"
            nmap_out = run_cmd(cmd)
            for line in nmap_out.splitlines():
                if "Up" in line:
                    ip = line.split()[1]
                    if ip in ips:
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
            upsert_system(conn, ip, info, dept["dept_id"])
            print(f"    [+] {ip} → {info['hostname']} (verified)")

def scan_departments(conn, cfg):
    """Run one complete department scan cycle"""
    try:
        print(f"[SCAN] Starting department scan at {datetime.now()}")
        ssh_cfg = get_effective_ssh_config(cfg)
        if not verify_bastion_connection(ssh_cfg):
            print("[SCAN] Skipping scan because bastion is unavailable")
            return
        configured_labs = cfg.get("labs", [])
        if configured_labs:
            cur = conn.cursor()
            try:
                for lab in configured_labs:
                    dept_id = lab.get("dept_id")
                    ip_range = lab.get("ip_range", {})
                    from_ip = ip_range.get("from")
                    to_ip = ip_range.get("to")
                    if not dept_id or not from_ip or not to_ip:
                        continue

                    cur.execute("SELECT dept_id, dept_name, subnet_cidr FROM departments WHERE dept_id = %s", (dept_id,))
                    dept = cur.fetchone()
                    if not dept:
                        continue

                        discover_department(dict(dept), ssh_cfg, conn, expand_range(from_ip, to_ip))
            finally:
                cur.close()
        else:
            # Query departments from database
            cur = conn.cursor()
            cur.execute("SELECT dept_id, dept_name, subnet_cidr FROM departments WHERE subnet_cidr IS NOT NULL")
            departments = cur.fetchall()
            cur.close()

            for dept in departments:
                discover_department(dict(dept), ssh_cfg, conn)
        print(f"[SCAN] Department scan completed at {datetime.now()}")
    except Exception as e:
        print(f"[SCAN] Error in scan cycle: {e}")

# Metrics collection functions
def get_active_systems(conn):
    """Get all collectable systems from database"""
    cur = conn.cursor()
    cur.execute("""
        SELECT system_id, ip_address, hostname 
        FROM systems 
        WHERE status IN ('active', 'discovered')
        ORDER BY system_id
    """)
    systems = cur.fetchall()
    cur.close()
    return systems

def filter_systems_by_configured_ranges(systems, cfg):
    configured_ips = set(get_configured_ranges(cfg))
    if not configured_ips:
        return systems

    filtered = []
    for system in systems:
        if str(system["ip_address"]) in configured_ips:
            filtered.append(system)
    return filtered

def collect_metrics_ssh(ip, ssh_cfg):
    """Collect metrics from remote system via SSH"""
    script_path = os.path.join(os.path.dirname(__file__), "metrics_collector.sh")
    remote_script = "/tmp/metrics_collector.sh"
    scp_transport, ssh_transport = build_ssh_transport_options(ssh_cfg)
    
    try:
        # Transfer script
        scp_cmd = (
            f"scp -oBatchMode=yes "
            f"-oConnectTimeout={ssh_cfg['timeout']} "
            f"-oStrictHostKeyChecking=no "
            f"{scp_transport} "
            f"-i {ssh_cfg['private_key']} "
            f"{script_path} {ssh_cfg['user']}@{ip}:{remote_script}"
        )
        result = subprocess.run(scp_cmd, shell=True, capture_output=True, text=True, timeout=ssh_cfg['timeout'] + 5)
        
        if result.returncode != 0:
            print(f"  [!] SCP failed for {ip}: {result.stderr}")
            return None
        
        # Run metrics collection script
        ssh_cmd = (
            f"ssh -oBatchMode=yes "
            f"-oConnectTimeout={ssh_cfg['timeout']} "
            f"-oStrictHostKeyChecking=no "
            f"{ssh_transport} "
            f"-i {ssh_cfg['private_key']} "
            f"{ssh_cfg['user']}@{ip} "
            f"'bash {remote_script} --json'"
        )
        result = subprocess.run(ssh_cmd, shell=True, capture_output=True, text=True, timeout=ssh_cfg['timeout'] + 10)
        
        if result.returncode != 0:
            print(f"  [!] SSH metrics collection failed for {ip}")
            return None
        
        # Cleanup
        cleanup_cmd = (
            f"ssh -oBatchMode=yes "
            f"-oConnectTimeout={ssh_cfg['timeout']} "
            f"-oStrictHostKeyChecking=no "
            f"{ssh_transport} "
            f"-i {ssh_cfg['private_key']} "
            f"{ssh_cfg['user']}@{ip} "
            f"'rm -f {remote_script}'"
        )
        subprocess.run(cleanup_cmd, shell=True, capture_output=True, timeout=ssh_cfg['timeout'] + 5)
        
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
                cpu_percent, cpu_temperature, cpu_iowait_percent,
                ram_percent,
                disk_percent, disk_read_mbps, disk_write_mbps,
                network_sent_mbps, network_recv_mbps,
                gpu_percent, gpu_memory_used_gb, gpu_temperature,
                context_switch_rate, swap_in_rate, swap_out_rate,
                page_fault_rate, major_page_fault_rate,
                uptime_seconds, logged_in_users
            )
            VALUES (
                %s, NOW(),
                %s, %s, %s,
                %s,
                %s, %s, %s,
                %s, %s,
                %s, %s, %s,
                %s, %s, %s,
                %s, %s,
                %s, %s
            )
            ON CONFLICT DO NOTHING
        """, (
            system_id,
            metrics.get("cpu_percent"), metrics.get("cpu_temperature"), metrics.get("cpu_iowait_percent"),
            metrics.get("ram_percent"),
            metrics.get("disk_percent"), metrics.get("disk_read_mbps"), metrics.get("disk_write_mbps"),
            metrics.get("network_sent_mbps"), metrics.get("network_recv_mbps"),
            metrics.get("gpu_percent"), metrics.get("gpu_memory_used_gb"), metrics.get("gpu_temperature"),
            metrics.get("context_switch_rate"), metrics.get("swap_in_rate"), metrics.get("swap_out_rate"),
            metrics.get("page_fault_rate"), metrics.get("major_page_fault_rate"),
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
            cur = conn.cursor()
            try:
                cur.execute(
                    "UPDATE systems SET status = 'active', updated_at = NOW() WHERE system_id = %s",
                    (system_id,)
                )
                conn.commit()
            finally:
                cur.close()
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
        
        systems = filter_systems_by_configured_ranges(get_active_systems(conn), cfg)
        
        if not systems:
            print("[*] No collectable systems found")
            return conn
        
        print(f"[+] Collecting metrics from {len(systems)} systems...")
        
        ssh_cfg = get_effective_ssh_config(cfg)
        if not verify_bastion_connection(ssh_cfg):
            print("[*] Skipping metrics collection because bastion is unavailable")
            return conn
        successful = 0
        
        # Collect metrics in parallel
        with ThreadPoolExecutor(max_workers=cfg.get("max_workers", 5)) as executor:
            futures = {}
            for system in systems:
                system_id = system["system_id"] if isinstance(system, dict) else system[0]
                futures[executor.submit(collect_system_metrics, conn, system, ssh_cfg)] = system_id

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