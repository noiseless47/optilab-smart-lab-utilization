const sql = require('./db.js')

/**
 * CFRS (Composite Fault Risk Score) Model
 * 
 * Implementation of CFRS Technical Definition v1.0
 * 
 * CFRS Components:
 * - Deviation (D): Short-term abnormality from baseline (40%)
 * - Variance (V): Instability/unpredictability (30%)
 * - Trend (S): Long-term degradation (30%)
 * 
 * Metric Tiers:
 * - Tier-1 (6 metrics): Primary CFRS drivers (70% weight in D&V, 100% in S)
 *   cpu_iowait_percent, context_switch_rate, swap_out_rate,
 *   major_page_fault_rate, cpu_temperature, gpu_temperature
 * 
 * - Tier-2 (5 metrics): Secondary contributors (30% weight in D&V, 0% in S)
 *   cpu_percent, ram_percent, disk_percent, swap_in_rate, page_fault_rate
 */
class CFRSModel {
    constructor() {
        this.sql = sql
        
        // CFRS Configuration (default weights - configurable)
        this.config = {
            // Component weights (must sum to 1.0)
            weights: {
                deviation: 0.40,    // Deviation component weight
                variance: 0.30,     // Variance component weight
                trend: 0.30         // Trend component weight
            },
            
            // Tier-1 metrics (Primary CFRS drivers)
            tier1Metrics: [
                'cpu_iowait',
                'context_switch',
                'swap_out',
                'major_page_faults',
                'cpu_temp',
                'gpu_temp'
            ],
            
            // Tier-2 metrics (Secondary contributors)
            tier2Metrics: [
                'cpu_percent',
                'ram_percent',
                'disk_percent',
                'swap_in',
                'page_faults'
            ],
            
            // Metric distribution within components
            metricWeights: {
                deviation: {
                    tier1: 0.70,    // Tier-1 metrics get 70% of deviation weight
                    tier2: 0.30     // Tier-2 metrics get 30% of deviation weight
                },
                variance: {
                    tier1: 0.70,
                    tier2: 0.30
                },
                trend: {
                    tier1: 1.0,     // Only Tier-1 metrics used in trend
                    tier2: 0.0
                }
            },
            
            // Trend computation settings
            trendWindow: 30,        // Days for trend analysis
            minTrendDays: 20,       // Minimum days required for reliable trend
            
            // Baseline settings
            baselineWindow: 30,     // Days for baseline computation
            minBaselineSamples: 100 // Minimum samples for reliable baseline
        }
    }

    // ============================================================================
    // BASELINE MANAGEMENT
    // ============================================================================

