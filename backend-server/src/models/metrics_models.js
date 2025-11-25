import sql from './db.js'

class MetricsModel {
    constructor() {
        this.sql = sql
    }

    // Basic validation
    validateRequired(value, fieldName) {
        if (!value || value === '') throw new Error(`${fieldName} required`)
        return value
    }

    validateID(id) {
        if (!id || id <= 0) throw new Error('Invalid ID')
        return id
    }

    validatePercent(value, fieldName) {
        const num = Number(value)
        if (isNaN(num) || num < 0 || num > 100) {
            throw new Error(`${fieldName} must be between 0 and 100`)
        }
        return num
    }

    // Safe query wrapper
    async query(sqlQuery, errorMsg = 'Database operation failed') {
        try {
            return await sqlQuery
        } catch (error) {
            console.error(errorMsg, error.message)
            throw new Error(errorMsg)
        }
    }

    // RAW METRICS OPERATIONS -----------------------------------------------------------------

    async addMetrics(system_id, metrics) {
        this.validateID(system_id)

        const {
            cpu_percent, ram_percent, disk_percent,
            network_sent_mbps, network_recv_mbps,
            gpu_percent, gpu_memory_used_gb, gpu_temperature,
            uptime_seconds, logged_in_users,
            collection_method, collection_duration_ms
        } = metrics

        // Validate percentages
        if (cpu_percent !== undefined) this.validatePercent(cpu_percent, 'cpu_percent')
        if (ram_percent !== undefined) this.validatePercent(ram_percent, 'ram_percent')
        if (disk_percent !== undefined) this.validatePercent(disk_percent, 'disk_percent')
        if (gpu_percent !== undefined) this.validatePercent(gpu_percent, 'gpu_percent')

        return await this.query(
            this.sql`
                INSERT INTO metrics (
                    system_id, cpu_percent, ram_percent, disk_percent,
                    network_sent_mbps, network_recv_mbps, gpu_percent,
                    gpu_memory_used_gb, gpu_temperature, uptime_seconds,
                    logged_in_users, collection_method, collection_duration_ms
                ) VALUES (
                    ${system_id}, ${cpu_percent}, ${ram_percent}, ${disk_percent},
                    ${network_sent_mbps}, ${network_recv_mbps}, ${gpu_percent},
                    ${gpu_memory_used_gb}, ${gpu_temperature}, ${uptime_seconds},
                    ${logged_in_users}, ${collection_method}, ${collection_duration_ms}
                ) RETURNING *
            `,
            'Failed to add metrics'
        )
    }

    async getMetricsBySystem(systemID, limit = 100, hours = 24) {
        this.validateID(systemID)
        return await this.query(
            this.sql`
                SELECT * FROM metrics
                WHERE system_id = ${systemID}
                AND timestamp >= NOW() - INTERVAL '${hours} hours'
                ORDER BY timestamp DESC
                LIMIT ${limit}
            `,
            'Failed to get metrics'
        )
    }

    async getLatestMetrics(systemID) {
        this.validateID(systemID)
        const result = await this.query(
            this.sql`
                SELECT * FROM metrics
                WHERE system_id = ${systemID}
                ORDER BY timestamp DESC
                LIMIT 1
            `,
            'Failed to get latest metrics'
        )
        return result[0] || null
    }

    // HOURLY PERFORMANCE STATS VIEW -----------------------------------------------------------------
    // Uses the hourly_performance_stats continuous aggregate view

    async getHourlyStats(systemID, hours = 24) {
        this.validateID(systemID)
        return await this.query(
            this.sql`
                SELECT
                    hour_bucket as timestamp,
                    avg_cpu_percent, max_cpu_percent, min_cpu_percent, p95_cpu_percent,
                    avg_ram_percent, max_ram_percent, p95_ram_percent,
                    avg_gpu_percent, max_gpu_percent,
                    avg_disk_percent, max_disk_percent,
                    metric_count
                FROM hourly_performance_stats
                WHERE system_id = ${systemID}
                AND hour_bucket >= NOW() - INTERVAL '${hours} hours'
                ORDER BY hour_bucket DESC
            `,
            'Failed to get hourly stats'
        )
    }

    async getHourlyStatsForMultipleSystems(systemIDs, hours = 24) {
        if (!Array.isArray(systemIDs) || systemIDs.length === 0) {
            throw new Error('systemIDs must be a non-empty array')
        }
        return await this.query(
            this.sql`
                SELECT
                    system_id,
                    hour_bucket as timestamp,
                    avg_cpu_percent, max_cpu_percent, p95_cpu_percent,
                    avg_ram_percent, max_ram_percent, p95_ram_percent,
                    avg_gpu_percent, max_gpu_percent,
                    metric_count
                FROM hourly_performance_stats
                WHERE system_id = ANY(${systemIDs})
                AND hour_bucket >= NOW() - INTERVAL '${hours} hours'
                ORDER BY system_id, hour_bucket DESC
            `,
            'Failed to get hourly stats for multiple systems'
        )
    }

    // DAILY PERFORMANCE STATS VIEW -----------------------------------------------------------------
    // Uses the daily_performance_stats continuous aggregate view

