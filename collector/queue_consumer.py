#!/usr/bin/env python3
"""
OptiLab Queue Consumer
Consumes messages from RabbitMQ/Redis and processes them into the database
"""

import os
import sys
import json
import time
import logging
import signal
from datetime import datetime
from typing import Dict, Any, Optional

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
except ImportError:
    print("Error: psycopg2 not installed. Install with: pip install psycopg2-binary")
    sys.exit(1)

# Try to import queue libraries (optional)
try:
    import pika  # RabbitMQ
    RABBITMQ_AVAILABLE = True
except ImportError:
    RABBITMQ_AVAILABLE = False

try:
    import redis  # Redis
    REDIS_AVAILABLE = True
except ImportError:
    REDIS_AVAILABLE = False

# Configuration
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', '5432')),
    'database': os.getenv('DB_NAME', 'optilab'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', 'your_password'),
}

QUEUE_CONFIG = {
    'type': os.getenv('QUEUE_TYPE', 'rabbitmq'),  # rabbitmq, redis
    'host': os.getenv('QUEUE_HOST', 'localhost'),
    'port': int(os.getenv('QUEUE_PORT', '5672')),
    'user': os.getenv('QUEUE_USER', 'guest'),
    'password': os.getenv('QUEUE_PASSWORD', 'guest'),
}

QUEUE_NAMES = {
    'discovery': os.getenv('DISCOVERY_QUEUE', 'discovery_queue'),
    'metrics': os.getenv('METRICS_QUEUE', 'metrics_queue'),
    'alerts': os.getenv('ALERT_QUEUE', 'alert_queue'),
}

# Logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('queue_consumer')

# Global flag for graceful shutdown
shutdown_flag = False


def signal_handler(signum, frame):
    """Handle shutdown signals"""
    global shutdown_flag
    logger.info(f"Received signal {signum}, shutting down gracefully...")
    shutdown_flag = True


signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)


class DatabaseHandler:
    """Handle database operations"""
    
    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.conn = None
        self.connect()
    
    def connect(self):
        """Connect to PostgreSQL"""
        try:
            self.conn = psycopg2.connect(**self.config)
            self.conn.autocommit = False
            logger.info("Connected to database")
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            raise
    
    def reconnect(self):
        """Reconnect if connection lost"""
        if self.conn:
            try:
                self.conn.close()
            except:
                pass
        self.connect()
    
    def insert_discovered_system(self, data: Dict[str, Any]) -> bool:
        """Insert or update discovered system"""
        try:
            with self.conn.cursor() as cur:
                query = """
                INSERT INTO systems (hostname, ip_address, mac_address, dept_id, status, created_at)
                VALUES (%(hostname)s, %(ip_address)s, %(mac_address)s, %(dept_id)s, 'discovered', NOW())
                ON CONFLICT (ip_address) 
                DO UPDATE SET 
                    hostname = EXCLUDED.hostname,
                    mac_address = EXCLUDED.mac_address,
                    dept_id = EXCLUDED.dept_id,
                    status = 'discovered',
                    updated_at = NOW()
                RETURNING system_id;
                """
                
                cur.execute(query, {
                    'hostname': data.get('hostname', 'unknown'),
                    'ip_address': data['ip_address'],
                    'mac_address': data.get('mac_address'),
                    'dept_id': data.get('dept_id'),
                })
                
                result = cur.fetchone()
                self.conn.commit()
                
                system_id = result[0] if result else None
                logger.info(f"Inserted/updated system: {data['ip_address']} (ID: {system_id})")
                return True
                
        except Exception as e:
            logger.error(f"Failed to insert system: {e}")
            self.conn.rollback()
            return False
    
    def insert_metrics(self, data: Dict[str, Any]) -> bool:
        """Insert metrics data"""
        try:
            with self.conn.cursor() as cur:
                metrics = data.get('metrics', {})
                
                query = """
                INSERT INTO metrics (
                    system_id, timestamp,
                    cpu_percent, cpu_temperature,
                    ram_percent,
                    disk_percent, disk_read_mbps, disk_write_mbps,
                    network_sent_mbps, network_recv_mbps,
                    gpu_percent, gpu_memory_used_gb, gpu_temperature,
                    uptime_seconds, logged_in_users
                ) VALUES (
                    %(system_id)s, NOW(),
                    %(cpu_percent)s, %(cpu_temperature)s,
                    %(ram_percent)s,
                    %(disk_percent)s, %(disk_read_mbps)s, %(disk_write_mbps)s,
                    %(network_sent_mbps)s, %(network_recv_mbps)s,
                    %(gpu_percent)s, %(gpu_memory_used_gb)s, %(gpu_temperature)s,
                    %(uptime_seconds)s, %(logged_in_users)s
                );
                """
                
                cur.execute(query, {
                    'system_id': data['system_id'],
                    'cpu_percent': metrics.get('cpu_percent'),
                    'cpu_temperature': metrics.get('cpu_temperature'),
                    'ram_percent': metrics.get('ram_percent'),
                    'disk_percent': metrics.get('disk_percent'),
                    'disk_read_mbps': metrics.get('disk_read_mbps'),
                    'disk_write_mbps': metrics.get('disk_write_mbps'),
                    'network_sent_mbps': metrics.get('network_sent_mbps'),
                    'network_recv_mbps': metrics.get('network_recv_mbps'),
                    'gpu_percent': metrics.get('gpu_percent'),
                    'gpu_memory_used_gb': metrics.get('gpu_memory_used_gb'),
                    'gpu_temperature': metrics.get('gpu_temperature'),
                    'uptime_seconds': metrics.get('uptime_seconds'),
                    'logged_in_users': metrics.get('logged_in_users'),
                })
                
                self.conn.commit()
                logger.info(f"Inserted metrics for system_id: {data['system_id']}")
                return True
                
        except Exception as e:
            logger.error(f"Failed to insert metrics: {e}")
            self.conn.rollback()
            return False
    
    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()
            logger.info("Database connection closed")


