"""
Message Queue Integration (RabbitMQ)
Decouples metrics collection from database writes for better scalability

Benefits:
- Handles spikes without blocking collectors
- Fault tolerance with message persistence
- Easy to scale workers independently
- Backpressure handling

Architecture:
[Collectors] → [RabbitMQ Queues] → [Worker Processes] → [Database]
"""

import pika
import json
import logging
from typing import Dict, Any, Optional, Callable
from datetime import datetime
import os
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)


class MessageQueue:
    """
    RabbitMQ wrapper for async message passing
    
    Queues:
    - metrics: System metrics data
    - discovery: Newly discovered systems
    - alerts: Alert notifications
    - dead_letter: Failed messages for debugging
    """
    
    def __init__(self, host: str = None, port: int = None, user: str = None, password: str = None):
        """
        Initialize RabbitMQ connection
        
        Args:
            host: RabbitMQ host (default: from env or 'localhost')
            port: RabbitMQ port (default: 5672)
            user: RabbitMQ username
            password: RabbitMQ password
        """
        self.host = host or os.getenv('RABBITMQ_HOST', 'localhost')
        self.port = port or int(os.getenv('RABBITMQ_PORT', 5672))
        self.user = user or os.getenv('RABBITMQ_USER', 'guest')
        self.password = password or os.getenv('RABBITMQ_PASSWORD', 'guest')
        
        self.connection_params = pika.ConnectionParameters(
            host=self.host,
            port=self.port,
            credentials=pika.PlainCredentials(self.user, self.password),
            heartbeat=600,
            blocked_connection_timeout=300
        )
        
        self.connection: Optional[pika.BlockingConnection] = None
        self.channel: Optional[pika.channel.Channel] = None
        self._connect()
    
    def _connect(self):
        """Establish connection and declare queues"""
        try:
            self.connection = pika.BlockingConnection(self.connection_params)
            self.channel = self.connection.channel()
            
            # Declare durable queues (survive broker restart)
            queues = ['metrics', 'discovery', 'alerts', 'dead_letter']
            for queue_name in queues:
                self.channel.queue_declare(
                    queue=queue_name, 
                    durable=True,
                    arguments={
                        'x-message-ttl': 86400000,  # 24 hours
                        'x-max-length': 100000  # Max 100k messages
                    }
                )
            
            logger.info(f"Connected to RabbitMQ at {self.host}:{self.port}")
        
        except Exception as e:
            logger.error(f"Failed to connect to RabbitMQ: {e}")
            logger.warning("Message queue unavailable - will use direct database writes")
            self.connection = None
            self.channel = None
    
    def is_connected(self) -> bool:
        """Check if connected to RabbitMQ"""
        return self.connection is not None and self.channel is not None
    
    def _publish(self, queue: str, message: Dict[str, Any]):
        """
        Internal publish method with reconnection logic
        
        Args:
            queue: Queue name
            message: Message dict to publish
        """
        if not self.is_connected():
            logger.warning(f"Not connected to RabbitMQ, cannot publish to {queue}")
            return False
        
        try:
            self.channel.basic_publish(
                exchange='',
                routing_key=queue,
                body=json.dumps(message, default=str),  # default=str handles datetime
                properties=pika.BasicProperties(
                    delivery_mode=2,  # Persistent message
                    content_type='application/json',
                    timestamp=int(datetime.now().timestamp())
                )
            )
            logger.debug(f"Published message to queue '{queue}'")
            return True
        
        except Exception as e:
            logger.error(f"Failed to publish to {queue}: {e}")
            # Try to reconnect
            try:
                self._connect()
            except:
                pass
            return False
    
    def publish_metric(self, system_id: int, metrics: Dict[str, Any]):
        """
        Publish metrics to queue
        
        Args:
            system_id: System ID
            metrics: Metrics data dict
        """
        message = {
            'type': 'metric',
            'system_id': system_id,
            'timestamp': metrics.get('timestamp', datetime.now().isoformat()),
            'data': metrics
        }
        
        self._publish('metrics', message)
    
    def publish_discovery(self, discovered_systems: list):
        """
        Publish discovered systems to queue
        
        Args:
            discovered_systems: List of discovered system dicts
        """
        message = {
            'type': 'discovery',
            'systems': discovered_systems,
            'timestamp': datetime.now().isoformat(),
            'count': len(discovered_systems)
        }
        
        self._publish('discovery', message)
    
    def publish_alert(self, alert_data: Dict[str, Any]):
        """
        Publish alert to queue
        
        Args:
            alert_data: Alert information
        """
        message = {
            'type': 'alert',
            'timestamp': datetime.now().isoformat(),
            'data': alert_data
        }
        
        self._publish('alerts', message)
    
    def get_queue_stats(self, queue_name: str) -> Optional[Dict]:
        """
        Get statistics for a queue
        
        Args:
            queue_name: Name of queue
        
        Returns:
            Dict with message counts or None if unavailable
        """
        if not self.is_connected():
            return None
        
        try:
            method = self.channel.queue_declare(queue=queue_name, passive=True)
            return {
                'queue': queue_name,
                'messages': method.method.message_count,
                'consumers': method.method.consumer_count
            }
        except Exception as e:
            logger.error(f"Failed to get stats for {queue_name}: {e}")
            return None
    
    def close(self):
        """Close connection"""
        if self.connection and not self.connection.is_closed:
            try:
                self.connection.close()
                logger.info("Closed RabbitMQ connection")
            except:
                pass


