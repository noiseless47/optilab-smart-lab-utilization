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

def expand_ip_range(from_ip, to_ip):
    start = int(ipaddress.IPv4Address(from_ip))
    end = int(ipaddress.IPv4Address(to_ip))
    return [str(ipaddress.IPv4Address(i)) for i in range(start, end + 1)]

def db_connect(cfg):
    return psycopg2.connect(cfg["db"]["dsn"], cursor_factory=RealDictCursor)

def get_configured_ranges(cfg):
    ranges = []
    for lab in cfg.get("labs", []):
        ip_range = lab.get("ip_range", {})
        from_ip = ip_range.get("from")
        to_ip = ip_range.get("to")
        if from_ip and to_ip:
            ranges.extend(expand_ip_range(from_ip, to_ip))
    return ranges

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

# ----------------------------------------------------------
# Scanner
# ----------------------------------------------------------
def ssh_identify(ip, ssh_cfg):
    """Attempt SSH auth and gather static system data."""
    script_path = os.path.join(os.path.dirname(__file__), "get_system_info.sh")
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
                if ip in ips:
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
    ssh_cfg = get_effective_ssh_config(cfg)

    if sys.argv[1] == "scan":
        print(f"[+] Starting discovery scan at {datetime.now()}")
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

                        discover_department(dict(dept), ssh_cfg, conn, expand_ip_range(from_ip, to_ip))
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
        print("[+] Scan completed.")
    elif sys.argv[1] == "heartbeat":
        heartbeat(conn, cfg)
        print(f"[+] Heartbeat completed at {datetime.now()}")

    conn.close()
