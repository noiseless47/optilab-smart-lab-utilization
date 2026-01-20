import { useEffect, useState } from 'react'
import { TrendingUp, TrendingDown, BarChart3, PieChart, Activity, CheckCircle } from 'lucide-react'
import Loading from '../components/Loading'
import api from '../lib/api'

interface SystemWithMetrics {
  system_id: number
  hostname: string
  lab_id: number
  cpu: number
  memory: number
  disk: number
}

export default function Analytics() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [systems, setSystems] = useState<SystemWithMetrics[]>([])
  const [avgCpu, setAvgCpu] = useState(0)
  const [avgMemory, setAvgMemory] = useState(0)

  useEffect(() => {
    fetchAnalytics()
  }, [])

  const fetchAnalytics = async () => {
    try {
      setLoading(true)
      setError(null)
      const systemsRes = await api.get('/api/systems/all')
      const systemsData = systemsRes.data

      const systemsWithMetrics = await Promise.all(
        systemsData.map(async (system: any) => {
          try {
            const metricsRes = await api.get(`/api/systems/${system.system_id}/metrics/latest`)
            const metrics = metricsRes.data
            return {
              system_id: system.system_id,
              hostname: system.hostname,
              lab_id: system.lab_id,
              cpu: metrics?.cpu_percent || 0,
              memory: metrics?.ram_percent || 0,
              disk: metrics?.disk_percent || 0
            }
          } catch {
            return {
              system_id: system.system_id,
              hostname: system.hostname,
              lab_id: system.lab_id,
              cpu: 0,
              memory: 0,
              disk: 0
            }
          }
        })
      )

      setSystems(systemsWithMetrics)
      
      // Calculate averages
      const totalCpu = systemsWithMetrics.reduce((acc, s) => acc + s.cpu, 0)
      const totalMemory = systemsWithMetrics.reduce((acc, s) => acc + s.memory, 0)
      setAvgCpu(systemsWithMetrics.length > 0 ? Math.round(totalCpu / systemsWithMetrics.length) : 0)
      setAvgMemory(systemsWithMetrics.length > 0 ? Math.round(totalMemory / systemsWithMetrics.length) : 0)
    } catch (err: any) {
      console.error('Failed to fetch analytics:', err)
      setError(err.response?.data?.error || 'Failed to load analytics')
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Analytics</h1>
          <p className="text-gray-600">Advanced insights and resource optimization</p>
        </div>
        <Loading text="Loading analytics..." />
      </div>
    )
  }

  // Get top consumers by CPU
  const topCpuConsumers = [...systems]
    .sort((a, b) => b.cpu - a.cpu)
    .slice(0, 5)

  // Count high usage systems
  const highCpuCount = systems.filter(s => s.cpu > 80).length
  const highMemoryCount = systems.filter(s => s.memory > 80).length
  const highDiskCount = systems.filter(s => s.disk > 80).length

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Analytics</h1>
        <p className="text-gray-600">Advanced insights and resource optimization</p>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        <MetricCard
          title="Avg CPU Usage"
          value={`${avgCpu}%`}
          change={avgCpu > 70 ? '+High' : 'Normal'}
          trend={avgCpu > 70 ? 'up' : 'down'}
          icon={<Activity className="w-5 h-5" />}
        />
        <MetricCard
          title="Avg Memory"
          value={`${avgMemory}%`}
          change={avgMemory > 70 ? '+High' : 'Normal'}
          trend={avgMemory > 70 ? 'up' : 'down'}
          icon={<Activity className="w-5 h-5" />}
        />
        <MetricCard
          title="Total Systems"
          value={`${systems.length}`}
          change="Active"
          trend="down"
          icon={<TrendingUp className="w-5 h-5" />}
        />
        <MetricCard
          title="High CPU Systems"
          value={`${highCpuCount}`}
          change={highCpuCount > 5 ? 'Warning' : 'Normal'}
          trend={highCpuCount > 5 ? 'up' : 'down'}
          icon={<TrendingDown className="w-5 h-5" />}
        />
      </div>

      {/* Charts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-12">
        <ChartCard
          title="Resource Utilization Trend"
          subtitle="Last 7 days"
          icon={<BarChart3 className="w-5 h-5" />}
        />
        <ChartCard
          title="Department Distribution"
          subtitle="By resource consumption"
          icon={<PieChart className="w-5 h-5" />}
        />
      </div>

      {/* Top Consumers */}
      <div className="card p-6 mb-12">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Top CPU Consumers</h2>
        {topCpuConsumers.length === 0 ? (
          <p className="text-gray-500 text-center py-8">No system data available</p>
        ) : (
          <div className="space-y-4">
            {topCpuConsumers.map(system => (
              <ConsumerBar
                key={system.system_id}
                system={system.hostname}
                lab={`Lab ${system.lab_id}`}
                value={Math.round(system.cpu)}
                color={system.cpu > 90 ? 'red' : system.cpu > 70 ? 'yellow' : 'green'}
              />
            ))}
          </div>
        )}
      </div>

      {/* Recommendations */}
      <div className="card p-6">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Optimization Recommendations</h2>
        <div className="space-y-4">
          {highMemoryCount > 0 && (
            <Recommendation
              type="hardware"
              title="High Memory Usage Detected"
              description={`${highMemoryCount} system(s) consistently exceed 80% memory usage. Consider upgrading RAM.`}
              priority="high"
            />
          )}
          {highDiskCount > 0 && (
            <Recommendation
              type="maintenance"
              title="Disk Cleanup Required"
              description={`${highDiskCount} system(s) have disk usage above 80%. Schedule cleanup to prevent performance degradation.`}
              priority="high"
            />
          )}
          {highCpuCount > 0 && (
            <Recommendation
              type="optimization"
              title="High CPU Load"
              description={`${highCpuCount} system(s) are experiencing elevated CPU usage. Consider workload balancing.`}
              priority="medium"
            />
          )}
          {highCpuCount === 0 && highMemoryCount === 0 && highDiskCount === 0 && (
            <div className="text-center py-8 text-gray-500">
              <CheckCircle className="w-12 h-12 mx-auto mb-2 text-green-500" />
              <p>All systems operating within normal parameters</p>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

function MetricCard({ title, value, change, trend, icon }: {
  title: string
  value: string
  change: string
  trend: string
  icon: React.ReactNode
}) {
  const trendColor = trend === 'up' ? 'text-green-600' : 'text-red-600'
  const TrendIcon = trend === 'up' ? TrendingUp : TrendingDown

  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="text-gray-600">{icon}</div>
        <div className={`flex items-center space-x-1 ${trendColor} text-sm font-medium`}>
          <TrendIcon className="w-4 h-4" />
          <span>{change}</span>
        </div>
      </div>
      <div className="text-3xl font-bold text-gray-900 mb-1">{value}</div>
      <div className="text-sm text-gray-500">{title}</div>
    </div>
  )
}

function ChartCard({ title, subtitle, icon }: { title: string, subtitle: string, icon: React.ReactNode }) {
  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">{title}</h3>
          <p className="text-sm text-gray-500 mt-1">{subtitle}</p>
        </div>
        <div className="text-gray-600">{icon}</div>
      </div>
      <div className="h-64 bg-gradient-to-br from-gray-50 to-gray-100 rounded-lg flex items-center justify-center">
        <p className="text-gray-400 text-sm">Chart visualization placeholder</p>
      </div>
    </div>
  )
}

