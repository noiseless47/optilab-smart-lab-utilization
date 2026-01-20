import { useEffect, useState } from 'react'
import { TrendingUp, TrendingDown, Activity, CheckCircle, Server } from 'lucide-react'
import Loading from '../components/Loading'
import api from '../lib/api'
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
} from 'chart.js'
import { Line } from 'react-chartjs-2'

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  Filler
)

interface MetricData {
  timestamp: string
  cpu_percent: number
  cpu_temperature: number
  ram_percent: number
  disk_percent: number
  disk_read_mbps: number
  disk_write_mbps: number
  network_sent_mbps: number
  network_recv_mbps: number
  uptime_seconds: number
  logged_in_users: number
  gpu_percent: number | null
  gpu_memory_used_gb: number | null
  gpu_temperature: number | null
}

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
  const [systems, setSystems] = useState<SystemWithMetrics[]>([])
  const [metrics, setMetrics] = useState<MetricData[]>([])
  const [selectedSystem, setSelectedSystem] = useState<number | null>(null)
  const [avgCpu, setAvgCpu] = useState(0)
  const [avgMemory, setAvgMemory] = useState(0)

  useEffect(() => {
    fetchAnalytics()
  }, [])

  useEffect(() => {
    if (selectedSystem) {
      fetchMetrics(selectedSystem)
    }
  }, [selectedSystem])

  const fetchMetrics = async (systemId: number) => {
    try {
      const response = await api.get(`/api/systems/${systemId}/metrics/history?limit=50`)
      const metricsData = response.data.map((m: any) => ({
        timestamp: m.timestamp,
        cpu_percent: m.cpu_percent || 0,
        cpu_temperature: m.cpu_temperature || 0,
        ram_percent: m.ram_percent || 0,
        disk_percent: m.disk_percent || 0,
        disk_read_mbps: m.disk_read_mbps || 0,
        disk_write_mbps: m.disk_write_mbps || 0,
        network_sent_mbps: m.network_sent_mbps || 0,
        network_recv_mbps: m.network_recv_mbps || 0,
        uptime_seconds: m.uptime_seconds || 0,
        logged_in_users: m.logged_in_users || 0,
        gpu_percent: m.gpu_percent,
        gpu_memory_used_gb: m.gpu_memory_used_gb,
        gpu_temperature: m.gpu_temperature
      }))
      setMetrics(metricsData.reverse()) // Show oldest to newest
    } catch (err) {
      console.error('Failed to fetch metrics:', err)
    }
  }

  const fetchAnalytics = async () => {
    try {
      setLoading(true)
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
      
      // Auto-select first system
      if (systemsWithMetrics.length > 0 && !selectedSystem) {
        setSelectedSystem(systemsWithMetrics[0].system_id)
      }
    } catch (err: any) {
      console.error('Failed to fetch analytics:', err)
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

  // Generate chart data with dynamic Y-axis
  const createChartData = (label: string, dataKey: keyof MetricData, color: string, unit: string) => {
    const values = metrics.map(m => m[dataKey] as number).filter(v => v !== null && v !== undefined)
    const labels = metrics.map(m => new Date(m.timestamp).toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit' }))
    
    return {
      labels,
      datasets: [{
        label: `${label} (${unit})`,
        data: values,
        borderColor: color,
        backgroundColor: color.replace('rgb', 'rgba').replace(')', ', 0.1)'),
        fill: true,
        tension: 0.4,
        pointRadius: 3,
        pointHoverRadius: 5
      }]
    }
  }

  const chartOptions = (title: string) => ({
    responsive: true,
    maintainAspectRatio: false,
    plugins: {
      legend: {
        display: true,
        position: 'top' as const,
      },
      title: {
        display: true,
        text: title,
        font: { size: 14, weight: 'bold' as const }
      }
    },
    scales: {
      y: {
        beginAtZero: true,
        ticks: {
          callback: function(value: any) {
            return value.toFixed(2)
          }
        }
      },
      x: {
        ticks: {
          maxRotation: 45,
          minRotation: 45
        }
      }
    }
  })

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Analytics</h1>
        <p className="text-gray-600">Real-time metrics and performance insights</p>
      </div>

      {/* System Selector */}
      <div className="card p-6 mb-8">
        <label className="block text-sm font-medium text-gray-700 mb-3">Select System</label>
        <select
          value={selectedSystem || ''}
          onChange={(e) => setSelectedSystem(Number(e.target.value))}
          className="w-full px-4 py-2.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300"
        >
          {systems.map(system => (
            <option key={system.system_id} value={system.system_id}>
              {system.hostname} - Lab {system.lab_id}
            </option>
          ))}
        </select>
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

      {metrics.length === 0 ? (
        <div className="card p-12 text-center">
          <Server className="w-16 h-16 mx-auto mb-4 text-gray-400" />
          <p className="text-gray-500">Select a system to view detailed metrics</p>
        </div>
      ) : (
        <>
          {/* CPU & Temperature Charts */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('CPU Usage', 'cpu_percent', 'rgb(249, 115, 22)', '%')} 
                  options={chartOptions('CPU Usage Over Time')} 
                />
              </div>
            </div>
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('CPU Temperature', 'cpu_temperature', 'rgb(239, 68, 68)', '°C')} 
                  options={chartOptions('CPU Temperature')} 
                />
              </div>
            </div>
          </div>

          {/* Memory & Disk Charts */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('RAM Usage', 'ram_percent', 'rgb(59, 130, 246)', '%')} 
                  options={chartOptions('Memory Usage Over Time')} 
                />
              </div>
            </div>
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Disk Usage', 'disk_percent', 'rgb(168, 85, 247)', '%')} 
                  options={chartOptions('Disk Usage Over Time')} 
                />
              </div>
            </div>
          </div>

          {/* Disk I/O Charts */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Disk Read', 'disk_read_mbps', 'rgb(16, 185, 129)', 'MB/s')} 
                  options={chartOptions('Disk Read Speed')} 
                />
              </div>
            </div>
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Disk Write', 'disk_write_mbps', 'rgb(245, 158, 11)', 'MB/s')} 
                  options={chartOptions('Disk Write Speed')} 
                />
              </div>
            </div>
          </div>

          {/* Network Charts */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Network Sent', 'network_sent_mbps', 'rgb(99, 102, 241)', 'MB/s')} 
                  options={chartOptions('Network Upload Speed')} 
                />
              </div>
            </div>
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Network Received', 'network_recv_mbps', 'rgb(236, 72, 153)', 'MB/s')} 
                  options={chartOptions('Network Download Speed')} 
                />
              </div>
            </div>
          </div>

          {/* System Stats */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Uptime', 'uptime_seconds', 'rgb(20, 184, 166)', 'seconds')} 
                  options={chartOptions('System Uptime')} 
                />
              </div>
            </div>
            <div className="card p-6">
              <div className="h-64">
                <Line 
                  data={createChartData('Logged In Users', 'logged_in_users', 'rgb(14, 165, 233)', 'users')} 
                  options={chartOptions('Active Users')} 
                />
              </div>
            </div>
          </div>

          {/* GPU Charts (if available) */}
          {metrics.some(m => m.gpu_percent !== null) && (
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-6">
              <div className="card p-6">
                <div className="h-64">
                  <Line 
                    data={createChartData('GPU Usage', 'gpu_percent', 'rgb(217, 70, 239)', '%')} 
                    options={chartOptions('GPU Usage')} 
                  />
                </div>
              </div>
              <div className="card p-6">
                <div className="h-64">
                  <Line 
                    data={createChartData('GPU Memory', 'gpu_memory_used_gb', 'rgb(244, 63, 94)', 'GB')} 
                    options={chartOptions('GPU Memory Usage')} 
                  />
                </div>
              </div>
              <div className="card p-6">
                <div className="h-64">
                  <Line 
                    data={createChartData('GPU Temp', 'gpu_temperature', 'rgb(251, 146, 60)', '°C')} 
                    options={chartOptions('GPU Temperature')} 
                  />
                </div>
              </div>
            </div>
          )}
        </>
      )}

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
