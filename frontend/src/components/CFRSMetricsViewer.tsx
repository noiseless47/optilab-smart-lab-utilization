import { useState, useEffect } from 'react'
import { Activity, AlertCircle, TrendingUp, Zap, Gauge, Thermometer } from 'lucide-react'
import { Line } from 'react-chartjs-2'
import api from '../lib/api'

interface CFRSMetric {
  timestamp: string
  cpu_iowait_percent?: number
  context_switch_rate?: number
  swap_out_rate?: number
  major_page_fault_rate?: number
  cpu_temperature?: number
  gpu_temperature?: number
  swap_in_rate?: number
  page_fault_rate?: number
  cpu_percent?: number
  ram_percent?: number
  disk_percent?: number
}

interface CFRSViewerProps {
  systemId: string
}

export default function CFRSMetricsViewer({ systemId }: CFRSViewerProps) {
  const [metrics, setMetrics] = useState<CFRSMetric[]>([])
  const [latestMetrics, setLatestMetrics] = useState<CFRSMetric | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [timeRange, setTimeRange] = useState<number>(24) // hours
  const [viewMode, setViewMode] = useState<'tier1' | 'tier2' | 'all'>('tier1')

  useEffect(() => {
    fetchCFRSMetrics()
  }, [systemId, timeRange])

  const fetchCFRSMetrics = async () => {
    try {
      setLoading(true)
      setError(null)
      
      const [metricsRes, latestRes] = await Promise.all([
        api.get(`/systems/${systemId}/metrics/cfrs?hours=${timeRange}`),
        api.get(`/systems/${systemId}/metrics/cfrs/latest`)
      ])
      
      setMetrics(metricsRes.data)
      setLatestMetrics(latestRes.data)
    } catch (err: any) {
      console.error('Error fetching CFRS metrics:', err)
      setError(err.response?.data?.error || 'Failed to fetch CFRS metrics')
    } finally {
      setLoading(false)
    }
  }

  const formatValue = (value: number | string | undefined | null, decimals: number = 2): string => {
    if (value === null || value === undefined) return 'N/A'
    const numValue = typeof value === 'string' ? parseFloat(value) : value
    if (isNaN(numValue)) return 'N/A'
    return numValue.toFixed(decimals)
  }

  const formatLargeNumber = (value: number | string | undefined | null): string => {
    if (value === null || value === undefined) return 'N/A'
    const numValue = typeof value === 'string' ? parseFloat(value) : value
    if (isNaN(numValue)) return 'N/A'
    if (numValue >= 1000000) return `${(numValue / 1000000).toFixed(2)}M`
    if (numValue >= 1000) return `${(numValue / 1000).toFixed(2)}K`
    return numValue.toFixed(0)
  }

  const createChartData = (label: string, dataKey: keyof CFRSMetric, color: string) => {
    const reversedMetrics = [...metrics].reverse()
    return {
      labels: reversedMetrics.map(m => new Date(m.timestamp).toLocaleTimeString()),
      datasets: [{
        label,
        data: reversedMetrics.map(m => m[dataKey] as number),
        borderColor: color,
        backgroundColor: `${color}20`,
        tension: 0.4,
        fill: true,
        pointRadius: 2,
        pointHoverRadius: 5
      }]
    }
  }

  const chartOptions = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: false
      },
      tooltip: {
        mode: 'index' as const,
        intersect: false,
      }
    },
    scales: {
      x: {
        display: false
      },
      y: {
        beginAtZero: true,
        grid: {
          color: 'rgba(0, 0, 0, 0.05)'
        }
      }
    }
  }

  if (loading) {
    return (
      <div className="card p-8 text-center">
        <Activity className="w-12 h-12 text-gray-300 mx-auto mb-4 animate-pulse" />
        <p className="text-gray-600">Loading CFRS metrics...</p>
      </div>
    )
  }

  if (error) {
    return (
      <div className="card p-8 text-center bg-red-50 border-red-200">
        <AlertCircle className="w-12 h-12 text-red-400 mx-auto mb-4" />
        <h3 className="text-lg font-semibold text-red-800 mb-2">Error Loading CFRS Metrics</h3>
        <p className="text-red-600">{error}</p>
        <button onClick={fetchCFRSMetrics} className="btn-primary mt-4">
          Retry
        </button>
      </div>
    )
  }

  if (!latestMetrics && metrics.length === 0) {
    return (
      <div className="card p-8 text-center">
        <Activity className="w-12 h-12 text-gray-300 mx-auto mb-4" />
        <h3 className="text-lg font-semibold text-gray-700 mb-2">No CFRS Metrics Available</h3>
        <p className="text-gray-600">
          CFRS metrics have not been collected yet. Ensure the advanced metrics collector is running.
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h2 className="text-2xl font-bold text-gray-900 flex items-center gap-2">
            <Zap className="w-6 h-6 text-yellow-500" />
            CFRS Metrics Viewer
          </h2>
          <p className="text-sm text-gray-600 mt-1">
            Composite Fault Risk Score - Real-time metrics verification
          </p>
        </div>
        
        <div className="flex items-center gap-4">
          {/* Time Range Selector */}
          <select
            value={timeRange}
            onChange={(e) => setTimeRange(Number(e.target.value))}
            className="px-4 py-2 bg-white border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500"
          >
            <option value={1}>Last Hour</option>
            <option value={6}>Last 6 Hours</option>
            <option value={24}>Last 24 Hours</option>
            <option value={72}>Last 3 Days</option>
          </select>

          {/* View Mode Selector */}
          <div className="flex gap-2">
            <button
              onClick={() => setViewMode('tier1')}
              className={`px-4 py-2 rounded-lg font-medium transition-colors ${
                viewMode === 'tier1'
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              Tier-1
            </button>
            <button
              onClick={() => setViewMode('tier2')}
              className={`px-4 py-2 rounded-lg font-medium transition-colors ${
                viewMode === 'tier2'
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              Tier-2
            </button>
            <button
              onClick={() => setViewMode('all')}
              className={`px-4 py-2 rounded-lg font-medium transition-colors ${
                viewMode === 'all'
                  ? 'bg-primary-600 text-white'
                  : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
              }`}
            >
              All
            </button>
          </div>
        </div>
      </div>

      {/* Latest Values Card */}
      <div className="card p-6 bg-gradient-to-r from-primary-50 to-blue-50 border-primary-200">
        <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
          <Gauge className="w-5 h-5 text-primary-600" />
          Latest Readings
        </h3>
        <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
          {(viewMode === 'tier1' || viewMode === 'all') && (
            <>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">CPU I/O Wait</p>
                <p className="text-xl font-bold text-orange-600">
                  {formatValue(latestMetrics?.cpu_iowait_percent)}%
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">Context Switch</p>
                <p className="text-xl font-bold text-purple-600">
                  {formatLargeNumber(latestMetrics?.context_switch_rate)}/s
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">Swap Out</p>
                <p className="text-xl font-bold text-red-600">
                  {formatValue(latestMetrics?.swap_out_rate)}/s
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">Major PF</p>
                <p className="text-xl font-bold text-pink-600">
                  {formatValue(latestMetrics?.major_page_fault_rate)}/s
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">CPU Temp</p>
                <p className="text-xl font-bold text-yellow-600">
                  {formatValue(latestMetrics?.cpu_temperature, 1)}°C
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">GPU Temp</p>
                <p className="text-xl font-bold text-amber-600">
                  {formatValue(latestMetrics?.gpu_temperature, 1)}°C
                </p>
              </div>
            </>
          )}
          
          {(viewMode === 'tier2' || viewMode === 'all') && (
            <>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">CPU %</p>
                <p className="text-xl font-bold text-blue-600">
                  {formatValue(latestMetrics?.cpu_percent)}%
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">RAM %</p>
                <p className="text-xl font-bold text-green-600">
                  {formatValue(latestMetrics?.ram_percent)}%
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">Disk %</p>
                <p className="text-xl font-bold text-teal-600">
                  {formatValue(latestMetrics?.disk_percent)}%
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">Swap In</p>
                <p className="text-xl font-bold text-indigo-600">
                  {formatValue(latestMetrics?.swap_in_rate)}/s
                </p>
              </div>
              <div className="text-center">
                <p className="text-xs text-gray-600 mb-1">Page Faults</p>
                <p className="text-xl font-bold text-violet-600">
                  {formatValue(latestMetrics?.page_fault_rate)}/s
                </p>
              </div>
            </>
          )}
        </div>
      </div>

      {/* Charts Section */}
      {metrics.length > 0 && (
        <>
          {/* Tier-1 Metrics Charts */}
          {(viewMode === 'tier1' || viewMode === 'all') && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
                <TrendingUp className="w-5 h-5 text-red-600" />
                Tier-1 Metrics (Primary CFRS Drivers)
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {/* CPU I/O Wait */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">CPU I/O Wait %</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('CPU I/O Wait', 'cpu_iowait_percent', '#f97316')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Storage/network bottleneck indicator</p>
                </div>

                {/* Context Switch Rate */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">Context Switch Rate</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('Context Switches', 'context_switch_rate', '#a855f7')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">System thrashing indicator</p>
                </div>

                {/* Swap Out Rate */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">Swap Out Rate</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('Swap Out', 'swap_out_rate', '#ef4444')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Memory pressure critical</p>
                </div>

                {/* Major Page Faults */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">Major Page Fault Rate</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('Major Page Faults', 'major_page_fault_rate', '#ec4899')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Storage latency spike</p>
                </div>

                {/* CPU Temperature */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">CPU Temperature (°C)</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('CPU Temp', 'cpu_temperature', '#eab308')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Thermal stress indicator</p>
                </div>

                {/* GPU Temperature */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">GPU Temperature (°C)</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('GPU Temp', 'gpu_temperature', '#f59e0b')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">GPU cooling degradation</p>
                </div>
              </div>
            </div>
          )}

          {/* Tier-2 Metrics Charts */}
          {(viewMode === 'tier2' || viewMode === 'all') && (
            <div>
              <h3 className="text-lg font-semibold text-gray-900 mb-4 flex items-center gap-2">
                <Activity className="w-5 h-5 text-blue-600" />
                Tier-2 Metrics (Secondary Contributors)
              </h3>
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                {/* CPU Percent */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">CPU Utilization %</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('CPU %', 'cpu_percent', '#3b82f6')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Overall CPU usage</p>
                </div>

                {/* RAM Percent */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">RAM Utilization %</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('RAM %', 'ram_percent', '#10b981')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Memory utilization</p>
                </div>

                {/* Disk Percent */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">Disk Utilization %</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('Disk %', 'disk_percent', '#14b8a6')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Storage usage</p>
                </div>

                {/* Swap In Rate */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">Swap In Rate</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('Swap In', 'swap_in_rate', '#6366f1')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Memory reclaim activity</p>
                </div>

                {/* Page Fault Rate */}
                <div className="card p-4">
                  <h4 className="text-sm font-semibold text-gray-700 mb-3">Page Fault Rate</h4>
                  <div style={{ height: '180px' }}>
                    <Line data={createChartData('Page Faults', 'page_fault_rate', '#8b5cf6')} options={chartOptions} />
                  </div>
                  <p className="text-xs text-gray-500 mt-2">Memory access patterns</p>
                </div>
              </div>
            </div>
          )}
        </>
      )}

      {/* Info Footer */}
      <div className="card p-4 bg-blue-50 border-blue-200">
        <div className="flex items-start gap-3">
          <AlertCircle className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
          <div className="text-sm text-blue-800">
            <p className="font-medium mb-1">About CFRS Metrics</p>
            <p className="text-blue-700">
              <strong>Tier-1</strong> metrics are primary degradation indicators (use-case independent). 
              <strong> Tier-2</strong> metrics are secondary contributors (context-dependent). 
              These metrics feed into the Deviation (D), Variance (V), and Trend (S) components of the CFRS system.
            </p>
          </div>
        </div>
      </div>
    </div>
  )
}
