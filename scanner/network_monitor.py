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

    # Transfer script
    scp_cmd = (
        f"scp -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"-i {ssh_cfg['private_key']} {script_path} {ssh_cfg['user']}@{ip}:{remote_script}"
    )
    if run_cmd(scp_cmd) is None:
        return None

    # Run script
    ssh_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
        f"'bash {remote_script} --json'"
    )
    output = run_cmd(ssh_cmd)

    # Cleanup
    cleanup_cmd = (
        f"ssh -oBatchMode=yes "
        f"-oConnectTimeout={ssh_cfg['timeout']} "
        f"-i {ssh_cfg['private_key']} {ssh_cfg['user']}@{ip} "
        f"'rm -f {remote_script}'"
    )
    run_cmd(cleanup_cmd)

    if not output:
        return None

    try:
        data = json.loads(output)
        return data
    except json.JSONDecodeError:
        return None

def upsert_system(conn, ip, data, lab_id, dept_id):
    cur = conn.cursor()
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
            updated_at = NOW();
    """, (
        lab_id, dept_id, data.get("hostname"), ip, data.get("mac_address"),
        data.get("cpu_model"), data.get("cpu_cores"), data.get("ram_total_gb"),
        data.get("disk_total"), data.get("gpu_model"), data.get("gpu_memory_gb"),
        None
    ))
    conn.commit()

def discover_lab(lab, ssh_cfg, conn):
    ips = expand_range(lab["ip_range"]["from"], lab["ip_range"]["to"])
    responsive_hosts = []
    print(f"[+] Scanning lab {lab['lab_id']} ({lab['ip_range']['from']}–{lab['ip_range']['to']})")

    # Step 1: Fast ping sweep
    cmd = f"nmap -sn {lab['ip_range']['from']}-{lab['ip_range']['to'].split('.')[-1]} -oG -"
    nmap_out = run_cmd(cmd)
    for line in nmap_out.splitlines():
        if "Up" in line:
            responsive_hosts.append(line.split()[1])

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
            upsert_system(conn, ip, info, lab["lab_id"], lab["dept_id"])
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
        for lab in cfg["labs"]:
            discover_lab(lab, cfg["ssh"], conn)
        print("[+] Scan completed.")
    elif sys.argv[1] == "heartbeat":
        heartbeat(conn, cfg)
        print(f"[+] Heartbeat completed at {datetime.now()}")

    conn.close()