class RabbitMQConsumer:
    """RabbitMQ consumer"""
    
    def __init__(self, config: Dict[str, Any], db_handler: DatabaseHandler):
        if not RABBITMQ_AVAILABLE:
            raise RuntimeError("pika library not installed. Install with: pip install pika")
        
        self.config = config
        self.db_handler = db_handler
        self.connection = None
        self.channel = None
        self.connect()
    
    def connect(self):
        """Connect to RabbitMQ"""
        try:
            credentials = pika.PlainCredentials(
                self.config['user'],
                self.config['password']
            )
            
            parameters = pika.ConnectionParameters(
                host=self.config['host'],
                port=self.config['port'],
                credentials=credentials,
                heartbeat=600,
                blocked_connection_timeout=300,
            )
            
            self.connection = pika.BlockingConnection(parameters)
            self.channel = self.connection.channel()
            
            # Declare queues
            for queue_name in QUEUE_NAMES.values():
                self.channel.queue_declare(queue=queue_name, durable=True)
            
            logger.info("Connected to RabbitMQ")
            
        except Exception as e:
            logger.error(f"RabbitMQ connection failed: {e}")
            raise
    
    def process_message(self, ch, method, properties, body):
        """Process incoming message"""
        try:
            data = json.loads(body)
            queue_name = method.routing_key
            
            logger.info(f"Processing message from {queue_name}")
            
            success = False
            
            # Route to appropriate handler
            if queue_name == QUEUE_NAMES['discovery']:
                success = self.db_handler.insert_discovered_system(data)
            elif queue_name == QUEUE_NAMES['metrics']:
                success = self.db_handler.insert_metrics(data)
            elif queue_name == QUEUE_NAMES['alerts']:
                # Handle alerts (could send notifications, etc.)
                logger.info(f"Alert received: {data}")
                success = True
            
            if success:
                ch.basic_ack(delivery_tag=method.delivery_tag)
            else:
                # Reject and requeue if processing failed
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
                
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON message: {e}")
            ch.basic_ack(delivery_tag=method.delivery_tag)  # Discard bad message
        except Exception as e:
            logger.error(f"Error processing message: {e}")
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
    
    def start_consuming(self, queue_name: str):
        """Start consuming from queue"""
        self.channel.basic_qos(prefetch_count=1)
        self.channel.basic_consume(
            queue=queue_name,
            on_message_callback=self.process_message
        )
        
        logger.info(f"Started consuming from {queue_name}")
        
        try:
            while not shutdown_flag:
                self.connection.process_data_events(time_limit=1)
        except KeyboardInterrupt:
            pass
        finally:
            self.stop()
    
    def stop(self):
        """Stop consuming and close connection"""
        if self.channel:
            self.channel.stop_consuming()
        if self.connection:
            self.connection.close()
        logger.info("RabbitMQ consumer stopped")