    async getDailyStats(systemID, days = 30) {
        this.validateID(systemID)
        return await this.query(
            this.sql`
                SELECT
                    day_bucket as date,
                    avg_cpu_percent, max_cpu_percent, p95_cpu_percent, cpu_above_80_minutes,
                    avg_ram_percent, max_ram_percent, p95_ram_percent, ram_above_80_minutes,
                    avg_gpu_percent, max_gpu_percent,
                    avg_disk_percent, max_disk_percent,
                    metric_count
                FROM daily_performance_stats
                WHERE system_id = ${systemID}
                AND day_bucket >= NOW() - INTERVAL '${days} days'
                ORDER BY day_bucket DESC
            `,
            'Failed to get daily stats'
        )
    }

    async getDailyStatsForMultipleSystems(systemIDs, days = 30) {
        if (!Array.isArray(systemIDs) || systemIDs.length === 0) {
            throw new Error('systemIDs must be a non-empty array')
        }
        return await this.query(
            this.sql`
                SELECT
                    system_id,
                    day_bucket as date,
                    avg_cpu_percent, max_cpu_percent, p95_cpu_percent, cpu_above_80_minutes,
                    avg_ram_percent, max_ram_percent, p95_ram_percent, ram_above_80_minutes,
                    avg_gpu_percent, max_gpu_percent,
                    metric_count
                FROM daily_performance_stats
                WHERE system_id = ANY(${systemIDs})
                AND day_bucket >= NOW() - INTERVAL '${days} days'
                ORDER BY system_id, day_bucket DESC
            `,
            'Failed to get daily stats for multiple systems'
        )
    }

    // PERFORMANCE ANALYTICS -----------------------------------------------------------------

    async getSystemPerformanceSummary(systemID, days = 7) {
        this.validateID(systemID)

        const [latest, hourly, daily] = await Promise.all([
            this.getLatestMetrics(systemID),
            this.getHourlyStats(systemID, 24), // Last 24 hours
            this.getDailyStats(systemID, days)
        ])

        return {
            system_id: systemID,
            latest_metrics: latest,
            hourly_stats: hourly,
            daily_stats: daily,
            summary: {
                avg_cpu_24h: hourly.length > 0 ? hourly.reduce((sum, h) => sum + h.avg_cpu_percent, 0) / hourly.length : 0,
                avg_ram_24h: hourly.length > 0 ? hourly.reduce((sum, h) => sum + h.avg_ram_percent, 0) / hourly.length : 0,
                total_samples_24h: hourly.reduce((sum, h) => sum + h.metric_count, 0),
                days_analyzed: days
            }
        }
    }

    async getDepartmentPerformanceSummary(systemIDs) {
        if (!Array.isArray(systemIDs) || systemIDs.length === 0) {
            throw new Error('systemIDs must be a non-empty array')
        }

        const [hourlyStats, dailyStats] = await Promise.all([
            this.getHourlyStatsForMultipleSystems(systemIDs, 24),
            this.getDailyStatsForMultipleSystems(systemIDs, 7)
        ])

        // Aggregate by system
        const systemSummaries = {}
        systemIDs.forEach(systemID => {
            const systemHourly = hourlyStats.filter(h => h.system_id === systemID)
            const systemDaily = dailyStats.filter(d => d.system_id === systemID)

            systemSummaries[systemID] = {
                system_id: systemID,
                hourly_avg_cpu: systemHourly.length > 0 ?
                    systemHourly.reduce((sum, h) => sum + h.avg_cpu_percent, 0) / systemHourly.length : 0,
                hourly_avg_ram: systemHourly.length > 0 ?
                    systemHourly.reduce((sum, h) => sum + h.avg_ram_percent, 0) / systemHourly.length : 0,
                daily_high_cpu_days: systemDaily.filter(d => d.cpu_above_80_minutes > 60).length,
                total_samples_24h: systemHourly.reduce((sum, h) => sum + h.metric_count, 0)
            }
        })

        return {
            department_summary: {
                total_systems: systemIDs.length,
                avg_cpu_across_systems: Object.values(systemSummaries)
                    .reduce((sum, s) => sum + s.hourly_avg_cpu, 0) / systemIDs.length,
                systems_with_high_cpu: Object.values(systemSummaries)
                    .filter(s => s.hourly_avg_cpu > 80).length
            },
            system_details: systemSummaries
        }
    }

    // UTILITY METHODS -----------------------------------------------------------------

    async getMetricsCount(systemID, hours = 24) {
        this.validateID(systemID)
        const result = await this.query(
            this.sql`
                SELECT COUNT(*) as count
                FROM metrics
                WHERE system_id = ${systemID}
                AND timestamp >= NOW() - INTERVAL '${hours} hours'
            `,
            'Failed to get metrics count'
        )
        return result[0]?.count || 0
    }

    async cleanupOldMetrics(days = 90) {
        // Note: This is handled by TimescaleDB retention policy,
        // but this method allows manual cleanup if needed
        return await this.query(
            this.sql`DELETE FROM metrics WHERE timestamp < NOW() - INTERVAL '${days} days'`,
            'Failed to cleanup old metrics'
        )
    }
}

export default MetricsModel