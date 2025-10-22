"""
Generate Sample Data for Testing
Populates database with realistic test data for demonstration
"""

import psycopg2
from psycopg2.extras import execute_batch
import random
from datetime import datetime, timedelta
import uuid

# Database configuration
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'database': 'lab_resource_monitor',
    'user': 'postgres',
    'password': 'postgres'  # Change this!
}

def generate_sample_systems(num_systems=10):
    """Generate sample system records"""
    systems = []
    locations = ['Lab A', 'Lab B', 'Lab C', 'Server Room', 'Research Lab']
    cpu_models = ['Intel Core i7-9700', 'Intel Core i5-8400', 'AMD Ryzen 5 3600', 'Intel Xeon E-2288G']
    gpu_models = ['NVIDIA RTX 3060', 'NVIDIA GTX 1660', None, None]  # Some have no GPU
    disk_types = ['SSD', 'NVMe', 'HDD']
    
    for i in range(num_systems):
        system = {
            'system_id': str(uuid.uuid4()),
            'hostname': f'lab-pc-{i+1:02d}',
            'ip_address': f'192.168.1.{i+10}',
            'location': random.choice(locations),
            'department': 'Computer Science',
            'cpu_model': random.choice(cpu_models),
            'cpu_cores': random.choice([4, 6, 8]),
            'cpu_threads': random.choice([8, 12, 16]),
            'cpu_base_freq': round(random.uniform(2.5, 4.0), 2),
            'ram_total_gb': random.choice([8, 16, 32]),
            'ram_type': 'DDR4',
            'gpu_model': random.choice(gpu_models),
            'gpu_memory_gb': random.choice([4, 6, 8]) if random.choice(gpu_models) else None,
            'gpu_count': 1 if random.choice(gpu_models) else 0,
            'disk_total_gb': random.choice([256, 512, 1024]),
            'disk_type': random.choice(disk_types),
            'os_name': 'Windows 10',
            'os_version': '10.0.19044'
        }
        systems.append(system)
    
    return systems