    /**
     * Compute baseline statistics for a system and metric
     * @param {number} systemId - System ID
     * @param {string} metricName - Metric name (e.g., 'cpu_iowait')
     * @param {number} windowDays - Baseline window in days (default: 30)
     * @returns {object} Baseline statistics
     */
    async computeBaseline(systemId, metricName, windowDays = null) {
        if (!systemId || systemId <= 0) throw new Error('Invalid system ID')
        if (!metricName) throw new Error('Metric name required')
        
        windowDays = windowDays || this.config.baselineWindow
        
        // Map metric names to database column names
        const columnMap = {
            'cpu_iowait': 'cpu_iowait',
            'context_switch': 'context_switch',
            'swap_out': 'swap_out',
            'major_page_faults': 'major_page_faults',
            'cpu_temp': 'cpu_temp',
            'gpu_temp': 'gpu_temp',
            'cpu_percent': 'cpu_percent',
            'ram_percent': 'ram_percent',
            'disk_percent': 'disk_percent',
            'swap_in': 'swap_in',
            'page_faults': 'page_faults'
        }
        
        const columnName = columnMap[metricName]
        if (!columnName) throw new Error(`Unknown metric: ${metricName}`)
        
        try {
            // Compute baseline from hourly aggregates
            const result = await sql`
                SELECT
                    AVG(avg_${sql.unsafe(columnName)}) AS baseline_mean,
                    STDDEV(avg_${sql.unsafe(columnName)}) AS baseline_stddev,
                    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY avg_${sql.unsafe(columnName)}) AS baseline_median,
                    COUNT(*) AS sample_count,
                    MIN(hour_bucket) AS baseline_start,
                    MAX(hour_bucket) AS baseline_end
                FROM cfrs_hourly_stats
                WHERE system_id = ${systemId}
                  AND hour_bucket >= NOW() - (${windowDays}::integer || ' days')::interval
                  AND avg_${sql.unsafe(columnName)} IS NOT NULL
            `
            
            if (!result || result.length === 0) {
                throw new Error(`No data available for baseline computation`)
            }
            
            const stats = result[0]
            
            // Check minimum sample requirement
            if (stats.sample_count < this.config.minBaselineSamples) {
                throw new Error(`Insufficient samples for baseline (${stats.sample_count} < ${this.config.minBaselineSamples})`)
            }
            
            // Compute MAD (Median Absolute Deviation) for robustness
            const madResult = await sql`
                WITH deviations AS (
                    SELECT ABS(avg_${sql.unsafe(columnName)} - ${stats.baseline_median}) AS abs_deviation
                    FROM cfrs_hourly_stats
                    WHERE system_id = ${systemId}
                      AND hour_bucket >= NOW() - (${windowDays}::integer || ' days')::interval
                      AND avg_${sql.unsafe(columnName)} IS NOT NULL
                )
                SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY abs_deviation) AS mad
                FROM deviations
            `
            
            const baseline_mad = madResult && madResult.length > 0 ? madResult[0].mad : null
            
            return {
                system_id: systemId,
                metric_name: metricName,
                baseline_mean: parseFloat(stats.baseline_mean) || 0,
                baseline_stddev: parseFloat(stats.baseline_stddev) || 0,
                baseline_median: parseFloat(stats.baseline_median) || 0,
                baseline_mad: parseFloat(baseline_mad) || 0,
                sample_count: parseInt(stats.sample_count) || 0,
                baseline_start: stats.baseline_start,
                baseline_end: stats.baseline_end,
                baseline_window_days: windowDays
            }
        } catch (error) {
            console.error(`Failed to compute baseline for ${metricName}:`, error.message)
            throw error
        }
    }

    /**
     * Store baseline statistics in the database
     */
    async storeBaseline(baselineStats, notes = null) {
        const {
            system_id, metric_name, baseline_mean, baseline_stddev,
            baseline_median, baseline_mad, sample_count,
            baseline_start, baseline_end, baseline_window_days
        } = baselineStats
        
        try {
            const result = await sql`
                INSERT INTO cfrs_system_baselines (
                    system_id, metric_name,
                    baseline_mean, baseline_stddev, baseline_median, baseline_mad,
                    baseline_window_days, baseline_start, baseline_end, sample_count,
                    computed_at, is_active, notes
                ) VALUES (
                    ${system_id}, ${metric_name},
                    ${baseline_mean}, ${baseline_stddev}, ${baseline_median}, ${baseline_mad},
                    ${baseline_window_days}, ${baseline_start}, ${baseline_end}, ${sample_count},
                    NOW(), TRUE, ${notes}
                )
                ON CONFLICT (system_id, metric_name, baseline_start, baseline_end)
                DO UPDATE SET
                    baseline_mean = EXCLUDED.baseline_mean,
                    baseline_stddev = EXCLUDED.baseline_stddev,
                    baseline_median = EXCLUDED.baseline_median,
                    baseline_mad = EXCLUDED.baseline_mad,
                    sample_count = EXCLUDED.sample_count,
                    computed_at = NOW(),
                    is_active = TRUE,
                    notes = EXCLUDED.notes
                RETURNING *
            `
            
            return result && result.length > 0 ? result[0] : null
        } catch (error) {
            console.error('Failed to store baseline:', error.message)
            throw error
        }
    }