class MessageConsumer:
    """
    Message queue consumer/worker
    Processes messages from RabbitMQ and writes to database
    """
    
    def __init__(self, queue_name: str, callback: Callable, prefetch_count: int = 10):
        """
        Initialize consumer
        
        Args:
            queue_name: Queue to consume from
            callback: Function to process messages (takes message dict, returns success bool)
            prefetch_count: Number of messages to prefetch (parallel processing)
        """
        self.queue_name = queue_name
        self.callback = callback
        self.prefetch_count = prefetch_count
        
        # Connect to RabbitMQ
        host = os.getenv('RABBITMQ_HOST', 'localhost')
        port = int(os.getenv('RABBITMQ_PORT', 5672))
        user = os.getenv('RABBITMQ_USER', 'guest')
        password = os.getenv('RABBITMQ_PASSWORD', 'guest')
        
        connection_params = pika.ConnectionParameters(
            host=host,
            port=port,
            credentials=pika.PlainCredentials(user, password),
            heartbeat=600,
            blocked_connection_timeout=300
        )
        
        self.connection = pika.BlockingConnection(connection_params)
        self.channel = self.connection.channel()
        
        # Ensure queue exists
        self.channel.queue_declare(queue=queue_name, durable=True)
        
        # Set prefetch (process N messages at a time)
        self.channel.basic_qos(prefetch_count=prefetch_count)
        
        logger.info(f"Consumer initialized for queue '{queue_name}' (prefetch: {prefetch_count})")
    
    def _process_message(self, ch, method, properties, body):
        """
        Internal message processing handler
        
        Args:
            ch: Channel
            method: Delivery method
            properties: Message properties
            body: Message body (JSON)
        """
        try:
            # Parse JSON message
            message = json.loads(body)
            logger.debug(f"Processing message from {self.queue_name}: {message.get('type', 'unknown')}")
            
            # Call user callback
            success = self.callback(message)
            
            if success:
                # Acknowledge message (remove from queue)
                ch.basic_ack(delivery_tag=method.delivery_tag)
                logger.debug(f"Message processed successfully")
            else:
                # Reject and requeue for retry
                logger.warning(f"Message processing failed, requeueing...")
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
        
        except json.JSONDecodeError as e:
            logger.error(f"Invalid JSON in message: {e}")
            # Send to dead letter queue (don't requeue)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)
        
        except Exception as e:
            logger.error(f"Error processing message: {e}", exc_info=True)
            # Requeue for retry
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
    
    def start_consuming(self):
        """
        Start consuming messages (blocking)
        
        This will run forever until interrupted
        """
        logger.info(f"Starting consumer for queue '{self.queue_name}'...")
        
        self.channel.basic_consume(
            queue=self.queue_name,
            on_message_callback=self._process_message,
            auto_ack=False  # Manual acknowledgment for reliability
        )
        
        try:
            logger.info("Consumer ready, waiting for messages...")
            self.channel.start_consuming()
        
        except KeyboardInterrupt:
            logger.info("Consumer interrupted by user")
            self.stop_consuming()
        
        except Exception as e:
            logger.error(f"Consumer error: {e}", exc_info=True)
            self.stop_consuming()
    
    def stop_consuming(self):
        """Stop consuming messages"""
        try:
            logger.info(f"Stopping consumer for '{self.queue_name}'...")
            self.channel.stop_consuming()
            self.connection.close()
            logger.info("Consumer stopped")
        except Exception as e:
            logger.error(f"Error stopping consumer: {e}")


# Global message queue instance (singleton)
_message_queue: Optional[MessageQueue] = None


def get_message_queue() -> MessageQueue:
    """Get global message queue instance (singleton)"""
    global _message_queue
    if _message_queue is None:
        _message_queue = MessageQueue()
    return _message_queue


def check_rabbitmq_available() -> bool:
    """
    Check if RabbitMQ is available
    
    Returns:
        True if RabbitMQ is accessible, False otherwise
    """
    try:
        mq = MessageQueue()
        is_available = mq.is_connected()
        mq.close()
        return is_available
    except Exception as e:
        logger.debug(f"RabbitMQ not available: {e}")
        return False
