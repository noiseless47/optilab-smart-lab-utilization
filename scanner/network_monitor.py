#!/usr/bin/env python3
import json
import ipaddress
import subprocess
import psycopg2
from psycopg2.extras import RealDictCursor
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
import os

CONFIG_PATH = "/home/aayush/Desktop/Projects/optilab-smart-lab-utilization/scanner/config.json"

# ----------------------------------------------------------
# Utility functions
# ----------------------------------------------------------
def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)

def expand_range(from_ip, to_ip):
    start = int(ipaddress.IPv4Address(from_ip))
    end = int(ipaddress.IPv4Address(to_ip))
    return [str(ipaddress.IPv4Address(i)) for i in range(start, end + 1)]

def db_connect(cfg):
    return psycopg2.connect(cfg["db"]["dsn"], cursor_factory=RealDictCursor)

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

def run_cmd(cmd):
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=5)
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return ""

# ----------------------------------------------------------
# Scanner
# ----------------------------------------------------------
def ssh_identify(ip, ssh_cfg):
    """Attempt SSH auth and gather static system data."""
    script_path = os.path.join(os.path.dirname(__file__), "get_system_info.sh")
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
    # Since nmap with large ranges might be slow, perhaps ping in parallel or use nmap
    # For simplicity, use nmap on the network
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

# ----------------------------------------------------------
# Heartbeat
# ----------------------------------------------------------
def heartbeat(conn, cfg):
    cur = conn.cursor()
    cur.execute("SELECT system_id, ip_address, hostname, status, notes FROM systems WHERE status='active';")
    systems = cur.fetchall()

    print(f"[HB] Checking {len(systems)} active systems...")
    def check(ip):
        result = subprocess.run(["nc", "-z", "-w1", ip, "22"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return ip, (result.returncode == 0)

    with ThreadPoolExecutor(max_workers=cfg["max_workers"]) as executor:
        results = executor.map(lambda s: check(s["ip_address"]), systems)

    for ip, ok in results:
        if ok:
            cur.execute("""
                UPDATE systems 
                SET status='active', updated_at=NOW()
                WHERE ip_address=%s;
            """, (ip,))
        else:
            cur.execute("""
                UPDATE systems 
                SET status='offline', updated_at=NOW()
                WHERE ip_address=%s;
            """, (ip,))
    conn.commit()
    print("[HB] Heartbeat complete.")

# ----------------------------------------------------------
# Main entry
# ----------------------------------------------------------
if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2 or sys.argv[1] not in ["scan", "heartbeat"]:
        print("Usage: python3 network_monitor.py [scan|heartbeat]")
        sys.exit(1)

    cfg = load_config()
    conn = db_connect(cfg)

    if sys.argv[1] == "scan":
        print(f"[+] Starting discovery scan at {datetime.now()}")
        # Query departments from database
        cur = conn.cursor()
        cur.execute("SELECT dept_id, dept_name, subnet_cidr FROM departments WHERE subnet_cidr IS NOT NULL")
        departments = cur.fetchall()
        cur.close()
        
        for dept in departments:
            discover_department(dict(dept), cfg["ssh"], conn)
        print("[+] Scan completed.")
    elif sys.argv[1] == "heartbeat":
        heartbeat(conn, cfg)
        print(f"[+] Heartbeat completed at {datetime.now()}")

    conn.close()