    /**
     * Compute and store baselines for all metrics of a system
     */
    async computeAllBaselines(systemId, windowDays = null) {
        const allMetrics = [...this.config.tier1Metrics, ...this.config.tier2Metrics]
        const results = []
        const errors = []
        
        for (const metricName of allMetrics) {
            try {
                const baseline = await this.computeBaseline(systemId, metricName, windowDays)
                const stored = await this.storeBaseline(baseline, `Auto-computed baseline`)
                results.push(stored)
            } catch (error) {
                errors.push({
                    metric: metricName,
                    error: error.message
                })
            }
        }
        
        return {
            system_id: systemId,
            computed: results.length,
            total: allMetrics.length,
            results,
            errors
        }
    }

    /**
     * Get active baseline for a system and metric
     */
    async getBaseline(systemId, metricName) {
        const result = await sql`
            SELECT *
            FROM cfrs_system_baselines
            WHERE system_id = ${systemId}
              AND metric_name = ${metricName}
              AND is_active = TRUE
            ORDER BY computed_at DESC
            LIMIT 1
        `
        
        return result && result.length > 0 ? result[0] : null
    }

    /**
     * Get all active baselines for a system
     */
    async getAllBaselines(systemId) {
        const result = await sql`
            SELECT *
            FROM cfrs_system_baselines
            WHERE system_id = ${systemId}
              AND is_active = TRUE
            ORDER BY metric_name
        `
        
        return result || []
    }

    // ============================================================================
    // CFRS COMPONENT COMPUTATION
    // ============================================================================

    /**
     * Compute Deviation Component (D)
     * Measures short-term abnormality from baseline
     * 
     * Formula: D_m = |x_m - μ_m| / σ_m (z-score)
     * Alternative: D_m = |x_m - median_m| / MAD_m (robust)
     * 
     * @param {object} currentStats - Current hourly statistics
     * @param {object} baselines - Baseline statistics (keyed by metric name)
     * @param {boolean} useMAD - Use MAD instead of stddev (robust)
     * @returns {object} Deviation scores by metric
     */
    computeDeviation(currentStats, baselines, useMAD = false) {
        const deviations = {}
        
        const metrics = {
            // Tier-1
            cpu_iowait: 'avg_cpu_iowait',
            context_switch: 'avg_context_switch',
            swap_out: 'avg_swap_out',
            major_page_faults: 'avg_major_page_faults',
            cpu_temp: 'avg_cpu_temp',
            gpu_temp: 'avg_gpu_temp',
            // Tier-2
            cpu_percent: 'avg_cpu_percent',
            ram_percent: 'avg_ram_percent',
            disk_percent: 'avg_disk_percent',
            swap_in: 'avg_swap_in',
            page_faults: 'avg_page_faults'
        }
        
        for (const [metricName, columnName] of Object.entries(metrics)) {
            const currentValue = currentStats[columnName]
            const baseline = baselines[metricName]
            
            if (currentValue === null || currentValue === undefined || !baseline) {
                deviations[metricName] = null
                continue
            }
            
            let deviation
            if (useMAD && baseline.baseline_mad > 0) {
                // Robust MAD-based deviation
                deviation = Math.abs(currentValue - baseline.baseline_median) / baseline.baseline_mad
            } else if (baseline.baseline_stddev > 0) {
                // Standard z-score
                deviation = Math.abs(currentValue - baseline.baseline_mean) / baseline.baseline_stddev
            } else {
                deviation = 0
            }
            
            deviations[metricName] = deviation
        }
        
        return deviations
    }

