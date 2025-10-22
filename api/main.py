"""
FastAPI Server for Lab Resource Monitoring System
Data ingestion endpoint for metrics collection agents
"""

from fastapi import FastAPI, HTTPException, Depends, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from typing import Optional, List, Dict, Any
from datetime import datetime
import logging
import asyncpg
from contextlib import asynccontextmanager
import os
from dotenv import load_dotenv

load_dotenv()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Database connection pool
db_pool = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifespan - startup and shutdown"""
    global db_pool
    
    # Startup
    logger.info("Starting up API server...")
    db_pool = await get_db_pool()
    logger.info("Database connection pool created")
    
    yield
    
    # Shutdown
    logger.info("Shutting down API server...")
    if db_pool:
        await db_pool.close()
    logger.info("Database connection pool closed")


# FastAPI app
app = FastAPI(
    title="Lab Resource Monitoring API",
    description="Data ingestion and query API for system resource monitoring",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure appropriately for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ============================================================================
# Database Connection
# ============================================================================

async def get_db_pool():
    """Create database connection pool"""
    return await asyncpg.create_pool(
        host=os.getenv('DB_HOST', 'localhost'),
        port=int(os.getenv('DB_PORT', 5432)),
        database=os.getenv('DB_NAME', 'lab_resource_monitor'),
        user=os.getenv('DB_USER', 'postgres'),
        password=os.getenv('DB_PASSWORD', 'postgres'),
        min_size=5,
        max_size=20
    )


async def get_db():
    """Get database connection from pool"""
    async with db_pool.acquire() as connection:
        yield connection


# ============================================================================
# Pydantic Models
# ============================================================================

class SystemRegistration(BaseModel):
    """System registration/update model"""
    system_id: str
    hostname: str
    ip_address: Optional[str] = None
    location: Optional[str] = None
    department: Optional[str] = None
    
    cpu_model: Optional[str] = None
    cpu_cores: Optional[int] = None
    cpu_threads: Optional[int] = None
    cpu_base_freq: Optional[float] = None
    
    ram_total_gb: Optional[float] = None
    ram_type: Optional[str] = None
    
    gpu_model: Optional[str] = None
    gpu_memory_gb: Optional[float] = None
    gpu_count: Optional[int] = 0
    
    disk_total_gb: Optional[float] = None
    disk_type: Optional[str] = None
    
    os_name: Optional[str] = None
    os_version: Optional[str] = None


class MetricsData(BaseModel):
    """Metrics data model"""
    system_id: str
    timestamp: Optional[str] = None
    
    # CPU Metrics
    cpu_percent: Optional[float] = None
    cpu_per_core: Optional[List[float]] = None
    cpu_freq_current: Optional[float] = None
    cpu_temp: Optional[float] = None
    
    # Memory Metrics
    ram_used_gb: Optional[float] = None
    ram_available_gb: Optional[float] = None
    ram_percent: Optional[float] = None
    swap_used_gb: Optional[float] = None
    swap_percent: Optional[float] = None
    
    # GPU Metrics
    gpu_utilization: Optional[float] = None
    gpu_memory_used_gb: Optional[float] = None
    gpu_memory_percent: Optional[float] = None
    gpu_temp: Optional[float] = None
    gpu_power_draw: Optional[float] = None
    
    # Disk Metrics
    disk_read_mb_s: Optional[float] = None
    disk_write_mb_s: Optional[float] = None
    disk_read_ops: Optional[int] = None
    disk_write_ops: Optional[int] = None
    disk_io_wait_percent: Optional[float] = None
    disk_used_gb: Optional[float] = None
    disk_percent: Optional[float] = None
    
    # Network Metrics
    net_sent_mb_s: Optional[float] = None
    net_recv_mb_s: Optional[float] = None
    net_packets_sent: Optional[int] = None
    net_packets_recv: Optional[int] = None
    
    # Process Metrics
    process_count: Optional[int] = None
    thread_count: Optional[int] = None
    top_processes: Optional[List[Dict[str, Any]]] = None
    
    # System Load
    load_avg_1min: Optional[float] = None
    load_avg_5min: Optional[float] = None
    load_avg_15min: Optional[float] = None
    
    collection_duration_ms: Optional[int] = None


class SystemStatus(BaseModel):
    """System status response model"""
    system_id: str
    hostname: str
    status: str
    last_seen: Optional[str]
    current_cpu: Optional[float]
    current_ram: Optional[float]
    utilization_status: Optional[str]


# ============================================================================
# API Endpoints
# ============================================================================

@app.get("/")
async def root():
    """Root endpoint - API info"""
    return {
        "name": "Lab Resource Monitoring API",
        "version": "1.0.0",
        "status": "online",
        "endpoints": {
            "systems": "/api/systems",
            "metrics": "/api/metrics",
            "status": "/api/systems/status",
            "docs": "/docs"
        }
    }


@app.post("/api/systems/register", status_code=status.HTTP_201_CREATED)
async def register_system(system: SystemRegistration, conn=Depends(get_db)):
    """Register or update a system"""
    try:
        # Check if system exists
        existing = await conn.fetchrow(
            "SELECT system_id FROM systems WHERE system_id = $1",
            system.system_id
        )
        
        if existing:
            # Update existing system
            await conn.execute("""
                UPDATE systems SET
                    hostname = $2, ip_address = $3, location = $4, department = $5,
                    cpu_model = $6, cpu_cores = $7, cpu_threads = $8, cpu_base_freq = $9,
                    ram_total_gb = $10, ram_type = $11,
                    gpu_model = $12, gpu_memory_gb = $13, gpu_count = $14,
                    disk_total_gb = $15, disk_type = $16,
                    os_name = $17, os_version = $18,
                    updated_at = CURRENT_TIMESTAMP
                WHERE system_id = $1
            """,
                system.system_id, system.hostname, system.ip_address, system.location,
                system.department, system.cpu_model, system.cpu_cores, system.cpu_threads,
                system.cpu_base_freq, system.ram_total_gb, system.ram_type,
                system.gpu_model, system.gpu_memory_gb, system.gpu_count,
                system.disk_total_gb, system.disk_type, system.os_name, system.os_version
            )
            logger.info(f"Updated system: {system.hostname} ({system.system_id})")
            return {"message": "System updated", "system_id": system.system_id}
        
        else:
            # Insert new system
            await conn.execute("""
                INSERT INTO systems (
                    system_id, hostname, ip_address, location, department,
                    cpu_model, cpu_cores, cpu_threads, cpu_base_freq,
                    ram_total_gb, ram_type,
                    gpu_model, gpu_memory_gb, gpu_count,
                    disk_total_gb, disk_type,
                    os_name, os_version, status
                ) VALUES (
                    $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, 'active'
                )
            """,
                system.system_id, system.hostname, system.ip_address, system.location,
                system.department, system.cpu_model, system.cpu_cores, system.cpu_threads,
                system.cpu_base_freq, system.ram_total_gb, system.ram_type,
                system.gpu_model, system.gpu_memory_gb, system.gpu_count,
                system.disk_total_gb, system.disk_type, system.os_name, system.os_version
            )
            logger.info(f"Registered new system: {system.hostname} ({system.system_id})")
            return {"message": "System registered", "system_id": system.system_id}
    
    except Exception as e:
        logger.error(f"Error registering system: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/metrics", status_code=status.HTTP_201_CREATED)
async def ingest_metrics(metrics: MetricsData, conn=Depends(get_db)):
    """Ingest system metrics"""
    try:
        # Verify system exists
        system = await conn.fetchrow(
            "SELECT system_id FROM systems WHERE system_id = $1",
            metrics.system_id
        )
        
        if not system:
            raise HTTPException(
                status_code=404,
                detail=f"System {metrics.system_id} not found. Please register first."
            )
        
        # Parse timestamp
        timestamp = metrics.timestamp or datetime.utcnow().isoformat()
        
        # Convert cpu_per_core list to JSON
        import json
        cpu_per_core_json = json.dumps(metrics.cpu_per_core) if metrics.cpu_per_core else None
        
        # Insert metrics
        await conn.execute("""
            INSERT INTO usage_metrics (
                system_id, timestamp,
                cpu_percent, cpu_per_core, cpu_freq_current, cpu_temp,
                ram_used_gb, ram_available_gb, ram_percent, swap_used_gb, swap_percent,
                gpu_utilization, gpu_memory_used_gb, gpu_memory_percent, gpu_temp, gpu_power_draw,
                disk_read_mb_s, disk_write_mb_s, disk_read_ops, disk_write_ops,
                disk_io_wait_percent, disk_used_gb, disk_percent,
                net_sent_mb_s, net_recv_mb_s, net_packets_sent, net_packets_recv,
                process_count, thread_count,
                load_avg_1min, load_avg_5min, load_avg_15min,
                collection_duration_ms
            ) VALUES (
                $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16,
                $17, $18, $19, $20, $21, $22, $23, $24, $25, $26, $27, $28, $29, $30, $31, $32, $33
            )
        """,
            metrics.system_id, timestamp,
            metrics.cpu_percent, cpu_per_core_json, metrics.cpu_freq_current, metrics.cpu_temp,
            metrics.ram_used_gb, metrics.ram_available_gb, metrics.ram_percent,
            metrics.swap_used_gb, metrics.swap_percent,
            metrics.gpu_utilization, metrics.gpu_memory_used_gb, metrics.gpu_memory_percent,
            metrics.gpu_temp, metrics.gpu_power_draw,
            metrics.disk_read_mb_s, metrics.disk_write_mb_s, metrics.disk_read_ops,
            metrics.disk_write_ops, metrics.disk_io_wait_percent, metrics.disk_used_gb,
            metrics.disk_percent,
            metrics.net_sent_mb_s, metrics.net_recv_mb_s, metrics.net_packets_sent,
            metrics.net_packets_recv,
            metrics.process_count, metrics.thread_count,
            metrics.load_avg_1min, metrics.load_avg_5min, metrics.load_avg_15min,
            metrics.collection_duration_ms
        )
        
        logger.info(f"Metrics ingested for system {metrics.system_id}")
        return {"message": "Metrics ingested successfully", "timestamp": timestamp}
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error ingesting metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/systems", response_model=List[Dict[str, Any]])
async def get_systems(conn=Depends(get_db)):
    """Get all systems"""
    try:
        systems = await conn.fetch("""
            SELECT 
                system_id, hostname, location, department, status,
                cpu_cores, ram_total_gb, gpu_model, last_seen, created_at
            FROM systems
            ORDER BY hostname
        """)
        
        return [dict(row) for row in systems]
    
    except Exception as e:
        logger.error(f"Error fetching systems: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/systems/status", response_model=List[SystemStatus])
async def get_systems_status(conn=Depends(get_db)):
    """Get current status of all systems"""
    try:
        status_data = await conn.fetch("""
            SELECT * FROM current_system_status
            ORDER BY utilization_status DESC, hostname
        """)
        
        return [SystemStatus(**dict(row)) for row in status_data]
    
    except Exception as e:
        logger.error(f"Error fetching system status: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/systems/{system_id}/metrics")
async def get_system_metrics(
    system_id: str,
    hours: int = 24,
    limit: int = 100,
    conn=Depends(get_db)
):
    """Get recent metrics for a specific system"""
    try:
        metrics = await conn.fetch("""
            SELECT 
                timestamp, cpu_percent, ram_percent, gpu_utilization,
                disk_percent, disk_io_wait_percent,
                load_avg_1min, load_avg_5min, load_avg_15min
            FROM usage_metrics
            WHERE system_id = $1
                AND timestamp >= CURRENT_TIMESTAMP - ($2 || ' hours')::INTERVAL
            ORDER BY timestamp DESC
            LIMIT $3
        """, system_id, hours, limit)
        
        if not metrics:
            raise HTTPException(status_code=404, detail="No metrics found")
        
        return [dict(row) for row in metrics]
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching system metrics: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/analytics/top-consumers/{resource_type}")
async def get_top_consumers(
    resource_type: str,
    limit: int = 10,
    hours: int = 24,
    conn=Depends(get_db)
):
    """Get top resource consumers"""
    try:
        if resource_type not in ['cpu', 'ram', 'gpu', 'disk_io']:
            raise HTTPException(status_code=400, detail="Invalid resource type")
        
        result = await conn.fetch("""
            SELECT * FROM get_top_resource_consumers($1, $2, $3)
        """, resource_type, limit, hours)
        
        return [dict(row) for row in result]
    
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error fetching top consumers: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/analytics/underutilized")
async def get_underutilized_systems(days: int = 7, conn=Depends(get_db)):
    """Get underutilized systems"""
    try:
        systems = await conn.fetch("""
            SELECT 
                s.hostname, s.location, s.cpu_cores, s.ram_total_gb,
                ps.avg_cpu_percent, ps.avg_ram_percent,
                ps.utilization_score, ps.period_start
            FROM performance_summaries ps
            JOIN systems s ON ps.system_id = s.system_id
            WHERE ps.is_underutilized = TRUE
                AND ps.period_type = 'daily'
                AND ps.period_start >= CURRENT_DATE - $1
            ORDER BY ps.utilization_score ASC
        """, days)
        
        return [dict(row) for row in systems]
    
    except Exception as e:
        logger.error(f"Error fetching underutilized systems: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/alerts/active")
async def get_active_alerts(conn=Depends(get_db)):
    """Get active (unresolved) alerts"""
    try:
        alerts = await conn.fetch("""
            SELECT 
                al.alert_id, al.triggered_at, al.severity, al.message,
                s.hostname, s.location,
                al.metric_name, al.actual_value, al.threshold_value
            FROM alert_logs al
            JOIN systems s ON al.system_id = s.system_id
            WHERE al.resolved_at IS NULL
            ORDER BY al.severity DESC, al.triggered_at DESC
        """)
        
        return [dict(row) for row in alerts]
    
    except Exception as e:
        logger.error(f"Error fetching active alerts: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
async def health_check(conn=Depends(get_db)):
    """Health check endpoint"""
    try:
        # Test database connection
        await conn.fetchval("SELECT 1")
        return {
            "status": "healthy",
            "database": "connected",
            "timestamp": datetime.utcnow().isoformat()
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }


# ============================================================================
# Run Server
# ============================================================================

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
