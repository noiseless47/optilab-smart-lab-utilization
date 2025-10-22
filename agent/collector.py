"""
System Resource Monitoring Agent
Collects CPU, RAM, GPU, Disk, Network metrics and sends to central database
"""

import psutil
import platform
import socket
import json
import time
import uuid
import logging
from datetime import datetime
from typing import Dict, Optional, List
import requests
import yaml
from pathlib import Path

# Try to import GPU monitoring (optional)
try:
    import GPUtil
    GPU_AVAILABLE = True
except ImportError:
    GPU_AVAILABLE = False
    print("Warning: GPUtil not installed. GPU monitoring disabled.")
    print("Install with: pip install gputil")

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('agent.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)


class SystemMetricsCollector:
    """Collects system performance metrics"""
    
    def __init__(self, config_path: str = "config.yaml"):
        self.config = self._load_config(config_path)
        self.system_id = self._get_or_create_system_id()
        self.hostname = socket.gethostname()
        
        # Initialize network counters for delta calculations
        self.last_net_io = psutil.net_io_counters()
        self.last_disk_io = psutil.disk_io_counters()
        self.last_check_time = time.time()
        
        logger.info(f"Metrics collector initialized for {self.hostname} (ID: {self.system_id})")
    
    def _load_config(self, config_path: str) -> Dict:
        """Load configuration from YAML file"""
        config_file = Path(config_path)
        if not config_file.exists():
            logger.warning(f"Config file {config_path} not found. Using defaults.")
            return self._default_config()
        
        with open(config_path, 'r') as f:
            config = yaml.safe_load(f)
        logger.info(f"Configuration loaded from {config_path}")
        return config
    
    def _default_config(self) -> Dict:
        """Default configuration"""
        return {
            'api': {
                'endpoint': 'http://localhost:8000/api/metrics',
                'timeout': 10
            },
            'collection': {
                'interval_seconds': 300,  # 5 minutes
                'include_processes': True,
                'process_limit': 10
            },
            'system': {
                'location': 'Unknown',
                'department': 'Unknown'
            }
        }
    
    def _get_or_create_system_id(self) -> str:
        """Get or create persistent system UUID"""
        id_file = Path('.system_id')
        
        if id_file.exists():
            with open(id_file, 'r') as f:
                system_id = f.read().strip()
                logger.info(f"Loaded existing system ID: {system_id}")
                return system_id
        else:
            system_id = str(uuid.uuid4())
            with open(id_file, 'w') as f:
                f.write(system_id)
            logger.info(f"Created new system ID: {system_id}")
            return system_id
    
    def collect_cpu_metrics(self) -> Dict:
        """Collect CPU-related metrics"""
        try:
            cpu_percent = psutil.cpu_percent(interval=1)
            cpu_per_core = psutil.cpu_percent(interval=1, percpu=True)
            cpu_freq = psutil.cpu_freq()
            load_avg = psutil.getloadavg() if hasattr(psutil, 'getloadavg') else (0, 0, 0)
            
            # Try to get CPU temperature (Linux only)
            cpu_temp = None
            if hasattr(psutil, 'sensors_temperatures'):
                temps = psutil.sensors_temperatures()
                if temps and 'coretemp' in temps:
                    cpu_temp = temps['coretemp'][0].current
            
            return {
                'cpu_percent': round(cpu_percent, 2),
                'cpu_per_core': [round(x, 2) for x in cpu_per_core],
                'cpu_freq_current': round(cpu_freq.current, 2) if cpu_freq else None,
                'cpu_temp': round(cpu_temp, 2) if cpu_temp else None,
                'load_avg_1min': round(load_avg[0], 2),
                'load_avg_5min': round(load_avg[1], 2),
                'load_avg_15min': round(load_avg[2], 2)
            }
        except Exception as e:
            logger.error(f"Error collecting CPU metrics: {e}")
            return {}
    
    def collect_memory_metrics(self) -> Dict:
        """Collect memory-related metrics"""
        try:
            mem = psutil.virtual_memory()
            swap = psutil.swap_memory()
            
            return {
                'ram_used_gb': round(mem.used / (1024**3), 2),
                'ram_available_gb': round(mem.available / (1024**3), 2),
                'ram_percent': round(mem.percent, 2),
                'swap_used_gb': round(swap.used / (1024**3), 2),
                'swap_percent': round(swap.percent, 2)
            }
        except Exception as e:
            logger.error(f"Error collecting memory metrics: {e}")
            return {}
    
    def collect_gpu_metrics(self) -> Dict:
        """Collect GPU-related metrics (NVIDIA only)"""
        if not GPU_AVAILABLE:
            return {}
        
        try:
            gpus = GPUtil.getGPUs()
            if not gpus:
                return {}
            
            # Use first GPU (can be extended for multi-GPU)
            gpu = gpus[0]
            
            return {
                'gpu_utilization': round(gpu.load * 100, 2),
                'gpu_memory_used_gb': round(gpu.memoryUsed / 1024, 2),
                'gpu_memory_percent': round(gpu.memoryUtil * 100, 2),
                'gpu_temp': round(gpu.temperature, 2),
                'gpu_power_draw': None  # Not available in GPUtil
            }
        except Exception as e:
            logger.error(f"Error collecting GPU metrics: {e}")
            return {}
    
    def collect_disk_metrics(self) -> Dict:
        """Collect disk I/O and usage metrics"""
        try:
            disk_usage = psutil.disk_usage('/')
            disk_io = psutil.disk_io_counters()
            
            # Calculate I/O rates
            current_time = time.time()
            time_delta = current_time - self.last_check_time
            
            if time_delta > 0 and self.last_disk_io:
                read_mb_s = (disk_io.read_bytes - self.last_disk_io.read_bytes) / (1024**2) / time_delta
                write_mb_s = (disk_io.write_bytes - self.last_disk_io.write_bytes) / (1024**2) / time_delta
                read_ops = int((disk_io.read_count - self.last_disk_io.read_count) / time_delta)
                write_ops = int((disk_io.write_count - self.last_disk_io.write_count) / time_delta)
            else:
                read_mb_s = write_mb_s = read_ops = write_ops = 0
            
            self.last_disk_io = disk_io
            
            return {
                'disk_read_mb_s': round(read_mb_s, 2),
                'disk_write_mb_s': round(write_mb_s, 2),
                'disk_read_ops': read_ops,
                'disk_write_ops': write_ops,
                'disk_io_wait_percent': None,  # Requires platform-specific implementation
                'disk_used_gb': round(disk_usage.used / (1024**3), 2),
                'disk_percent': round(disk_usage.percent, 2)
            }
        except Exception as e:
            logger.error(f"Error collecting disk metrics: {e}")
            return {}
    
    def collect_network_metrics(self) -> Dict:
        """Collect network I/O metrics"""
        try:
            net_io = psutil.net_io_counters()
            
            # Calculate network rates
            current_time = time.time()
            time_delta = current_time - self.last_check_time
            
            if time_delta > 0 and self.last_net_io:
                sent_mb_s = (net_io.bytes_sent - self.last_net_io.bytes_sent) / (1024**2) / time_delta
                recv_mb_s = (net_io.bytes_recv - self.last_net_io.bytes_recv) / (1024**2) / time_delta
                packets_sent = int((net_io.packets_sent - self.last_net_io.packets_sent) / time_delta)
                packets_recv = int((net_io.packets_recv - self.last_net_io.packets_recv) / time_delta)
            else:
                sent_mb_s = recv_mb_s = packets_sent = packets_recv = 0
            
            self.last_net_io = net_io
            self.last_check_time = current_time
            
            return {
                'net_sent_mb_s': round(sent_mb_s, 2),
                'net_recv_mb_s': round(recv_mb_s, 2),
                'net_packets_sent': packets_sent,
                'net_packets_recv': packets_recv
            }
        except Exception as e:
            logger.error(f"Error collecting network metrics: {e}")
            return {}
    
    def collect_process_metrics(self) -> Dict:
        """Collect process count and top processes"""
        try:
            processes = list(psutil.process_iter(['pid', 'name', 'cpu_percent', 'memory_percent']))
            
            # Get top CPU-consuming processes
            if self.config['collection']['include_processes']:
                top_processes = sorted(
                    processes,
                    key=lambda p: p.info.get('cpu_percent', 0),
                    reverse=True
                )[:self.config['collection']['process_limit']]
                
                process_list = [
                    {
                        'name': p.info.get('name'),
                        'pid': p.info.get('pid'),
                        'cpu_percent': round(p.info.get('cpu_percent', 0), 2),
                        'memory_percent': round(p.info.get('memory_percent', 0), 2)
                    }
                    for p in top_processes
                ]
            else:
                process_list = []
            
            return {
                'process_count': len(processes),
                'thread_count': sum(1 for _ in psutil.process_iter()),
                'top_processes': process_list
            }
        except Exception as e:
            logger.error(f"Error collecting process metrics: {e}")
            return {'process_count': 0, 'thread_count': 0, 'top_processes': []}
    
    def collect_system_info(self) -> Dict:
        """Collect static system information"""
        try:
            uname = platform.uname()
            cpu_freq = psutil.cpu_freq()
            mem = psutil.virtual_memory()
            disk = psutil.disk_usage('/')
            
            # Get GPU info
            gpu_info = {}
            if GPU_AVAILABLE:
                gpus = GPUtil.getGPUs()
                if gpus:
                    gpu = gpus[0]
                    gpu_info = {
                        'gpu_model': gpu.name,
                        'gpu_memory_gb': round(gpu.memoryTotal / 1024, 2),
                        'gpu_count': len(gpus)
                    }
            
            return {
                'hostname': self.hostname,
                'ip_address': socket.gethostbyname(self.hostname),
                'location': self.config['system']['location'],
                'department': self.config['system']['department'],
                'cpu_model': uname.processor or platform.processor(),
                'cpu_cores': psutil.cpu_count(logical=False),
                'cpu_threads': psutil.cpu_count(logical=True),
                'cpu_base_freq': round(cpu_freq.current / 1000, 2) if cpu_freq else None,
                'ram_total_gb': round(mem.total / (1024**3), 2),
                'ram_type': 'Unknown',  # Requires platform-specific implementation
                'disk_total_gb': round(disk.total / (1024**3), 2),
                'disk_type': 'Unknown',  # Requires platform-specific implementation
                'os_name': uname.system,
                'os_version': uname.version,
                **gpu_info
            }
        except Exception as e:
            logger.error(f"Error collecting system info: {e}")
            return {}
    
    def collect_all_metrics(self) -> Dict:
        """Collect all metrics"""
        start_time = time.time()
        
        metrics = {
            'system_id': self.system_id,
            'timestamp': datetime.utcnow().isoformat(),
            **self.collect_cpu_metrics(),
            **self.collect_memory_metrics(),
            **self.collect_gpu_metrics(),
            **self.collect_disk_metrics(),
            **self.collect_network_metrics(),
            **self.collect_process_metrics()
        }
        
        collection_time = int((time.time() - start_time) * 1000)
        metrics['collection_duration_ms'] = collection_time
        
        logger.info(f"Metrics collected in {collection_time}ms")
        return metrics
    
    def send_metrics(self, metrics: Dict) -> bool:
        """Send metrics to API endpoint"""
        try:
            endpoint = self.config['api']['endpoint']
            timeout = self.config['api']['timeout']
            
            response = requests.post(
                endpoint,
                json=metrics,
                timeout=timeout,
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code == 200:
                logger.info("Metrics sent successfully")
                return True
            else:
                logger.error(f"Failed to send metrics: {response.status_code} - {response.text}")
                return False
        
        except requests.exceptions.RequestException as e:
            logger.error(f"Error sending metrics: {e}")
            return False
    
    def register_system(self) -> bool:
        """Register system with central database"""
        try:
            system_info = self.collect_system_info()
            system_info['system_id'] = self.system_id
            
            endpoint = self.config['api']['endpoint'].replace('/metrics', '/systems/register')
            response = requests.post(
                endpoint,
                json=system_info,
                timeout=self.config['api']['timeout'],
                headers={'Content-Type': 'application/json'}
            )
            
            if response.status_code in [200, 201]:
                logger.info("System registered successfully")
                return True
            else:
                logger.warning(f"System registration returned: {response.status_code}")
                return False
        
        except Exception as e:
            logger.error(f"Error registering system: {e}")
            return False


def main():
    """Main agent loop"""
    collector = SystemMetricsCollector()
    
    # Register system on startup
    collector.register_system()
    
    # Collection interval
    interval = collector.config['collection']['interval_seconds']
    logger.info(f"Starting metrics collection every {interval} seconds")
    
    while True:
        try:
            # Collect metrics
            metrics = collector.collect_all_metrics()
            
            # Send to API
            collector.send_metrics(metrics)
            
            # Wait for next interval
            time.sleep(interval)
        
        except KeyboardInterrupt:
            logger.info("Agent stopped by user")
            break
        
        except Exception as e:
            logger.error(f"Unexpected error in main loop: {e}")
            time.sleep(interval)


if __name__ == "__main__":
    main()