    /**
     * Compute Variance Component (V)
     * Captures instability and erratic behavior
     * 
     * Formula: V_m = σ_m / (μ_m + ε) (Coefficient of Variation)
     * 
     * @param {object} currentStats - Current hourly statistics
     * @returns {object} Variance scores by metric
     */
    computeVariance(currentStats) {
        const variances = {}
        const epsilon = 1e-6  // Prevent division by zero
        
        const metrics = {
            // Tier-1
            cpu_iowait: { avg: 'avg_cpu_iowait', stddev: 'stddev_cpu_iowait' },
            context_switch: { avg: 'avg_context_switch', stddev: 'stddev_context_switch' },
            swap_out: { avg: 'avg_swap_out', stddev: 'stddev_swap_out' },
            major_page_faults: { avg: 'avg_major_page_faults', stddev: 'stddev_major_page_faults' },
            cpu_temp: { avg: 'avg_cpu_temp', stddev: 'stddev_cpu_temp' },
            gpu_temp: { avg: 'avg_gpu_temp', stddev: 'stddev_gpu_temp' },
            // Tier-2
            cpu_percent: { avg: 'avg_cpu_percent', stddev: 'stddev_cpu_percent' },
            ram_percent: { avg: 'avg_ram_percent', stddev: 'stddev_ram_percent' },
            disk_percent: { avg: 'avg_disk_percent', stddev: 'stddev_disk_percent' },
            swap_in: { avg: 'avg_swap_in', stddev: 'stddev_swap_in' },
            page_faults: { avg: 'avg_page_faults', stddev: 'stddev_page_faults' }
        }
        
        for (const [metricName, cols] of Object.entries(metrics)) {
            const avg = currentStats[cols.avg]
            const stddev = currentStats[cols.stddev]
            
            if (avg === null || avg === undefined || stddev === null || stddev === undefined) {
                variances[metricName] = null
                continue
            }
            
            // Coefficient of Variation (CV)
            const cv = stddev / (Math.abs(avg) + epsilon)
            variances[metricName] = cv
        }
        
        return variances
    }

    /**
     * Compute Trend Component (S)
     * Detects long-term degradation via linear regression slope
     * 
     * Formula: S_m = REGR_SLOPE(avg_m, day_epoch)
     * 
     * @param {number} systemId - System ID
     * @param {number} windowDays - Days for trend analysis (default: 30)
     * @returns {object} Trend slopes by metric
     */
    async computeTrend(systemId, windowDays = null) {
        windowDays = windowDays || this.config.trendWindow
        
        try {
            // Compute slopes for all Tier-1 metrics
            const result = await sql`
                WITH trend_data AS (
                    SELECT
                        system_id,
                        day_bucket,
                        EXTRACT(EPOCH FROM day_bucket)::BIGINT AS day_epoch,
                        avg_cpu_iowait,
                        avg_context_switch,
                        avg_swap_out,
                        avg_major_page_faults,
                        avg_cpu_temp,
                        avg_gpu_temp
                    FROM cfrs_daily_stats
                    WHERE system_id = ${systemId}
                      AND day_bucket >= NOW() - (${windowDays}::integer || ' days')::interval
                    ORDER BY day_bucket
                )
                SELECT
                    COUNT(*) AS days_count,
                    REGR_SLOPE(avg_cpu_iowait, day_epoch) AS slope_cpu_iowait,
                    REGR_R2(avg_cpu_iowait, day_epoch) AS r2_cpu_iowait,
                    REGR_SLOPE(avg_context_switch, day_epoch) AS slope_context_switch,
                    REGR_R2(avg_context_switch, day_epoch) AS r2_context_switch,
                    REGR_SLOPE(avg_swap_out, day_epoch) AS slope_swap_out,
                    REGR_R2(avg_swap_out, day_epoch) AS r2_swap_out,
                    REGR_SLOPE(avg_major_page_faults, day_epoch) AS slope_major_page_faults,
                    REGR_R2(avg_major_page_faults, day_epoch) AS r2_major_page_faults,
                    REGR_SLOPE(avg_cpu_temp, day_epoch) AS slope_cpu_temp,
                    REGR_R2(avg_cpu_temp, day_epoch) AS r2_cpu_temp,
                    REGR_SLOPE(avg_gpu_temp, day_epoch) AS slope_gpu_temp,
                    REGR_R2(avg_gpu_temp, day_epoch) AS r2_gpu_temp
                FROM trend_data
                GROUP BY system_id
            `
            
            if (!result || result.length === 0) {
                throw new Error('No trend data available')
            }
            
            const trendData = result[0]
            
            // Check minimum days requirement
            if (trendData.days_count < this.config.minTrendDays) {
                throw new Error(`Insufficient days for trend analysis (${trendData.days_count} < ${this.config.minTrendDays})`)
            }
            
            // Extract slopes and normalize by time scale (slope per day)
            // Note: Slopes are already per-second from epoch, multiply by seconds in a day
            const secondsPerDay = 86400
            
            return {
                cpu_iowait: (parseFloat(trendData.slope_cpu_iowait) || 0) * secondsPerDay,
                context_switch: (parseFloat(trendData.slope_context_switch) || 0) * secondsPerDay,
                swap_out: (parseFloat(trendData.slope_swap_out) || 0) * secondsPerDay,
                major_page_faults: (parseFloat(trendData.slope_major_page_faults) || 0) * secondsPerDay,
                cpu_temp: (parseFloat(trendData.slope_cpu_temp) || 0) * secondsPerDay,
                gpu_temp: (parseFloat(trendData.slope_gpu_temp) || 0) * secondsPerDay,
                // R² values for quality assessment
                r2: {
                    cpu_iowait: parseFloat(trendData.r2_cpu_iowait) || 0,
                    context_switch: parseFloat(trendData.r2_context_switch) || 0,
                    swap_out: parseFloat(trendData.r2_swap_out) || 0,
                    major_page_faults: parseFloat(trendData.r2_major_page_faults) || 0,
                    cpu_temp: parseFloat(trendData.r2_cpu_temp) || 0,
                    gpu_temp: parseFloat(trendData.r2_gpu_temp) || 0
                },
                days_analyzed: trendData.days_count
            }
        } catch (error) {
            console.error('Failed to compute trend:', error.message)
            throw error
        }
    }

