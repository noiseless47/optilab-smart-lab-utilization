#!/usr/bin/env python3
"""
Network Discovery & Metrics Collection Service
Agentless monitoring system for academic computer labs

Usage:
    python network_collector.py --scan 10.30.0.0/16 --dept ISE
    python network_collector.py --collect-all
"""

import nmap
import argparse
import logging
from datetime import datetime
from typing import List, Dict, Optional
import psycopg2
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()


# For Windows WMI
try:
    import wmi
    WMI_AVAILABLE = True
except ImportError:
    WMI_AVAILABLE = False
    # ...existing code...

# For Linux SSH
try:
    import paramiko
    SSH_AVAILABLE = True
except ImportError:
    SSH_AVAILABLE = False
    # ...existing code...

# For SNMP
try:
    from pysnmp.hlapi import *
    SNMP_AVAILABLE = True
except ImportError:
    SNMP_AVAILABLE = False
    # ...existing code...


logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class DatabaseConnection:
    """PostgreSQL database connection manager"""
    
    def __init__(self, host=None, database=None, user=None, password=None, port=None):
        self.conn_params = {
            'host': host or os.getenv('DB_HOST', 'localhost'),
            'port': port or os.getenv('DB_PORT', '5432'),
            'database': database or os.getenv('DB_NAME', 'lab_resource_monitor'),
            'user': user or os.getenv('DB_USER', 'postgres'),
            'password': password or os.getenv('DB_PASSWORD', 'postgres')
        }
    # ...existing code...
        self.conn = None
    
    def connect(self):
        """Establish database connection"""
        self.conn = psycopg2.connect(**self.conn_params)
        return self.conn
    
    def execute(self, query, params=None, fetch=False):
        """Execute SQL query"""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute(query, params)
            if fetch:
                return cur.fetchall()
            self.conn.commit()
            return cur.rowcount
    
    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()


