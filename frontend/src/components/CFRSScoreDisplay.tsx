import { useState, useEffect } from 'react'
import { Activity, TrendingUp, BarChart3, AlertTriangle, CheckCircle, XCircle, Info } from 'lucide-react'
import api from '../lib/api'
import Loading from './Loading'

interface CFRSScore {
  system_id: number
  cfrs_score: number
  computed_at: string
  components: {
    deviation: {
      score: number
      weight: number
      tier1: number
      tier2: number
      details: Record<string, number | null>
    }
    variance: {
      score: number
      weight: number
      tier1: number
      tier2: number
      details: Record<string, number | null>
    }
    trend: {
      score: number
      weight: number
      tier1: number
      days_analyzed: number
      details: Record<string, number>
      r2_scores: Record<string, number>
    }
  }
  hour_bucket: string
  total_samples: number
  baselines_used: number
  config: {
    weights: {
      deviation: number
      variance: number
      trend: number
    }
    use_mad: boolean
    trend_window: number
  }
}

interface Baseline {
  baseline_id: number
  system_id: number
  metric_name: string
  baseline_mean: number
  baseline_stddev: number
  baseline_median: number
  baseline_mad: number
  baseline_window_days: number
  sample_count: number
  computed_at: string
  is_active: boolean
}

interface CFRSScoreDisplayProps {
  systemId: string
}

