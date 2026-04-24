const sql = require('./db.js')

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
            const result = await sqlQuery
            return Array.isArray(result) ? result : [result]
        } catch (error) {
            console.error(errorMsg, error.message)
            console.error('Full error:', error)
            throw new Error(`${errorMsg}: ${error.message}`)
        }
    }

    // RAW METRICS OPERATIONS -----------------------------------------------------------------

    // async addMetrics(system_id, metrics) {
    //     this.validateID(system_id)

    //     const {
    //         cpu_percent, ram_percent, disk_percent,
    //         network_sent_mbps, network_recv_mbps,
    //         gpu_percent, gpu_memory_used_gb, gpu_temperature,
    //         uptime_seconds, logged_in_users,
    //         collection_method, collection_duration_ms
    //     } = metrics

    //     // Validate percentages
    //     if (cpu_percent !== undefined) this.validatePercent(cpu_percent, 'cpu_percent')
    //     if (ram_percent !== undefined) this.validatePercent(ram_percent, 'ram_percent')
    //     if (disk_percent !== undefined) this.validatePercent(disk_percent, 'disk_percent')
    //     if (gpu_percent !== undefined) this.validatePercent(gpu_percent, 'gpu_percent')

    //     return await this.query(
    //         this.sql`
    //             INSERT INTO metrics (
    //                 system_id, cpu_percent, ram_percent, disk_percent,
    //                 network_sent_mbps, network_recv_mbps, gpu_percent,
    //                 gpu_memory_used_gb, gpu_temperature, uptime_seconds,
    //                 logged_in_users, collection_method, collection_duration_ms
    //             ) VALUES (
    //                 ${system_id}, ${cpu_percent}, ${ram_percent}, ${disk_percent},
    //                 ${network_sent_mbps}, ${network_recv_mbps}, ${gpu_percent},
    //                 ${gpu_memory_used_gb}, ${gpu_temperature}, ${uptime_seconds},
    //                 ${logged_in_users}, ${collection_method}, ${collection_duration_ms}
    //             ) RETURNING *
    //         `,
    //         'Failed to add metrics'
    //     )
    // }

    async getMetricsBySystem(systemID, limit = 100, hours = 24) {
        this.validateID(systemID)
        return await this.query(
            this.sql`
                SELECT * FROM metrics
                WHERE system_id = ${systemID}
                AND timestamp >= NOW() - (${hours}::integer || ' hours')::interval
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
                    avg_disk_io_wait,
                    total_disk_read_gb,
                    total_disk_write_gb,
                    avg_uptime_seconds,
                    metric_count
                FROM hourly_performance_stats
                WHERE system_id = ${systemID}
                AND hour_bucket >= NOW() - (${hours}::integer || ' hours')::interval
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
                AND hour_bucket >= NOW() - (${hours}::integer || ' hours')::interval
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
                    avg_ram_percent, max_ram_percent, p95_ram_percent,
                    avg_gpu_percent, max_gpu_percent, gpu_idle_minutes,
                    avg_disk_io_wait,
                    total_disk_read_gb,
                    total_disk_write_gb,
                    is_underutilized,
                    is_overutilized,
                    metric_count
                FROM daily_performance_stats
                WHERE system_id = ${systemID}
                AND day_bucket >= NOW() - (${days}::integer || ' days')::interval
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
                    avg_ram_percent, max_ram_percent, p95_ram_percent,
                    avg_gpu_percent, max_gpu_percent,
                    avg_disk_io_wait,
                    total_disk_read_gb,
                    total_disk_write_gb,
                    metric_count
                FROM daily_performance_stats
                WHERE system_id = ANY(${systemIDs})
                AND day_bucket >= NOW() - (${days}::integer || ' days')::interval
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
                AND timestamp >= NOW() - (${hours}::integer || ' hours')::interval
            `,
            'Failed to get metrics count'
        )
        return result[0]?.count || 0
    }

    async cleanupOldMetrics(days = 90) {
        // Note: This is handled by TimescaleDB retention policy,
        // but this method allows manual cleanup if needed
        return await this.query(
            this.sql`DELETE FROM metrics WHERE timestamp < NOW() - (${days}::integer || ' days')::interval`,
            'Failed to cleanup old metrics'
        )
    }

    // Get aggregate metrics from TimescaleDB continuous aggregate views
    async getAggregateMetrics(systemID, type = 'hourly', limit = 24) {
        this.validateID(systemID)
        
        if (type === 'hourly') {
            return await this.query(
                this.sql`
                    SELECT
                        system_id,
                        hour_bucket,
                        avg_cpu_percent,
                        max_cpu_percent,
                        min_cpu_percent,
                        p95_cpu_percent,
                        stddev_cpu_percent,
                        avg_ram_percent,
                        max_ram_percent,
                        p95_ram_percent,
                        stddev_ram_percent,
                        avg_gpu_percent,
                        max_gpu_percent,
                        stddev_gpu_percent,
                        avg_disk_percent,
                        max_disk_percent,
                        stddev_disk_percent,
                        metric_count
                    FROM hourly_performance_stats
                    WHERE system_id = ${systemID}
                    ORDER BY hour_bucket DESC
                    LIMIT ${limit}
                `,
                'Failed to get hourly aggregate metrics'
            )
        } else if (type === 'daily') {
            return await this.query(
                this.sql`
                    SELECT
                        system_id,
                        day_bucket,
                        avg_cpu_percent,
                        max_cpu_percent,
                        min_cpu_percent,
                        p95_cpu_percent,
                        stddev_cpu_percent,
                        avg_ram_percent,
                        max_ram_percent,
                        min_ram_percent,
                        p95_ram_percent,
                        stddev_ram_percent,
                        avg_gpu_percent,
                        max_gpu_percent,
                        min_gpu_percent,
                        stddev_gpu_percent,
                        avg_disk_percent,
                        max_disk_percent,
                        min_disk_percent,
                        stddev_disk_percent,
                        metric_count
                    FROM daily_performance_stats
                    WHERE system_id = ${systemID}
                    ORDER BY day_bucket DESC
                    LIMIT ${limit}
                `,
                'Failed to get daily aggregate metrics'
            )
        } else {
            throw new Error('Invalid aggregate type. Must be "hourly" or "daily"')
        }
    }

    // CFRS METRICS OPERATIONS -----------------------------------------------------------------
    // Get CFRS-relevant metrics for verification and visualization

    async getCFRSMetrics(systemID, hours = 24) {
        this.validateID(systemID)
        
        // Fetch raw CFRS metrics from the metrics table
        return await this.query(
            this.sql`
                SELECT
                    timestamp,
                    cpu_iowait_percent,
                    context_switch_rate,
                    swap_out_rate,
                    major_page_fault_rate,
                    cpu_temperature,
                    gpu_temperature,
                    swap_in_rate,
                    page_fault_rate,
                    cpu_percent,
                    ram_percent,
                    disk_percent
                FROM metrics
                WHERE system_id = ${systemID}
                AND timestamp >= NOW() - (${hours}::integer || ' hours')::interval
                ORDER BY timestamp DESC
            `,
            'Failed to get CFRS metrics'
        )
    }

    async getCFRSHourlyStats(systemID, hours = 24) {
        this.validateID(systemID)
        
        // Check if cfrs_hourly_stats exists, otherwise return empty array
        try {
            return await this.query(
                this.sql`
                    SELECT
                        hour_bucket as timestamp,
                        -- Tier-1 metrics (Primary CFRS drivers)
                        avg_cpu_iowait,
                        stddev_cpu_iowait,
                        p95_cpu_iowait,
                        cnt_cpu_iowait,
                        avg_context_switch,
                        stddev_context_switch,
                        p95_context_switch,
                        cnt_context_switch,
                        avg_swap_out,
                        stddev_swap_out,
                        p95_swap_out,
                        cnt_swap_out,
                        avg_major_page_faults,
                        stddev_major_page_faults,
                        p95_major_page_faults,
                        cnt_major_page_faults,
                        avg_cpu_temp,
                        stddev_cpu_temp,
                        p95_cpu_temp,
                        cnt_cpu_temp,
                        avg_gpu_temp,
                        stddev_gpu_temp,
                        p95_gpu_temp,
                        cnt_gpu_temp,
                        -- Tier-2 metrics (Secondary contributors)
                        avg_cpu_percent,
                        stddev_cpu_percent,
                        p95_cpu_percent,
                        cnt_cpu_percent,
                        avg_ram_percent,
                        stddev_ram_percent,
                        p95_ram_percent,
                        cnt_ram_percent,
                        avg_disk_percent,
                        stddev_disk_percent,
                        p95_disk_percent,
                        cnt_disk_percent,
                        avg_swap_in,
                        stddev_swap_in,
                        p95_swap_in,
                        cnt_swap_in,
                        avg_page_faults,
                        stddev_page_faults,
                        p95_page_faults,
                        cnt_page_faults,
                        total_samples
                    FROM cfrs_hourly_stats
                    WHERE system_id = ${systemID}
                    AND hour_bucket >= NOW() - (${hours}::integer || ' hours')::interval
                    ORDER BY hour_bucket DESC
                `,
                'Failed to get CFRS hourly stats'
            )
        } catch (error) {
            // If cfrs_hourly_stats doesn't exist, return empty array
            console.log('CFRS hourly stats not available:', error.message)
            return []
        }
    }

    async getLatestCFRSMetrics(systemID) {
        this.validateID(systemID)
        
        const result = await this.query(
            this.sql`
                SELECT
                    timestamp,
                    cpu_iowait_percent,
                    context_switch_rate,
                    swap_out_rate,
                    major_page_fault_rate,
                    cpu_temperature,
                    gpu_temperature,
                    swap_in_rate,
                    page_fault_rate,
                    cpu_percent,
                    ram_percent,
                    disk_percent
                FROM metrics
                WHERE system_id = ${systemID}
                ORDER BY timestamp DESC
                LIMIT 1
            `,
            'Failed to get latest CFRS metrics'
        )
        return result[0] || null
    }

    async getCFRSMetricsSummary(systemID, hours = 24) {
        this.validateID(systemID)
        
        const [latest, rawMetrics, hourlyStats] = await Promise.all([
            this.getLatestCFRSMetrics(systemID),
            this.getCFRSMetrics(systemID, hours),
            this.getCFRSHourlyStats(systemID, hours)
        ])

        return {
            system_id: systemID,
            latest_cfrs_metrics: latest,
            raw_cfrs_metrics: rawMetrics,
            hourly_cfrs_stats: hourlyStats,
            summary: {
                total_samples: rawMetrics.length,
                hours_analyzed: hours,
                has_cfrs_aggregates: hourlyStats.length > 0
            }
        }
    }
}

module.exports = MetricsModel