def generate_sample_metrics(system_id, start_date, num_days=7):
    """Generate sample metrics for a system over time"""
    metrics = []
    current_time = start_date
    interval_minutes = 5
    
    # Simulate daily patterns
    for day in range(num_days):
        for hour in range(24):
            # Determine usage based on time of day
            # Peak hours: 9 AM - 5 PM
            if 9 <= hour <= 17:
                cpu_base = random.uniform(40, 80)
                ram_base = random.uniform(50, 75)
            # Off hours: Low usage
            else:
                cpu_base = random.uniform(5, 25)
                ram_base = random.uniform(20, 40)
            
            # Add some variance
            for _ in range(60 // interval_minutes):  # 12 samples per hour
                metric = {
                    'system_id': system_id,
                    'timestamp': current_time,
                    'cpu_percent': round(cpu_base + random.uniform(-10, 10), 2),
                    'cpu_freq_current': round(random.uniform(2000, 3500), 2),
                    'ram_percent': round(ram_base + random.uniform(-5, 10), 2),
                    'ram_used_gb': None,  # Will be calculated
                    'ram_available_gb': None,
                    'swap_percent': round(random.uniform(0, 5), 2) if ram_base > 70 else 0,
                    'gpu_utilization': round(random.uniform(0, 30), 2) if random.random() > 0.5 else None,
                    'disk_percent': round(random.uniform(40, 80), 2),
                    'disk_read_mb_s': round(random.uniform(10, 100), 2),
                    'disk_write_mb_s': round(random.uniform(5, 50), 2),
                    'disk_io_wait_percent': round(random.uniform(0, 20), 2),
                    'net_sent_mb_s': round(random.uniform(0.1, 5), 2),
                    'net_recv_mb_s': round(random.uniform(0.1, 10), 2),
                    'load_avg_1min': round(random.uniform(0.5, 4), 2),
                    'process_count': random.randint(80, 200)
                }
                
                metrics.append(metric)
                current_time += timedelta(minutes=interval_minutes)
    
    return metrics

def insert_systems(conn, systems):
    """Insert sample systems into database"""
    cursor = conn.cursor()
    
    query = """
    INSERT INTO systems (
        system_id, hostname, ip_address, location, department,
        cpu_model, cpu_cores, cpu_threads, cpu_base_freq,
        ram_total_gb, ram_type,
        gpu_model, gpu_memory_gb, gpu_count,
        disk_total_gb, disk_type,
        os_name, os_version, status
    ) VALUES (
        %(system_id)s, %(hostname)s, %(ip_address)s, %(location)s, %(department)s,
        %(cpu_model)s, %(cpu_cores)s, %(cpu_threads)s, %(cpu_base_freq)s,
        %(ram_total_gb)s, %(ram_type)s,
        %(gpu_model)s, %(gpu_memory_gb)s, %(gpu_count)s,
        %(disk_total_gb)s, %(disk_type)s,
        %(os_name)s, %(os_version)s, 'active'
    )
    ON CONFLICT (hostname) DO NOTHING
    """
    
    execute_batch(cursor, query, systems)
    conn.commit()
    print(f"✓ Inserted {len(systems)} systems")

def insert_metrics(conn, metrics):
    """Insert sample metrics into database"""
    cursor = conn.cursor()
    
    query = """
    INSERT INTO usage_metrics (
        system_id, timestamp,
        cpu_percent, cpu_freq_current,
        ram_percent, swap_percent,
        gpu_utilization,
        disk_percent, disk_read_mb_s, disk_write_mb_s, disk_io_wait_percent,
        net_sent_mb_s, net_recv_mb_s,
        load_avg_1min, process_count
    ) VALUES (
        %(system_id)s, %(timestamp)s,
        %(cpu_percent)s, %(cpu_freq_current)s,
        %(ram_percent)s, %(swap_percent)s,
        %(gpu_utilization)s,
        %(disk_percent)s, %(disk_read_mb_s)s, %(disk_write_mb_s)s, %(disk_io_wait_percent)s,
        %(net_sent_mb_s)s, %(net_recv_mb_s)s,
        %(load_avg_1min)s, %(process_count)s
    )
    ON CONFLICT (system_id, timestamp) DO NOTHING
    """
    
    # Insert in batches
    batch_size = 1000
    for i in range(0, len(metrics), batch_size):
        batch = metrics[i:i+batch_size]
        execute_batch(cursor, query, batch)
        conn.commit()
        print(f"✓ Inserted batch {i//batch_size + 1} ({len(batch)} metrics)")

def generate_sample_alerts(conn):
    """Generate sample alert rules"""
    cursor = conn.cursor()
    
    # Default alert rules are already created in schema.sql
    print("✓ Alert rules already configured in schema")

def main():
    """Main execution"""
    print("=" * 60)
    print("Generating Sample Data for Lab Resource Monitor")
    print("=" * 60)
    
    # Connect to database
    print("\n1. Connecting to database...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        print("✓ Connected successfully")
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return
    
    # Generate and insert systems
    print("\n2. Generating sample systems...")
    systems = generate_sample_systems(num_systems=10)
    insert_systems(conn, systems)
    
    # Generate and insert metrics
    print("\n3. Generating sample metrics (this may take a minute)...")
    start_date = datetime.now() - timedelta(days=7)
    
    all_metrics = []
    for system in systems:
        metrics = generate_sample_metrics(system['system_id'], start_date, num_days=7)
        all_metrics.extend(metrics)
        print(f"  Generated {len(metrics)} metrics for {system['hostname']}")
    
    print(f"\n4. Inserting {len(all_metrics)} total metrics...")
    insert_metrics(conn, all_metrics)
    
    # Generate summaries
    print("\n5. Generating performance summaries...")
    cursor = conn.cursor()
    for system in systems:
        for days_ago in range(1, 8):
            date = (datetime.now() - timedelta(days=days_ago)).date()
            cursor.execute(
                "CALL generate_daily_summary(%s, %s)",
                (system['system_id'], date)
            )
    conn.commit()
    print("✓ Performance summaries generated")
    
    # Close connection
    conn.close()
    
    print("\n" + "=" * 60)
    print("Sample Data Generation Complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Connect to database: psql -U postgres -d lab_resource_monitor")
    print("2. Query data: SELECT * FROM current_system_status;")
    print("3. Try analytics: See database/sample_queries.sql")
    print("\n" + "=" * 60)

if __name__ == "__main__":
    main()
