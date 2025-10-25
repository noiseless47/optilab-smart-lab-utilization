#!/usr/bin/env python3
"""
Message Queue Processor - Worker Service
Consumes metrics/discovery messages from RabbitMQ and writes to database

Usage:
    python queue_processor.py --queue metrics
    python queue_processor.py --queue discovery
    
Run multiple workers for parallel processing:
    python queue_processor.py --queue metrics &
    python queue_processor.py --queue metrics &
    python queue_processor.py --queue metrics &
"""

import argparse
import logging
import sys
import signal
from datetime import datetime
from typing import Dict, Any
import psycopg2
from psycopg2.extras import RealDictCursor
import os
from dotenv import load_dotenv

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from message_queue import MessageConsumer
from network_collector import DatabaseConnection

load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class QueueProcessor:
    """
    Process messages from RabbitMQ and write to database
    """
    
    def __init__(self, queue_name: str):
        """
        Initialize processor
        
        Args:
            queue_name: Queue to process ('metrics' or 'discovery')
        """
        self.queue_name = queue_name
        
        # Connect to database
        self.db = DatabaseConnection()
        self.db.connect()
        logger.info(f"Connected to database: {self.db.conn_params['database']}")
        
        # Setup consumer
        self.consumer = MessageConsumer(
            queue_name=queue_name,
            callback=self.process_message,
            prefetch_count=10  # Process 10 messages in parallel
        )
        
        # Statistics
        self.processed_count = 0
        self.error_count = 0
        self.start_time = datetime.now()
    
    def process_message(self, message: Dict[str, Any]) -> bool:
        """
        Process a single message
        
        Args:
            message: Message dict from queue
        
        Returns:
            True if processing succeeded, False otherwise
        """
        try:
            message_type = message.get('type')
            
            if message_type == 'metric':
                return self._process_metric(message)
            
            elif message_type == 'discovery':
                return self._process_discovery(message)
            
            elif message_type == 'alert':
                return self._process_alert(message)
            
            else:
                logger.warning(f"Unknown message type: {message_type}")
                return False
        
        except Exception as e:
            logger.error(f"Error processing message: {e}", exc_info=True)
            self.error_count += 1
            return False
    
    def _process_metric(self, message: Dict[str, Any]) -> bool:
        """
        Process metrics message and insert into usage_metrics table
        
        Args:
            message: Metric message
        
        Returns:
            True if successful
        """
        try:
            system_id = message['system_id']
            data = message['data']
            timestamp = message.get('timestamp', datetime.now().isoformat())
            
            # Insert metrics into database
            self.db.execute("""
                INSERT INTO usage_metrics
                (system_id, timestamp, cpu_percent, ram_total_gb, ram_used_gb, 
                 ram_percent, disk_total_gb, disk_used_gb, disk_percent,
                 collection_method, collection_duration_ms)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                system_id,
                timestamp,
                data.get('cpu_percent'),
                data.get('ram_total_gb'),
                data.get('ram_used_gb'),
                data.get('ram_percent'),
                data.get('disk_total_gb'),
                data.get('disk_used_gb'),
                data.get('disk_percent'),
                data.get('collection_method'),
                data.get('collection_duration_ms')
            ))
            
            # Update last_seen timestamp on system
            self.db.execute("""
                UPDATE systems 
                SET last_seen = %s,
                    status = 'active'
                WHERE system_id = %s
            """, (timestamp, system_id))
            
            self.processed_count += 1
            logger.debug(f"Saved metrics for system {system_id}")
            return True
        
        except Exception as e:
            logger.error(f"Failed to save metric: {e}")
            return False
    
    def _process_discovery(self, message: Dict[str, Any]) -> bool:
        """
        Process discovery message and upsert systems
        
        Args:
            message: Discovery message
        
        Returns:
            True if successful
        """
        try:
            systems = message.get('systems', [])
            count = 0
            
            for system in systems:
                # Upsert system
                self.db.execute("""
                    INSERT INTO systems 
                    (dept_id, hostname, ip_address, mac_address, os_type, os_version, 
                     collection_method, status, last_seen, first_seen)
                    VALUES (%(dept_id)s, %(hostname)s, %(ip_address)s, %(mac_address)s,
                            %(os_type)s, %(os_version)s, %(collection_method)s,
                            'discovered', NOW(), NOW())
                    ON CONFLICT (ip_address) DO UPDATE
                    SET hostname = EXCLUDED.hostname,
                        mac_address = EXCLUDED.mac_address,
                        os_type = EXCLUDED.os_type,
                        os_version = EXCLUDED.os_version,
                        collection_method = EXCLUDED.collection_method,
                        status = 'active',
                        last_seen = NOW()
                """, system)
                count += 1
            
            self.processed_count += count
            logger.info(f"Processed discovery: {count} systems")
            return True
        
        except Exception as e:
            logger.error(f"Failed to process discovery: {e}")
            return False
    
    def _process_alert(self, message: Dict[str, Any]) -> bool:
        """
        Process alert message
        
        Args:
            message: Alert message
        
        Returns:
            True if successful
        """
        try:
            alert_data = message.get('data', {})
            
            # Insert into alert_logs (if table exists)
            # This is optional - implement based on your alert schema
            logger.info(f"Alert received: {alert_data.get('message', 'No message')}")
            
            self.processed_count += 1
            return True
        
        except Exception as e:
            logger.error(f"Failed to process alert: {e}")
            return False
    
    def start(self):
        """Start processing messages"""
        logger.info(f"Starting queue processor for '{self.queue_name}'")
        logger.info("Press Ctrl+C to stop...")
        
        try:
            self.consumer.start_consuming()
        
        except KeyboardInterrupt:
            self.stop()
        
        except Exception as e:
            logger.error(f"Processor error: {e}", exc_info=True)
            self.stop()
    
    def stop(self):
        """Stop processing and cleanup"""
        logger.info("\nStopping queue processor...")
        
        # Print statistics
        duration = (datetime.now() - self.start_time).total_seconds()
        rate = self.processed_count / duration if duration > 0 else 0
        
        logger.info(f"Statistics:")
        logger.info(f"  Processed: {self.processed_count} messages")
        logger.info(f"  Errors: {self.error_count}")
        logger.info(f"  Duration: {duration:.1f} seconds")
        logger.info(f"  Rate: {rate:.1f} messages/second")
        
        # Cleanup
        if hasattr(self, 'consumer'):
            self.consumer.stop_consuming()
        
        if hasattr(self, 'db'):
            self.db.close()
        
        logger.info("Processor stopped")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Message Queue Processor - Worker Service',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Process metrics queue
  python queue_processor.py --queue metrics
  
  # Process discovery queue
  python queue_processor.py --queue discovery
  
  # Run multiple workers for parallel processing
  python queue_processor.py --queue metrics &
  python queue_processor.py --queue metrics &
  python queue_processor.py --queue metrics &
        """
    )
    
    parser.add_argument(
        '--queue',
        type=str,
        required=True,
        choices=['metrics', 'discovery', 'alerts'],
        help='Queue to process'
    )
    
    parser.add_argument(
        '--verbose',
        action='store_true',
        help='Enable verbose debug logging'
    )
    
    args = parser.parse_args()
    
    # Set log level
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    
    # Create and start processor
    processor = QueueProcessor(args.queue)
    
    # Handle Ctrl+C gracefully
    def signal_handler(sig, frame):
        processor.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start processing
    processor.start()


if __name__ == '__main__':
    main()