    // ============================================================================
    // CFRS SCORE COMPUTATION
    // ============================================================================

    /**
     * Compute weighted average of component scores
     * @param {object} scores - Scores by metric
     * @param {string} tier - 'tier1' or 'tier2'
     * @param {string} component - 'deviation', 'variance', or 'trend'
     * @returns {number} Weighted average score
     */
    computeWeightedScore(scores, tier, component) {
        const metrics = tier === 'tier1' ? this.config.tier1Metrics : this.config.tier2Metrics
        const validScores = []
        
        for (const metric of metrics) {
            const score = scores[metric]
            if (score !== null && score !== undefined && !isNaN(score)) {
                validScores.push(score)
            }
        }
        
        if (validScores.length === 0) return 0
        
        // Equal weight per metric within tier
        const avgScore = validScores.reduce((sum, s) => sum + s, 0) / validScores.length
        return avgScore
    }

    /**
     * Compute complete CFRS for a system
     * 
     * CFRS = w_D * D + w_V * V + w_S * S
     * 
     * Where:
     * - D = Deviation component (40%)
     * - V = Variance component (30%)
     * - S = Trend component (30%)
     * 
     * @param {number} systemId - System ID
     * @param {object} options - Computation options
     * @returns {object} CFRS score and component breakdown
     */
    async computeCFRS(systemId, options = {}) {
        if (!systemId || systemId <= 0) throw new Error('Invalid system ID')
        
        const {
            useMAD = false,
            trendWindow = null,
            customWeights = null
        } = options
        
        // Use custom weights if provided
        const weights = customWeights || this.config.weights
        
        try {
            // Step 1: Get latest hourly statistics
            const hourlyStats = await sql`
                SELECT *
                FROM cfrs_hourly_stats
                WHERE system_id = ${systemId}
                ORDER BY hour_bucket DESC
                LIMIT 1
            `
            
            if (!hourlyStats || hourlyStats.length === 0) {
                throw new Error('No hourly statistics available')
            }
            
            const currentStats = hourlyStats[0]
            
            // Step 2: Get all baselines
            const baselines = await this.getAllBaselines(systemId)
            const baselineMap = {}
            baselines.forEach(b => {
                baselineMap[b.metric_name] = b
            })
            
            // Check if baselines exist
            if (Object.keys(baselineMap).length === 0) {
                throw new Error('No baselines available. Compute baselines first.')
            }
            
            // Step 3: Compute Deviation component
            const deviations = this.computeDeviation(currentStats, baselineMap, useMAD)
            const deviationTier1 = this.computeWeightedScore(deviations, 'tier1', 'deviation')
            const deviationTier2 = this.computeWeightedScore(deviations, 'tier2', 'deviation')
            const deviationScore = (
                deviationTier1 * this.config.metricWeights.deviation.tier1 +
                deviationTier2 * this.config.metricWeights.deviation.tier2
            )
            
            // Step 4: Compute Variance component
            const variances = this.computeVariance(currentStats)
            const varianceTier1 = this.computeWeightedScore(variances, 'tier1', 'variance')
            const varianceTier2 = this.computeWeightedScore(variances, 'tier2', 'variance')
            const varianceScore = (
                varianceTier1 * this.config.metricWeights.variance.tier1 +
                varianceTier2 * this.config.metricWeights.variance.tier2
            )
            
            // Step 5: Compute Trend component
            const trends = await this.computeTrend(systemId, trendWindow)
            const trendTier1 = this.computeWeightedScore(trends, 'tier1', 'trend')
            // Normalize slope to [0, 1] range - positive slope = higher risk
            // Use sigmoid-like normalization: score = max(0, slope)
            const trendScore = Math.max(0, trendTier1)
            
            // Step 6: Compute final CFRS
            const cfrsScore = (
                weights.deviation * deviationScore +
                weights.variance * varianceScore +
                weights.trend * trendScore
            )
            
            return {
                system_id: systemId,
                cfrs_score: cfrsScore,
                computed_at: new Date(),
                
                // Component scores
                components: {
                    deviation: {
                        score: deviationScore,
                        weight: weights.deviation,
                        tier1: deviationTier1,
                        tier2: deviationTier2,
                        details: deviations
                    },
                    variance: {
                        score: varianceScore,
                        weight: weights.variance,
                        tier1: varianceTier1,
                        tier2: varianceTier2,
                        details: variances
                    },
                    trend: {
                        score: trendScore,
                        weight: weights.trend,
                        tier1: trendTier1,
                        days_analyzed: trends.days_analyzed,
                        details: trends,
                        r2_scores: trends.r2
                    }
                },
                
                // Metadata
                hour_bucket: currentStats.hour_bucket,
                total_samples: currentStats.total_samples,
                baselines_used: Object.keys(baselineMap).length,
                
                // Configuration used
                config: {
                    weights,
                    use_mad: useMAD,
                    trend_window: trendWindow || this.config.trendWindow
                }
            }
        } catch (error) {
            console.error('Failed to compute CFRS:', error.message)
            throw error
        }
    }

    /**
     * Compute CFRS for multiple systems
     */
    async computeBatchCFRS(systemIds, options = {}) {
        const results = []
        const errors = []
        
        for (const systemId of systemIds) {
            try {
                const cfrs = await this.computeCFRS(systemId, options)
                results.push(cfrs)
            } catch (error) {
                errors.push({
                    system_id: systemId,
                    error: error.message
                })
            }
        }
        
        return {
            computed: results.length,
            total: systemIds.length,
            results,
            errors
        }
    }

    /**
     * Get CFRS configuration
     */
    getConfig() {
        return { ...this.config }
    }

    /**
     * Update CFRS configuration
     */
    updateConfig(updates) {
        // Validate weights
        if (updates.weights) {
            const sum = (updates.weights.deviation || 0) +
                        (updates.weights.variance || 0) +
                        (updates.weights.trend || 0)
            
            if (Math.abs(sum - 1.0) > 0.001) {
                throw new Error('Component weights must sum to 1.0')
            }
        }
        
        this.config = {
            ...this.config,
            ...updates
        }
        
        return this.config
    }
}

module.exports = CFRSModel