export default function CFRSScoreDisplay({ systemId }: CFRSScoreDisplayProps) {
  const [cfrsScore, setCfrsScore] = useState<CFRSScore | null>(null)
  const [baselines, setBaselines] = useState<Baseline[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [computingBaselines, setComputingBaselines] = useState(false)

  useEffect(() => {
    fetchCFRSData()
  }, [systemId])

  const fetchCFRSData = async () => {
    try {
      setLoading(true)
      setError(null)

      // Fetch CFRS score and baselines in parallel
      const [scoreRes, baselinesRes] = await Promise.all([
        api.get(`/systems/${systemId}/cfrs/score`).catch(() => null),
        api.get(`/systems/${systemId}/cfrs/baselines`).catch(() => ({ data: [] }))
      ])

      if (scoreRes && scoreRes.data) {
        setCfrsScore(scoreRes.data)
      }
      setBaselines(baselinesRes.data || [])
    } catch (err: any) {
      console.error('Failed to fetch CFRS data:', err)
      setError(err.response?.data?.error || 'Failed to load CFRS data')
    } finally {
      setLoading(false)
    }
  }

  const computeBaselines = async () => {
    try {
      setComputingBaselines(true)
      await api.post(`/systems/${systemId}/cfrs/baselines/compute`)
      await fetchCFRSData()
    } catch (err: any) {
      setError(err.response?.data?.error || 'Failed to compute baselines')
    } finally {
      setComputingBaselines(false)
    }
  }

  const getRiskLevel = (score: number): { label: string; color: string; bgColor: string; icon: any } => {
    if (score < 1.0) return { label: 'Low', color: 'text-green-700', bgColor: 'bg-green-100', icon: CheckCircle }
    if (score < 2.0) return { label: 'Medium', color: 'text-yellow-700', bgColor: 'bg-yellow-100', icon: Info }
    if (score < 3.0) return { label: 'High', color: 'text-orange-700', bgColor: 'bg-orange-100', icon: AlertTriangle }
    return { label: 'Critical', color: 'text-red-700', bgColor: 'bg-red-100', icon: XCircle }
  }

  const formatMetricName = (name: string): string => {
    const names: Record<string, string> = {
      cpu_iowait: 'CPU I/O Wait',
      context_switch: 'Context Switch Rate',
      swap_out: 'Swap Out Rate',
      major_page_faults: 'Major Page Faults',
      cpu_temp: 'CPU Temperature',
      gpu_temp: 'GPU Temperature',
      cpu_percent: 'CPU Utilization',
      ram_percent: 'RAM Utilization',
      disk_percent: 'Disk Utilization',
      swap_in: 'Swap In Rate',
      page_faults: 'Page Faults'
    }
    return names[name] || name
  }

  if (loading) {
    return (
      <div className="card p-8">
        <Loading text="Loading CFRS score..." />
      </div>
    )
  }

  if (error && !cfrsScore) {
    return (
      <div className="card p-8">
        <div className="text-center">
          <AlertTriangle className="w-12 h-12 text-yellow-600 mx-auto mb-4" />
          <h3 className="text-lg font-semibold text-gray-900 mb-2">CFRS Not Available</h3>
          <p className="text-gray-600 mb-6">{error}</p>
          
          {baselines.length === 0 && (
            <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-4">
              <p className="text-sm text-blue-800 mb-3">
                No baselines found. Compute baselines first to enable CFRS scoring.
              </p>
              <button
                onClick={computeBaselines}
                disabled={computingBaselines}
                className="btn-primary"
              >
                {computingBaselines ? 'Computing...' : 'Compute Baselines'}
              </button>
            </div>
          )}
        </div>
      </div>
    )
  }

  if (!cfrsScore) {
    return (
      <div className="card p-8">
        <div className="text-center text-gray-600">
          No CFRS score available
        </div>
      </div>
    )
  }

  const riskLevel = getRiskLevel(cfrsScore.cfrs_score)
  const RiskIcon = riskLevel.icon

  return (
    <div className="space-y-6">
      {/* Main CFRS Score Card */}
      <div className="card p-8">
        <div className="flex items-center justify-between mb-6">
          <div>
            <h3 className="text-2xl font-bold text-gray-900 mb-2">
              Composite Fault Risk Score (CFRS)
            </h3>
            <p className="text-sm text-gray-600">
              Risk assessment based on deviation, variance, and trend analysis
            </p>
          </div>
          <div className={`px-6 py-3 rounded-lg ${riskLevel.bgColor} flex items-center space-x-2`}>
            <RiskIcon className={`w-6 h-6 ${riskLevel.color}`} />
            <span className={`text-lg font-bold ${riskLevel.color}`}>{riskLevel.label} Risk</span>
          </div>
        </div>

        {/* CFRS Score Display */}
        <div className="bg-gradient-to-br from-orange-50 to-yellow-50 rounded-xl p-8 mb-6">
          <div className="text-center">
            <p className="text-sm font-medium text-gray-600 mb-2">CFRS Score</p>
            <div className="text-6xl font-bold text-gray-900 mb-2">
              {cfrsScore.cfrs_score.toFixed(3)}
            </div>
            <p className="text-xs text-gray-500">
              Computed at {new Date(cfrsScore.computed_at).toLocaleString()}
            </p>
          </div>
        </div>

        {/* Component Breakdown */}
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
          {/* Deviation Component */}
          <div className="bg-blue-50 rounded-lg p-4">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center space-x-2">
                <Activity className="w-5 h-5 text-blue-600" />
                <span className="font-semibold text-gray-900">Deviation</span>
              </div>
              <span className="text-xs text-gray-600">{(cfrsScore.components.deviation.weight * 100).toFixed(0)}%</span>
            </div>
            <div className="text-2xl font-bold text-blue-700 mb-1">
              {cfrsScore.components.deviation.score.toFixed(3)}
            </div>
            <div className="text-xs text-gray-600 space-y-1">
              <div>Tier-1: {cfrsScore.components.deviation.tier1.toFixed(2)}</div>
              <div>Tier-2: {cfrsScore.components.deviation.tier2.toFixed(2)}</div>
            </div>
          </div>

          {/* Variance Component */}
          <div className="bg-purple-50 rounded-lg p-4">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center space-x-2">
                <BarChart3 className="w-5 h-5 text-purple-600" />
                <span className="font-semibold text-gray-900">Variance</span>
              </div>
              <span className="text-xs text-gray-600">{(cfrsScore.components.variance.weight * 100).toFixed(0)}%</span>
            </div>
            <div className="text-2xl font-bold text-purple-700 mb-1">
              {cfrsScore.components.variance.score.toFixed(3)}
            </div>
            <div className="text-xs text-gray-600 space-y-1">
              <div>Tier-1: {cfrsScore.components.variance.tier1.toFixed(2)}</div>
              <div>Tier-2: {cfrsScore.components.variance.tier2.toFixed(2)}</div>
            </div>
          </div>

          {/* Trend Component */}
          <div className="bg-green-50 rounded-lg p-4">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center space-x-2">
                <TrendingUp className="w-5 h-5 text-green-600" />
                <span className="font-semibold text-gray-900">Trend</span>
              </div>
              <span className="text-xs text-gray-600">{(cfrsScore.components.trend.weight * 100).toFixed(0)}%</span>
            </div>
            <div className="text-2xl font-bold text-green-700 mb-1">
              {cfrsScore.components.trend.score.toFixed(3)}
            </div>
            <div className="text-xs text-gray-600 space-y-1">
              <div>Days: {cfrsScore.components.trend.days_analyzed}</div>
              <div>Tier-1: {cfrsScore.components.trend.tier1.toFixed(2)}</div>
            </div>
          </div>
        </div>

        {/* Metadata */}
        <div className="bg-gray-50 rounded-lg p-4">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
            <div>
              <p className="text-gray-600 mb-1">Baselines Used</p>
              <p className="font-semibold text-gray-900">{cfrsScore.baselines_used}</p>
            </div>
            <div>
              <p className="text-gray-600 mb-1">Total Samples</p>
              <p className="font-semibold text-gray-900">{cfrsScore.total_samples}</p>
            </div>
            <div>
              <p className="text-gray-600 mb-1">Trend Window</p>
              <p className="font-semibold text-gray-900">{cfrsScore.config.trend_window} days</p>
            </div>
            <div>
              <p className="text-gray-600 mb-1">Method</p>
              <p className="font-semibold text-gray-900">
                {cfrsScore.config.use_mad ? 'MAD-based' : 'Z-score'}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Detailed Component Metrics */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Deviation Details */}
        <div className="card p-6">
          <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center">
            <Activity className="w-5 h-5 text-blue-600 mr-2" />
            Deviation Details
          </h4>
          <div className="space-y-3">
            {Object.entries(cfrsScore.components.deviation.details).map(([metric, value]) => (
              <div key={metric} className="flex items-center justify-between py-2 border-b border-gray-100">
                <span className="text-sm text-gray-700">{formatMetricName(metric)}</span>
                <span className="text-sm font-semibold text-gray-900">
                  {value !== null ? value.toFixed(3) : 'N/A'}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Variance Details */}
        <div className="card p-6">
          <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center">
            <BarChart3 className="w-5 h-5 text-purple-600 mr-2" />
            Variance Details
          </h4>
          <div className="space-y-3">
            {Object.entries(cfrsScore.components.variance.details).map(([metric, value]) => (
              <div key={metric} className="flex items-center justify-between py-2 border-b border-gray-100">
                <span className="text-sm text-gray-700">{formatMetricName(metric)}</span>
                <span className="text-sm font-semibold text-gray-900">
                  {value !== null ? value.toFixed(3) : 'N/A'}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Trend Details */}
        <div className="card p-6">
          <h4 className="text-lg font-semibold text-gray-900 mb-4 flex items-center">
            <TrendingUp className="w-5 h-5 text-green-600 mr-2" />
            Trend Slopes (per day)
          </h4>
          <div className="space-y-3">
            {Object.entries(cfrsScore.components.trend.details)
              .filter(([key]) => key !== 'r2' && key !== 'days_analyzed')
              .map(([metric, value]) => {
                const r2 = cfrsScore.components.trend.r2_scores?.[metric]
                return (
                  <div key={metric} className="py-2 border-b border-gray-100">
                    <div className="flex items-center justify-between mb-1">
                      <span className="text-sm text-gray-700">{formatMetricName(metric)}</span>
                      <span className={`text-sm font-semibold ${value > 0 ? 'text-red-600' : 'text-green-600'}`}>
                        {value.toFixed(6)}
                      </span>
                    </div>
                    {r2 !== undefined && (
                      <div className="text-xs text-gray-500">R² = {r2.toFixed(3)}</div>
                    )}
                  </div>
                )
              })}
          </div>
        </div>

        {/* Baselines Summary */}
        <div className="card p-6">
          <h4 className="text-lg font-semibold text-gray-900 mb-4">Active Baselines</h4>
          <div className="space-y-3">
            {baselines.length > 0 ? (
              baselines.slice(0, 11).map(baseline => (
                <div key={baseline.baseline_id} className="py-2 border-b border-gray-100">
                  <div className="flex items-center justify-between mb-1">
                    <span className="text-sm text-gray-700">{formatMetricName(baseline.metric_name)}</span>
                    <span className="text-sm font-semibold text-gray-900">
                      μ={baseline.baseline_mean.toFixed(2)}
                    </span>
                  </div>
                  <div className="text-xs text-gray-500">
                    σ={baseline.baseline_stddev.toFixed(2)} • {baseline.sample_count} samples
                  </div>
                </div>
              ))
            ) : (
              <p className="text-sm text-gray-600">No baselines available</p>
            )}
          </div>
          {baselines.length === 0 && (
            <button
              onClick={computeBaselines}
              disabled={computingBaselines}
              className="btn-primary w-full mt-4"
            >
              {computingBaselines ? 'Computing...' : 'Compute Baselines'}
            </button>
          )}
        </div>
      </div>

      {/* Interpretation Guide */}
      <div className="card p-6 bg-blue-50">
        <h4 className="text-lg font-semibold text-gray-900 mb-3">Understanding CFRS</h4>
        <div className="space-y-2 text-sm text-gray-700">
          <p>
            <strong>Deviation:</strong> Measures how far current behavior deviates from the established baseline. Higher values indicate abnormal behavior.
          </p>
          <p>
            <strong>Variance:</strong> Captures system instability and erratic behavior. High variance indicates unpredictable performance.
          </p>
          <p>
            <strong>Trend:</strong> Detects long-term degradation patterns. Positive slopes indicate worsening conditions over time.
          </p>
          <p className="mt-3 pt-3 border-t border-blue-200">
            <strong>Risk Levels:</strong> Low (&lt;1.0) • Medium (1.0-2.0) • High (2.0-3.0) • Critical (&gt;3.0)
          </p>
        </div>
      </div>
    </div>
  )
}