class NetworkDiscovery:
    """Network scanning and system discovery"""
    
    def __init__(self, db: DatabaseConnection):
        self.db = db
        self.scanner = nmap.PortScanner()
    
    def scan_network(self, subnet_cidr: str, dept_id: int) -> List[Dict]:
        """
        Scan network and discover active systems
        
        Args:
            subnet_cidr: Network range (e.g., '10.30.0.0/16')
            dept_id: Department ID
        
        Returns:
            List of discovered systems
        """
        logger.info(f"Starting network scan for {subnet_cidr}")
        
        # Record scan start
        scan_id = self.db.execute("""
            INSERT INTO network_scans 
            (dept_id, scan_type, target_range, scan_start, status)
            VALUES (%s, 'nmap', %s, NOW(), 'running')
            RETURNING scan_id
        """, (dept_id, subnet_cidr), fetch=True)[0]['scan_id']
        
        discovered_systems = []
        
        try:
            # Run nmap scan: -sn = ping scan for discovery only
            # Note: OS detection requires port scan, so we do simple host discovery first
            self.scanner.scan(
                hosts=subnet_cidr,
                arguments='-sn --max-rtt-timeout 500ms'
            )
            
            for host in self.scanner.all_hosts():
                if self.scanner[host].state() == 'up':
                    system_info = self._extract_system_info(host, dept_id, scan_id)
                    discovered_systems.append(system_info)
                    
                    # Upsert to database
                    self._upsert_system(system_info)
            
            # Update scan record
            self.db.execute("""
                UPDATE network_scans
                SET scan_end = NOW(), 
                    status = 'completed', 
                    systems_found = %s
                WHERE scan_id = %s
            """, (len(discovered_systems), scan_id))
            
            logger.info(f"Scan completed. Found {len(discovered_systems)} systems")
            
        except Exception as e:
            logger.error(f"Scan failed: {str(e)}")
            self.db.execute("""
                UPDATE network_scans
                SET status = 'failed', 
                    error_message = %s
                WHERE scan_id = %s
            """, (str(e), scan_id))
            raise
        
        return discovered_systems
    
    def _extract_system_info(self, host: str, dept_id: int, scan_id: int) -> Dict:
        """Extract system information from nmap scan"""
        host_info = self.scanner[host]
        
        # Get hostname
        hostname = host_info.hostname() if host_info.hostname() else f"host-{host.replace('.', '-')}"
        
        # Get MAC address
        mac_address = host_info['addresses'].get('mac', None)
        
        # Detect OS
        os_type = 'Unknown'
        os_version = 'Unknown'
        
        if 'osmatch' in host_info and host_info['osmatch']:
            os_match = host_info['osmatch'][0]
            os_name = os_match['name'].lower()
            
            if 'windows' in os_name:
                os_type = 'Windows'
                os_version = os_match['name']
            elif 'linux' in os_name or 'ubuntu' in os_name or 'centos' in os_name:
                os_type = 'Linux'
                os_version = os_match['name']
        
        # Determine collection method
        collection_method = self._determine_collection_method(os_type)
        
        return {
            'dept_id': dept_id,
            'hostname': hostname,
            'ip_address': host,
            'mac_address': mac_address,
            'os_type': os_type,
            'os_version': os_version,
            'collection_method': collection_method,
            'scan_id': scan_id
        }
    
    def _determine_collection_method(self, os_type: str) -> str:
        """Determine best collection method based on OS"""
        if os_type == 'Windows' and WMI_AVAILABLE:
            return 'wmi'
        elif os_type == 'Linux' and SSH_AVAILABLE:
            return 'ssh'
        elif SNMP_AVAILABLE:
            return 'snmp'
        else:
            return 'none'
    
    def _upsert_system(self, system_info: Dict):
        """Insert or update system in database"""
        self.db.execute("""
            INSERT INTO systems 
            (dept_id, hostname, ip_address, mac_address, os_type, os_version, 
             collection_method, last_scan_id, status, last_seen)
            VALUES (%(dept_id)s, %(hostname)s, %(ip_address)s, %(mac_address)s,
                    %(os_type)s, %(os_version)s, %(collection_method)s,
                    %(scan_id)s, 'active', NOW())
            ON CONFLICT (ip_address) DO UPDATE
            SET hostname = EXCLUDED.hostname,
                mac_address = EXCLUDED.mac_address,
                os_type = EXCLUDED.os_type,
                os_version = EXCLUDED.os_version,
                collection_method = EXCLUDED.collection_method,
                last_scan_id = EXCLUDED.last_scan_id,
                status = 'active',
                last_seen = NOW()
        """, system_info)


