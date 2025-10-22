"""
Generate Sample Data for Testing (Agentless Schema)
Populates database with realistic test data for demonstration
Compatible with schema_agentless.sql
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

def generate_sample_systems(num_systems=10, dept_id=1):
    """Generate sample system records with network fields"""
    systems = []
    cpu_models = ['Intel Core i7-9700', 'Intel Core i5-8400', 'AMD Ryzen 5 3600', 'Intel Xeon E-2288G']
    gpu_models = ['NVIDIA RTX 3060', 'NVIDIA GTX 1660', None, None]  # Some have no GPU
    disk_types = ['SSD', 'NVMe', 'HDD']
    os_types = ['Windows', 'Linux']
    collection_methods = ['wmi', 'ssh', 'snmp']
    
    for i in range(num_systems):
        os_type = random.choice(os_types)
        system = {
            'system_id': str(uuid.uuid4()),
            'hostname': f'lab-pc-{i+1:02d}',
            'ip_address': f'10.30.1.{i+10}',  # INET type
            'mac_address': f'00:1A:2B:3C:4D:{i+10:02X}',  # MACADDR type
            'os_type': os_type,
            'dept_id': dept_id,
            'collection_method': 'wmi' if os_type == 'Windows' else 'ssh',
            'location': f'Lab {chr(65 + i % 3)}',  # Lab A, B, C
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
            'os_name': 'Windows 10' if os_type == 'Windows' else 'Ubuntu 22.04',
            'os_version': '10.0.19044' if os_type == 'Windows' else '22.04'
        }
        systems.append(system)
    
    return systems

def generate_sample_metrics(system_id, collection_method, start_date, num_days=7):
    """Generate sample metrics for a system over time (agentless schema)"""
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
                    'collection_method': collection_method,  # NEW: agentless schema field
                    'cpu_percent': round(cpu_base + random.uniform(-10, 10), 2),
                    'cpu_freq_current': round(random.uniform(2000, 3500), 2),
                    'ram_percent': round(ram_base + random.uniform(-5, 10), 2),
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
    """Insert sample systems into database (agentless schema)"""
    cursor = conn.cursor()
    
    query = """
    INSERT INTO systems (
        system_id, hostname, ip_address, mac_address, os_type, dept_id, 
        collection_method, location,
        cpu_model, cpu_cores, cpu_threads, cpu_base_freq,
        ram_total_gb, ram_type,
        gpu_model, gpu_memory_gb, gpu_count,
        disk_total_gb, disk_type,
        os_name, os_version, status
    ) VALUES (
        %(system_id)s, %(hostname)s, %(ip_address)s::INET, %(mac_address)s::MACADDR, 
        %(os_type)s, %(dept_id)s, %(collection_method)s, %(location)s,
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
    """Insert sample metrics into database (agentless schema)"""
    cursor = conn.cursor()
    
    query = """
    INSERT INTO usage_metrics (
        system_id, timestamp, collection_method,
        cpu_percent, cpu_freq_current,
        ram_percent, swap_percent,
        gpu_utilization,
        disk_percent, disk_read_mb_s, disk_write_mb_s, disk_io_wait_percent,
        net_sent_mb_s, net_recv_mb_s,
        load_avg_1min, process_count
    ) VALUES (
        %(system_id)s, %(timestamp)s, %(collection_method)s,
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
    """Main execution (agentless schema compatible)"""
    print("=" * 60)
    print("Generating Sample Data for Lab Resource Monitor (Agentless)")
    print("=" * 60)
    
    # Connect to database
    print("\n1. Connecting to database...")
    try:
        conn = psycopg2.connect(**DB_CONFIG)
        print("✓ Connected successfully")
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return
    
    # Ensure departments exist
    print("\n2. Checking departments...")
    cursor = conn.cursor()
    cursor.execute("SELECT dept_id, dept_name FROM departments LIMIT 1")
    result = cursor.fetchone()
    if not result:
        print("  Creating sample departments...")
        cursor.execute("""
            INSERT INTO departments (dept_name, vlan_id, subnet_cidr, description) VALUES
            ('Information Science', 30, '10.30.0.0/16', 'ISE Department Lab'),
            ('Computer Science', 31, '10.31.0.0/16', 'CSE Department Lab')
        """)
        conn.commit()
        print("✓ Sample departments created")
        dept_id = 1
    else:
        dept_id = result[0]
        print(f"✓ Using existing department: {result[1]} (ID: {dept_id})")
    
    # Generate and insert systems
    print("\n3. Generating sample systems...")
    systems = generate_sample_systems(num_systems=10, dept_id=dept_id)
    insert_systems(conn, systems)
    
    # Generate and insert metrics
    print("\n4. Generating sample metrics (this may take a minute)...")
    start_date = datetime.now() - timedelta(days=7)
    
    all_metrics = []
    for system in systems:
        metrics = generate_sample_metrics(
            system['system_id'], 
            system['collection_method'],
            start_date, 
            num_days=7
        )
        all_metrics.extend(metrics)
        print(f"  Generated {len(metrics)} metrics for {system['hostname']} ({system['collection_method']})")
    
    print(f"\n5. Inserting {len(all_metrics)} total metrics...")
    insert_metrics(conn, all_metrics)
    
    # Generate summaries
    print("\n6. Generating performance summaries...")
    cursor = conn.cursor()
    for system in systems:
        for days_ago in range(1, 8):
            date = (datetime.now() - timedelta(days=days_ago)).date()
            try:
                cursor.execute(
                    "CALL generate_daily_summary(%s, %s)",
                    (system['system_id'], date)
                )
            except Exception as e:
                print(f"  Warning: Could not generate summary for {system['hostname']}: {e}")
    conn.commit()
    print("✓ Performance summaries generated")
    
    # Close connection
    conn.close()
    
    print("\n" + "=" * 60)
    print("Sample Data Generation Complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("1. Connect to database: psql -U postgres -d lab_resource_monitor")
    print("2. Query department stats: SELECT * FROM v_department_stats;")
    print("3. View systems: SELECT hostname, ip_address, mac_address, collection_method FROM systems;")
    print("4. Try network queries: SELECT * FROM get_systems_in_subnet('10.30.1.0/24');")
    print("5. See more queries: database/schema_agentless.sql (20+ examples)")
    print("\n" + "=" * 60)

if __name__ == "__main__":
    main()