function ConsumerBar({ system, lab, value, color }: { system: string, lab: string, value: number, color: string }) {
  const colorClasses = {
    red: 'bg-red-500',
    yellow: 'bg-yellow-500',
    green: 'bg-green-500',
  }[color]

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div>
          <div className="font-medium text-gray-900">{system}</div>
          <div className="text-sm text-gray-500">{lab}</div>
        </div>
        <span className="text-sm font-semibold text-gray-900">{value}%</span>
      </div>
      <div className="w-full bg-gray-100 rounded-full h-2">
        <div className={`${colorClasses} h-2 rounded-full`} style={{ width: `${value}%` }}></div>
      </div>
    </div>
  )
}

function Recommendation({ type, title, description, priority }: {
  type: string
  title: string
  description: string
  priority: string
}) {
  const typeConfig = {
    hardware: { icon: '🔧', bg: 'bg-blue-50', border: 'border-blue-200' },
    optimization: { icon: '⚡', bg: 'bg-purple-50', border: 'border-purple-200' },
    maintenance: { icon: '🛠️', bg: 'bg-orange-50', border: 'border-orange-200' },
  }[type]

  const priorityConfig = {
    high: { bg: 'bg-red-100', text: 'text-red-700' },
    medium: { bg: 'bg-yellow-100', text: 'text-yellow-700' },
    low: { bg: 'bg-green-100', text: 'text-green-700' },
  }[priority]

  return (
    <div className={`${typeConfig?.bg} ${typeConfig?.border} border rounded-lg p-4`}>
      <div className="flex items-start space-x-3">
        <div className="text-2xl">{typeConfig?.icon}</div>
        <div className="flex-1">
          <div className="flex items-center justify-between mb-2">
            <h4 className="font-semibold text-gray-900">{title}</h4>
            <span className={`px-2 py-1 rounded-full text-xs font-medium ${priorityConfig?.bg} ${priorityConfig?.text}`}>
              {priority.toUpperCase()}
            </span>
          </div>
          <p className="text-sm text-gray-600">{description}</p>
        </div>
      </div>
    </div>
  )
}
