import json
import pika
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime

RABBITMQ_HOST = "localhost"
RABBITMQ_USER = "guest"
RABBITMQ_PASS = "guest"
RABBITMQ_VHOST = "/opti-labs"
QUEUE_NAME = "metrics_queue"

PG_CONN_STR = "dbname=optilab_mvp user=aayush host=localhost"

pg_conn = psycopg2.connect(PG_CONN_STR)
pg_conn.autocommit = False
pg_cursor = pg_conn.cursor()

credentials = pika.PlainCredentials(RABBITMQ_USER, RABBITMQ_PASS)
connection = pika.BlockingConnection(
    pika.ConnectionParameters(host=RABBITMQ_HOST, virtual_host=RABBITMQ_VHOST, credentials=credentials)
)
channel = connection.channel()
channel.queue_declare(queue=QUEUE_NAME, durable=True)

buffer = []
BUFFER_SIZE = 1

def insert_batch(batch):
    query = """
        INSERT INTO metrics (system_id, timestamp, cpu_percent, cpu_temperature, ram_percent, disk_percent, disk_read_mbps, disk_write_mbps, network_sent_mbps, network_recv_mbps, gpu_percent, gpu_memory_used_gb, gpu_temperature, uptime_seconds, logged_in_users, timestamp)
        VALUES %s
    """
    execute_values(pg_cursor, query, batch)
    pg_conn.commit()


def call_back(ch, method, properties, body):
    try:
        data = json.loads(body)
        timestamp = datetime.fromisoformat(data['timestamp'])
        buffer.append((
            data['system_id'],
            timestamp,
            data['cpu_percent'],
            data['cpu_temperature'],
            data['ram_percent'],
            data['disk_percent'],
            data['disk_read_mbps'],
            data['disk_write_mbps'],
            data['network_sent_mbps'],
            data['network_recv_mbps'],
            data['gpu_percent'],
            data['gpu_memory_used_gb'],
            data['gpu_temperature'],
            data['uptime_seconds'],
            data['logged_in_users'],
        ))

        if len(buffer) >= BUFFER_SIZE:
            insert_batch(buffer[:])
            buffer.clear()

        ch.basic_ack(delivery_tag=method.delivery_tag)

    except Exception as e:
        print(f"Error processing message: {e}")
        pg_conn.rollback()
        # requeue message for retry
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)

print(" [*] Waiting for messages. To exit press CTRL+C")
channel.basic_qos(prefetch_count=10)
channel.basic_consume(queue=QUEUE_NAME, on_message_callback=call_back, auto_ack=False)
channel.start_consuming()