class RedisConsumer:
    """Redis consumer (using lists as queues)"""
    
    def __init__(self, config: Dict[str, Any], db_handler: DatabaseHandler):
        if not REDIS_AVAILABLE:
            raise RuntimeError("redis library not installed. Install with: pip install redis")
        
        self.config = config
        self.db_handler = db_handler
        self.client = None
        self.connect()
    
    def connect(self):
        """Connect to Redis"""
        try:
            self.client = redis.Redis(
                host=self.config['host'],
                port=self.config['port'],
                decode_responses=True
            )
            self.client.ping()
            logger.info("Connected to Redis")
        except Exception as e:
            logger.error(f"Redis connection failed: {e}")
            raise
    
    def start_consuming(self, queue_name: str):
        """Start consuming from Redis list"""
        logger.info(f"Started consuming from {queue_name}")
        
        try:
            while not shutdown_flag:
                # Blocking pop with timeout
                result = self.client.blpop(queue_name, timeout=1)
                
                if result:
                    _, message = result
                    try:
                        data = json.loads(message)
                        
                        # Route to appropriate handler
                        if queue_name == QUEUE_NAMES['discovery']:
                            self.db_handler.insert_discovered_system(data)
                        elif queue_name == QUEUE_NAMES['metrics']:
                            self.db_handler.insert_metrics(data)
                        elif queue_name == QUEUE_NAMES['alerts']:
                            logger.info(f"Alert received: {data}")
                        
                    except json.JSONDecodeError as e:
                        logger.error(f"Invalid JSON message: {e}")
                    except Exception as e:
                        logger.error(f"Error processing message: {e}")
                        # Could push to dead letter queue here
                
        except KeyboardInterrupt:
            pass
        finally:
            self.stop()
    
    def stop(self):
        """Close Redis connection"""
        if self.client:
            self.client.close()
        logger.info("Redis consumer stopped")


def main():
    """Main entry point"""
    logger.info("=== OptiLab Queue Consumer ===")
    logger.info(f"Queue Type: {QUEUE_CONFIG['type']}")
    logger.info(f"Database: {DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['database']}")
    
    # Get queue to consume from
    queue_name = sys.argv[1] if len(sys.argv) > 1 else 'metrics'
    if queue_name not in QUEUE_NAMES:
        logger.error(f"Invalid queue name. Choose from: {list(QUEUE_NAMES.keys())}")
        sys.exit(1)
    
    queue_full_name = QUEUE_NAMES[queue_name]
    logger.info(f"Consuming from: {queue_full_name}")
    
    # Initialize database handler
    db_handler = DatabaseHandler(DB_CONFIG)
    
    try:
        # Initialize consumer based on type
        if QUEUE_CONFIG['type'] == 'rabbitmq':
            consumer = RabbitMQConsumer(QUEUE_CONFIG, db_handler)
            consumer.start_consuming(queue_full_name)
        elif QUEUE_CONFIG['type'] == 'redis':
            consumer = RedisConsumer(QUEUE_CONFIG, db_handler)
            consumer.start_consuming(queue_full_name)
        else:
            logger.error(f"Unknown queue type: {QUEUE_CONFIG['type']}")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Consumer error: {e}")
        sys.exit(1)
    finally:
        db_handler.close()
        logger.info("Consumer shutdown complete")


if __name__ == '__main__':
    main()
