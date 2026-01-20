import { useEffect, useState } from 'react'
import { Activity, Wifi, AlertTriangle, TrendingUp, Server } from 'lucide-react'
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

interface SystemStatus {
  total: number
  online: number
  offline: number
  critical: number
}

interface SystemData {
  system_id: number
  hostname: string
  lab_id: number
}

export default function Dashboard() {
  const [stats, setStats] = useState<SystemStatus>({
    total: 0,
    online: 0,
    offline: 0,
    critical: 0
  })
  const [systems, setSystems] = useState<SystemData[]>([])
  const [metrics, setMetrics] = useState<MetricData[]>([])
  const [selectedSystem, setSelectedSystem] = useState<number | null>(null)

  useEffect(() => {
    fetchSystems()
  }, [])

  useEffect(() => {
    if (selectedSystem) {
      fetchMetrics(selectedSystem)
    }
  }, [selectedSystem])

  const fetchSystems = async () => {
    try {
      const response = await api.get('/api/systems/all')
      const systemsData = response.data
      setSystems(systemsData)
      
      // Auto-select first system
      if (systemsData.length > 0 && !selectedSystem) {
        setSelectedSystem(systemsData[0].system_id)
      }

      // Update stats
      setStats({
        total: systemsData.length,
        online: systemsData.length,
        offline: 0,
        critical: 0
      })
    } catch (err) {
      console.error('Failed to fetch systems:', err)
    }
  }

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
      setMetrics(metricsData.reverse())
    } catch (err) {
      console.error('Failed to fetch metrics:', err)
    }
  }

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
    <div className="max-w-7xl mx-auto px-6 py-16">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Performance Metrics</h1>
        <p className="text-gray-600">Real-time system monitoring and analytics</p>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-12">
        <StatCard
          title="Total Systems"
          value={stats.total.toString()}
          icon={<Server className="w-6 h-6" />}
          color="blue"
          trend="+5"
        />
        <StatCard
          title="Online"
          value={stats.online.toString()}
          icon={<Activity className="w-6 h-6" />}
          color="green"
          trend="+2"
        />
        <StatCard
          title="Offline"
          value={stats.offline.toString()}
          icon={<Wifi className="w-6 h-6" />}
          color="yellow"
          trend="-1"
        />
        <StatCard
          title="Critical Alerts"
          value={stats.critical.toString()}
          icon={<AlertTriangle className="w-6 h-6" />}
          color="red"
          trend="0"
        />
      </div>

      {/* System Selector */}
      <div className="card p-6 mb-8">
        <label className="block text-sm font-medium text-gray-700 mb-3">Select System to Monitor</label>
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
    </div>
  )
}

function StatCard({ title, value, icon, color, trend }: { title: string, value: string, icon: React.ReactNode, color: string, trend: string }) {
  const colorClasses = {
    blue: 'from-blue-500 to-blue-600',
    green: 'from-green-500 to-green-600',
    yellow: 'from-yellow-500 to-yellow-600',
    red: 'from-red-500 to-red-600',
  }[color]

  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <div className={`w-12 h-12 bg-gradient-to-br ${colorClasses} rounded-lg flex items-center justify-center text-white shadow-lg`}>
          {icon}
        </div>
        <div className="flex items-center space-x-1 text-green-600 text-sm font-medium">
          <TrendingUp className="w-4 h-4" />
          <span>{trend}</span>
        </div>
      </div>
      <div className="text-3xl font-bold text-gray-900 mb-1">{value}</div>
      <div className="text-sm text-gray-500 font-medium">{title}</div>
    </div>
  )
}
