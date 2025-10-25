"""
System Tests for OptiLab Smart Lab Resource Monitoring System

Tests all core components:
- Database connectivity
- Connection pooling
- Adaptive scheduler
- API endpoints
- Metric collection
"""

import sys
import os
from pathlib import Path

# Add parent directories to path
sys.path.insert(0, str(Path(__file__).parent.parent / 'collector'))
sys.path.insert(0, str(Path(__file__).parent.parent / 'api'))

import psycopg2
from datetime import datetime


class TestSystem:
    """Main test suite for OptiLab system"""
    
    def __init__(self):
        self.results = {
            'passed': 0,
            'failed': 0,
            'warnings': 0
        }
        self.db_config = {
            'host': os.getenv('DB_HOST', 'localhost'),
            'port': os.getenv('DB_PORT', 5432),
            'database': os.getenv('DB_NAME', 'lab_resource_monitor'),
            'user': os.getenv('DB_USER', 'postgres'),
            'password': os.getenv('DB_PASSWORD', '1010')
        }
    
    def print_header(self, text):
        """Print formatted test section header"""
        print(f"\n{'=' * 60}")
        print(f"  {text}")
        print('=' * 60)
    
    def print_result(self, test_name, passed, message=""):
        """Print test result"""
        if passed:
            print(f"✓ {test_name}")
            self.results['passed'] += 1
        else:
            print(f"✗ {test_name}")
            if message:
                print(f"  Error: {message}")
            self.results['failed'] += 1
    
    def print_warning(self, message):
        """Print warning message"""
        print(f"⚠ {message}")
        self.results['warnings'] += 1
    
    def test_database_connection(self):
        """Test PostgreSQL database connectivity"""
        self.print_header("1. Database Connection Test")
        
        try:
            conn = psycopg2.connect(**self.db_config)
            cursor = conn.cursor()
            
            # Test connection
            cursor.execute("SELECT version();")
            version = cursor.fetchone()[0]
            self.print_result("Database connection", True)
            print(f"  PostgreSQL version: {version.split(',')[0]}")
            
            # Check required tables
            cursor.execute("""
                SELECT table_name FROM information_schema.tables 
                WHERE table_schema = 'public'
                ORDER BY table_name;
            """)
            tables = [row[0] for row in cursor.fetchall()]
            
            required_tables = ['systems', 'usage_metrics', 'alerts']
            missing_tables = [t for t in required_tables if t not in tables]
            
            if missing_tables:
                self.print_result("Database schema", False, 
                                f"Missing tables: {', '.join(missing_tables)}")
            else:
                self.print_result("Database schema", True)
                print(f"  Found tables: {', '.join(tables)}")
            
            # Check for TimescaleDB
            cursor.execute("""
                SELECT EXISTS(
                    SELECT 1 FROM pg_extension WHERE extname = 'timescaledb'
                );
            """)
            has_timescaledb = cursor.fetchone()[0]
            
            if has_timescaledb:
                self.print_result("TimescaleDB extension", True)
                
                # Check for hypertables
                cursor.execute("""
                    SELECT hypertable_name 
                    FROM timescaledb_information.hypertables;
                """)
                hypertables = [row[0] for row in cursor.fetchall()]
                if hypertables:
                    print(f"  Hypertables: {', '.join(hypertables)}")
                else:
                    self.print_warning("No hypertables found (run setup_timescaledb.sql)")
            else:
                self.print_warning("TimescaleDB extension not installed (optional)")
            
            # Check system count
            cursor.execute("SELECT COUNT(*) FROM systems;")
            system_count = cursor.fetchone()[0]
            print(f"  Systems in database: {system_count}")
            
            cursor.close()
            conn.close()
            
            return True
            
        except Exception as e:
            self.print_result("Database connection", False, str(e))
            return False
    
    def test_connection_pool(self):
        """Test connection pooling functionality"""
        self.print_header("2. Connection Pool Test")
        
        try:
            from connection_pool import SSHConnectionPool, WMIConnectionPool
            
            # Test SSH pool
            ssh_pool = SSHConnectionPool(max_connections=5)
            self.print_result("SSH connection pool initialization", True)
            
            stats = ssh_pool.get_stats()
            print(f"  Active connections: {stats['active_connections']}")
            print(f"  Max connections: {stats['max_connections']}")
            
            # Test WMI pool
            wmi_pool = WMIConnectionPool(max_connections=5)
            self.print_result("WMI connection pool initialization", True)
            
            stats = wmi_pool.get_stats()
            print(f"  Cached connections: {stats['cached_connections']}")
            
            return True
            
        except ImportError:
            self.print_warning("Connection pool module not found (check collector/)")
            return False
        except Exception as e:
            self.print_result("Connection pool", False, str(e))
            return False
    
    def test_adaptive_scheduler(self):
        """Test adaptive scheduling functionality"""
        self.print_header("3. Adaptive Scheduler Test")
        
        try:
            from adaptive_scheduler import AdaptiveScheduler, SystemHealth
            
            scheduler = AdaptiveScheduler()
            self.print_result("Adaptive scheduler initialization", True)
            
            # Test health state transitions
            test_system = {
                'id': 999,
                'hostname': 'test-system',
                'ip_address': '192.168.0.999'
            }
            
            # Record healthy system
            scheduler.record_success(test_system)
            interval = scheduler.get_poll_interval(test_system)
            self.print_result("Healthy system interval", interval == 300,
                            f"Expected 300s, got {interval}s")
            
            # Simulate failure
            scheduler.record_failure(test_system)
            interval = scheduler.get_poll_interval(test_system)
            expected = 600  # Should be degraded (2x)
            self.print_result("Degraded system interval", interval == expected,
                            f"Expected {expected}s, got {interval}s")
            
            # Get statistics
            stats = scheduler.get_statistics()
            print(f"  Total systems tracked: {stats['total_systems']}")
            print(f"  Healthy: {stats['healthy']}")
            print(f"  Degraded: {stats['degraded']}")
            print(f"  Offline: {stats['offline']}")
            print(f"  Dead: {stats['dead']}")
            
            return True
            
        except ImportError:
            self.print_warning("Adaptive scheduler module not found")
            return False
        except Exception as e:
            self.print_result("Adaptive scheduler", False, str(e))
            return False
    
    def test_message_queue(self):
        """Test message queue functionality"""
        self.print_header("4. Message Queue Test")
        
        try:
            from message_queue import MessageQueue
            import pika
            
            # Try to connect to RabbitMQ
            try:
                connection = pika.BlockingConnection(
                    pika.ConnectionParameters(
                        host=os.getenv('RABBITMQ_HOST', 'localhost'),
                        port=int(os.getenv('RABBITMQ_PORT', 5672))
                    )
                )
                connection.close()
                
                # Test message queue
                mq = MessageQueue()
                self.print_result("Message queue initialization", True)
                
                # Test metric publishing
                test_metric = {
                    'system_id': 1,
                    'cpu_usage': 25.5,
                    'ram_usage': 42.3,
                    'disk_usage': 68.9
                }
                mq.publish_metric(test_metric)
                self.print_result("Metric publishing", True)
                
                mq.close()
                
            except Exception as e:
                self.print_warning(f"RabbitMQ not available: {str(e)}")
                self.print_warning("Message queue is optional (install RabbitMQ for this feature)")
                
            return True
            
        except ImportError:
            self.print_warning("Message queue module or pika not found")
            return False
        except Exception as e:
            self.print_result("Message queue", False, str(e))
            return False
    
    def test_api_server(self):
        """Test API endpoints"""
        self.print_header("5. API Server Test")
        
        try:
            import requests
            
            base_url = "http://localhost:8000"
            
            # Test health endpoint
            try:
                response = requests.get(f"{base_url}/health", timeout=2)
                if response.status_code == 200:
                    self.print_result("API health endpoint", True)
                    data = response.json()
                    print(f"  Status: {data.get('status', 'unknown')}")
                else:
                    self.print_result("API health endpoint", False, 
                                    f"Status code: {response.status_code}")
            except requests.exceptions.ConnectionError:
                self.print_warning("API server not running (start with: uvicorn main:app)")
                return False
            
            # Test systems endpoint
            try:
                response = requests.get(f"{base_url}/systems", timeout=2)
                if response.status_code == 200:
                    self.print_result("API systems endpoint", True)
                    data = response.json()
                    print(f"  Systems returned: {len(data.get('systems', []))}")
                else:
                    self.print_result("API systems endpoint", False,
                                    f"Status code: {response.status_code}")
            except Exception as e:
                self.print_result("API systems endpoint", False, str(e))
            
            # Test Prometheus metrics
            try:
                response = requests.get(f"{base_url}/metrics", timeout=2)
                if response.status_code == 200:
                    self.print_result("Prometheus metrics endpoint", True)
                    metrics_count = len(response.text.split('\n'))
                    print(f"  Metrics lines: {metrics_count}")
                else:
                    self.print_result("Prometheus metrics endpoint", False,
                                    f"Status code: {response.status_code}")
            except Exception as e:
                self.print_result("Prometheus metrics endpoint", False, str(e))
            
            return True
            
        except ImportError:
            self.print_warning("requests module not found (pip install requests)")
            return False
        except Exception as e:
            self.print_result("API server", False, str(e))
            return False
    
    def test_performance(self):
        """Test system performance"""
        self.print_header("6. Performance Test")
        
        try:
            import time
            
            # Test database query performance
            conn = psycopg2.connect(**self.db_config)
            cursor = conn.cursor()
            
            start = time.time()
            cursor.execute("SELECT COUNT(*) FROM usage_metrics;")
            metric_count = cursor.fetchone()[0]
            elapsed = (time.time() - start) * 1000  # Convert to ms
            
            self.print_result("Database query performance", elapsed < 100,
                            f"Query took {elapsed:.2f}ms (target: <100ms)")
            print(f"  Total metrics in database: {metric_count}")
            
            # Test index usage
            cursor.execute("""
                SELECT schemaname, tablename, indexname
                FROM pg_indexes
                WHERE tablename IN ('systems', 'usage_metrics', 'alerts')
                ORDER BY tablename, indexname;
            """)
            indexes = cursor.fetchall()
            print(f"  Database indexes: {len(indexes)}")
            
            cursor.close()
            conn.close()
            
            return True
            
        except Exception as e:
            self.print_result("Performance test", False, str(e))
            return False
    
    def run_all_tests(self):
        """Run all tests and print summary"""
        print("\n" + "=" * 60)
        print("  OptiLab System Test Suite")
        print("  " + datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        print("=" * 60)
        
        # Run tests
        self.test_database_connection()
        self.test_connection_pool()
        self.test_adaptive_scheduler()
        self.test_message_queue()
        self.test_api_server()
        self.test_performance()
        
        # Print summary
        self.print_header("Test Summary")
        total = self.results['passed'] + self.results['failed']
        print(f"  Passed:   {self.results['passed']}/{total}")
        print(f"  Failed:   {self.results['failed']}/{total}")
        print(f"  Warnings: {self.results['warnings']}")
        
        if self.results['failed'] == 0:
            print("\n✓ All tests passed!")
        else:
            print(f"\n✗ {self.results['failed']} test(s) failed")
        
        print("=" * 60)
        
        return self.results['failed'] == 0


if __name__ == "__main__":
    tester = TestSystem()
    success = tester.run_all_tests()
    sys.exit(0 if success else 1)