class MetricsCollector:
    """Collect metrics from discovered systems"""
    
    def __init__(self, db: DatabaseConnection):
        self.db = db
    
    def collect_all_metrics(self):
        """Collect metrics from all active systems"""
        systems = self.db.execute("""
            SELECT system_id, ip_address, os_type, collection_method, hostname
            FROM systems
            WHERE status = 'active'
            ORDER BY system_id
        """, fetch=True)
        
        logger.info(f"Starting metrics collection for {len(systems)} systems")
        
        success_count = 0
        fail_count = 0
        
        for system in systems:
            try:
                metrics = self._collect_system_metrics(system)
                if metrics:
                    self._save_metrics(system['system_id'], metrics)
                    success_count += 1
                    # ...existing code...
                else:
                    fail_count += 1
                    logger.warning(f"✗ No metrics from {system['hostname']}")
            except Exception as e:
                fail_count += 1
                logger.error(f"✗ Failed to collect from {system['hostname']}: {str(e)}")
                self._mark_system_offline(system['system_id'])
        
        logger.info(f"Collection complete: {success_count} success, {fail_count} failed")
    
    def _collect_system_metrics(self, system: Dict) -> Optional[Dict]:
        """Collect metrics from a single system"""
        method = system['collection_method']
        ip = system['ip_address']
        
        if method == 'wmi':
            return self._collect_wmi_metrics(ip)
        elif method == 'ssh':
            return self._collect_ssh_metrics(ip)
        elif method == 'snmp':
            return self._collect_snmp_metrics(ip)
        else:
            logger.warning(f"No collection method for {ip}")
            return None
    
    def _collect_wmi_metrics(self, ip: str) -> Optional[Dict]:
        """Collect metrics from Windows system via WMI"""
        if not WMI_AVAILABLE:
            return None
        
        try:
            # Connect to remote Windows machine
            # Note: In production, get credentials from secure vault
            conn = wmi.WMI(computer=ip, user="admin", password="password")
            
            metrics = {}
            
            # CPU
            for cpu in conn.Win32_Processor():
                metrics['cpu_percent'] = float(cpu.LoadPercentage or 0)
            
            # RAM
            for mem in conn.Win32_OperatingSystem():
                total_mb = int(mem.TotalVisibleMemorySize) / 1024
                free_mb = int(mem.FreePhysicalMemory) / 1024
                used_mb = total_mb - free_mb
                metrics['ram_total_gb'] = round(total_mb / 1024, 2)
                metrics['ram_used_gb'] = round(used_mb / 1024, 2)
                metrics['ram_percent'] = round((used_mb / total_mb) * 100, 2)
            
            # Disk
            for disk in conn.Win32_LogicalDisk(DriveType=3):  # Fixed disks
                total_gb = int(disk.Size) / (1024**3)
                free_gb = int(disk.FreeSpace) / (1024**3)
                used_gb = total_gb - free_gb
                metrics['disk_total_gb'] = round(total_gb, 2)
                metrics['disk_used_gb'] = round(used_gb, 2)
                metrics['disk_percent'] = round((used_gb / total_gb) * 100, 2)
                break  # First disk only
            
            return metrics
            
        except Exception as e:
            logger.error(f"WMI collection failed for {ip}: {str(e)}")
            return None
    
    def _collect_ssh_metrics(self, ip: str) -> Optional[Dict]:
        """Collect metrics from Linux system via SSH"""
        if not SSH_AVAILABLE:
            return None
        
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # In production, get credentials from secure vault
            ssh.connect(ip, username='monitor', password='password', timeout=10)
            
            metrics = {}
            
            # CPU usage
            stdin, stdout, stderr = ssh.exec_command(
                "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{print 100 - $1}'"
            )
            cpu_output = stdout.read().decode().strip()
            metrics['cpu_percent'] = float(cpu_output) if cpu_output else 0.0
            
            # RAM usage
            stdin, stdout, stderr = ssh.exec_command(
                "free -m | awk 'NR==2{printf \"%s %s %.2f\", $2,$3,$3*100/$2 }'"
            )
            ram_output = stdout.read().decode().strip().split()
            if len(ram_output) == 3:
                metrics['ram_total_gb'] = round(float(ram_output[0]) / 1024, 2)
                metrics['ram_used_gb'] = round(float(ram_output[1]) / 1024, 2)
                metrics['ram_percent'] = float(ram_output[2])
            
            # Disk usage
            stdin, stdout, stderr = ssh.exec_command(
                "df -h / | awk 'NR==2{printf \"%s %s %s\", $2,$3,$5}'"
            )
            disk_output = stdout.read().decode().strip().split()
            if len(disk_output) == 3:
                metrics['disk_total_gb'] = self._parse_size(disk_output[0])
                metrics['disk_used_gb'] = self._parse_size(disk_output[1])
                metrics['disk_percent'] = float(disk_output[2].replace('%', ''))
            
            ssh.close()
            return metrics
            
        except Exception as e:
            logger.error(f"SSH collection failed for {ip}: {str(e)}")
            return None
    
    def _collect_snmp_metrics(self, ip: str, community='public') -> Optional[Dict]:
        """Collect metrics via SNMP (works on Windows/Linux)"""
        if not SNMP_AVAILABLE:
            return None
        
        try:
            metrics = {}
            
            # SNMP OIDs for common metrics
            CPU_OID = '1.3.6.1.2.1.25.3.3.1.2'      # Host Resources MIB
            RAM_TOTAL_OID = '1.3.6.1.2.1.25.2.2.0'
            RAM_USED_OID = '1.3.6.1.2.1.25.2.3.1.6'
            
            # Query CPU
            iterator = getCmd(
                SnmpEngine(),
                CommunityData(community),
                UdpTransportTarget((ip, 161), timeout=2, retries=1),
                ContextData(),
                ObjectType(ObjectIdentity(CPU_OID))
            )
            errorIndication, errorStatus, errorIndex, varBinds = next(iterator)
            
            if not errorIndication and not errorStatus:
                for varBind in varBinds:
                    metrics['cpu_percent'] = float(varBind[1])
            
            # Add more SNMP queries as needed
            
            return metrics if metrics else None
            
        except Exception as e:
            logger.error(f"SNMP collection failed for {ip}: {str(e)}")
            return None
    
    def _parse_size(self, size_str: str) -> float:
        """Parse size string like '100G' to GB"""
        size_str = size_str.upper().strip()
        if size_str.endswith('G'):
            return float(size_str[:-1])
        elif size_str.endswith('T'):
            return float(size_str[:-1]) * 1024
        elif size_str.endswith('M'):
            return float(size_str[:-1]) / 1024
        return 0.0
    
    def _save_metrics(self, system_id: int, metrics: Dict):
        """Save metrics to database"""
        self.db.execute("""
            INSERT INTO usage_metrics
            (system_id, timestamp, cpu_percent, ram_total_gb, ram_used_gb, 
             ram_percent, disk_total_gb, disk_used_gb, disk_percent)
            VALUES (%s, NOW(), %s, %s, %s, %s, %s, %s, %s)
        """, (
            system_id,
            metrics.get('cpu_percent', 0),
            metrics.get('ram_total_gb', 0),
            metrics.get('ram_used_gb', 0),
            metrics.get('ram_percent', 0),
            metrics.get('disk_total_gb', 0),
            metrics.get('disk_used_gb', 0),
            metrics.get('disk_percent', 0)
        ))
        
        # Update last_seen
        self.db.execute("""
            UPDATE systems SET last_seen = NOW()
            WHERE system_id = %s
        """, (system_id,))
    
    def _mark_system_offline(self, system_id: int):
        """Mark system as offline"""
        self.db.execute("""
            UPDATE systems 
            SET status = 'offline'
            WHERE system_id = %s
        """, (system_id,))


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='Network Discovery & Metrics Collection')
    parser.add_argument('--scan', type=str, help='Network CIDR to scan (e.g., 10.30.0.0/16)')
    parser.add_argument('--dept', type=str, help='Department name')
    parser.add_argument('--collect-all', action='store_true', help='Collect metrics from all systems')
    parser.add_argument('--db-host', type=str, default=os.getenv('DB_HOST', 'localhost'), help='Database host')
    parser.add_argument('--db-name', type=str, default=os.getenv('DB_NAME', 'lab_resource_monitor'), help='Database name')
    parser.add_argument('--db-user', type=str, default=os.getenv('DB_USER', 'postgres'), help='Database user')
    parser.add_argument('--db-pass', type=str, default=os.getenv('DB_PASSWORD', 'postgres'), help='Database password')
    
    args = parser.parse_args()
    
    # Connect to database
    db = DatabaseConnection(
        host=args.db_host,
        database=args.db_name,
        user=args.db_user,
        password=args.db_pass
    )
    db.connect()
    
    try:
        if args.scan and args.dept:
            # Get department ID
            dept = db.execute("""
                SELECT dept_id FROM departments WHERE dept_name = %s
            """, (args.dept,), fetch=True)
            
            if not dept:
                logger.error(f"Department '{args.dept}' not found")
                return
            
            dept_id = dept[0]['dept_id']
            
            # Run network scan
            discovery = NetworkDiscovery(db)
            systems = discovery.scan_network(args.scan, dept_id)
            
            # ...existing code...
        
        elif args.collect_all:
            # Collect metrics from all systems
            collector = MetricsCollector(db)
            collector.collect_all_metrics()
        
        else:
            parser.print_help()
    
    finally:
        db.close()


if __name__ == '__main__':
    main()
