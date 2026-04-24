import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Server, Cpu, HardDrive, Activity, Network, Plus, BarChart3, TrendingUp, Zap } from 'lucide-react'
import { Line } from 'react-chartjs-2'
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
import Modal from '../components/Modal'
import Toast, { ToastMessage } from '../components/Toast'
import Loading from '../components/Loading'
import CFRSMetricsViewer from '../components/CFRSMetricsViewer'
import CFRSScoreDisplay from '../components/CFRSScoreDisplay'
import api from '../lib/api'

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

interface System {
  system_id: number
  system_number: number
  hostname: string
  ip_address: string
  mac_address?: string
  status: string
  cpu_model?: string
  cpu_cores?: number
  ram_total_gb?: number
  disk_total_gb?: number
  gpu_model?: string
  gpu_memory?: number
  created_at: string
}

interface Metric {
  timestamp: string
  cpu_percent?: number
  cpu_temperature?: number
  ram_percent?: number
  disk_percent?: number
  disk_read_mbps?: number
  disk_write_mbps?: number
  network_sent_mbps?: number
  network_recv_mbps?: number
  uptime_seconds?: number
  logged_in_users?: number
  gpu_percent?: number
  gpu_memory_used_gb?: number
  gpu_temperature?: number
}

interface AggregateMetric {
  hour_bucket?: string
  day_bucket?: string
  system_id: string
  avg_cpu_percent: number
  max_cpu_percent: number
  p95_cpu_percent: number
  avg_ram_percent: number
  max_ram_percent: number
  p95_ram_percent: number
  avg_gpu_percent?: number
  max_gpu_percent?: number
  avg_disk_io_wait?: number
  total_disk_read_gb?: number
  total_disk_write_gb?: number
  avg_load_1min?: number
  metric_count: number
}

export default function SystemDetail() {
  const { deptId, labId, systemId } = useParams<{ deptId: string; labId: string; systemId: string }>()
  const navigate = useNavigate()
  
  const [system, setSystem] = useState<System | null>(null)
  const [metrics, setMetrics] = useState<Metric[]>([])
  const [aggregateMetrics, setAggregateMetrics] = useState<AggregateMetric[]>([])
  const [loading, setLoading] = useState(true)
  const [showMaintenanceModal, setShowMaintenanceModal] = useState(false)
  const [toasts, setToasts] = useState<ToastMessage[]>([])
  
  // Toggle states for Live vs Aggregate and view type
  const [metricsMode, setMetricsMode] = useState<'live' | 'aggregate' | 'cfrs'>('live')
  const [viewType, setViewType] = useState<'graphs' | 'numeric'>('graphs')
  
  const [maintenanceForm, setMaintenanceForm] = useState({
    severity: 'medium',
    message: '',
  })

  const addToast = (message: string, type: 'success' | 'error' | 'info' | 'warning') => {
    const id = Date.now().toString()
    setToasts(prev => [...prev, { id, message, type }])
  }

  const removeToast = (id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id))
  }

  useEffect(() => {
    if (systemId) {
      fetchSystemData()
    }
  }, [systemId])

  const fetchSystemData = async () => {
    try {
      setLoading(true)
      // First get all systems in the lab, then find the specific one
      const [labSystemsRes, metricsRes, aggregateRes] = await Promise.all([
        api.get(`/departments/${deptId}/labs/${labId}/systems`),
        api.get(`/departments/${deptId}/labs/${labId}/${systemId}/metrics`, { params: { hours: 24, limit: 100 } }),
        api.get(`/departments/${deptId}/labs/${labId}/${systemId}/metrics/aggregate`, { params: { type: 'hourly' } }).catch(() => ({ data: [] }))
      ])
      
      // Find the specific system from the lab's systems
      const system = labSystemsRes.data.find((s: any) => s.system_id === parseInt(systemId || '0'))
      if (!system) {
        throw new Error('System not found')
      }
      
      setSystem(system)
      setMetrics(metricsRes.data.reverse())
      setAggregateMetrics(aggregateRes.data || [])
    } catch (error) {
      console.error('Failed to fetch system data:', error)
      addToast('Failed to load system data', 'error')
    } finally {
      setLoading(false)
    }
  }

  const handleAddToMaintenance = async () => {
    if (!maintenanceForm.message.trim()) {
      addToast('Problem description is required', 'error')
      return
    }

    try {
      await api.post(`/departments/${deptId}/labs/${labId}/maintenance`, {
        system_id: systemId,
        severity: maintenanceForm.severity,
        message: maintenanceForm.message,
        date_at: new Date().toISOString(),
      })
      addToast('System added to maintenance logs', 'success')
      setShowMaintenanceModal(false)
      setMaintenanceForm({ severity: 'medium', message: '' })
    } catch (error) {
      console.error('Failed to add maintenance log:', error)
      addToast('Failed to add maintenance log', 'error')
    }
  }

  const prepareChartData = (dataKey: keyof Metric, label: string, color: string) => {
    return {
      labels: metrics.map(m => new Date(m.timestamp).toLocaleTimeString()),
      datasets: [
        {
          label,
          data: metrics.map(m => m[dataKey] || 0),
          borderColor: color,
          backgroundColor: color + '20',
          fill: true,
          tension: 0.4,
          pointRadius: 2,
          pointHoverRadius: 4,
        }
      ]
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
      y: {
        beginAtZero: true,
        ticks: {
          callback: (value: any) => value.toFixed(2)
        }
      }
    }
  }

  const percentChartOptions = {
    ...chartOptions,
    scales: {
      y: {
        beginAtZero: true,
        ticks: {
          callback: (value: any) => value + '%'
        }
      }
    }
  }

  const networkChartOptions = {
    ...chartOptions,
    scales: {
      y: {
        beginAtZero: true,
        ticks: {
          callback: (value: any) => value.toFixed(2) + ' Mbps'
        }
      }
    }
  }

  const tempChartOptions = {
    ...chartOptions,
    scales: {
      y: {
        beginAtZero: true,
        ticks: {
          callback: (value: any) => value.toFixed(1) + '°C'
        }
      }
    }
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <Loading text="Loading system..." />
      </div>
    )
  }

  if (!system) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="card p-12 text-center">
          <h3 className="text-xl font-semibold text-gray-900 mb-2">System Not Found</h3>
          <button onClick={() => navigate(`/departments/${deptId}/labs/${labId}`)} className="btn-primary mt-4">
            Back to Lab
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      {/* Header */}
      <div className="mb-8">
        <button
          onClick={() => navigate(`/departments/${deptId}/labs/${labId}`)}
          className="flex items-center space-x-2 text-gray-600 hover:text-gray-900 mb-4"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to Lab</span>
        </button>
        <div className="flex items-start justify-between">
          <div>
            <h1 className="text-4xl font-bold text-gray-900 mb-2">{system.hostname}</h1>
            <p className="text-gray-600">System #{system.system_number} • {system.ip_address}</p>
          </div>
          <button
            onClick={() => setShowMaintenanceModal(true)}
            className="btn-primary flex items-center space-x-2"
          >
            <Plus className="w-4 h-4" />
            <span>Add to Maintenance</span>
          </button>
        </div>
      </div>

      {/* System Static Information */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-8">
        <div className="card p-6">
          <div className="flex items-center space-x-3 mb-3">
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <Server className="w-5 h-5 text-blue-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">Status</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">{system.status || 'Unknown'}</p>
        </div>

        <div className="card p-6">
          <div className="flex items-center space-x-3 mb-3">
            <div className="w-10 h-10 bg-purple-100 rounded-lg flex items-center justify-center">
              <Cpu className="w-5 h-5 text-purple-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">CPU</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">{system.cpu_cores || 'N/A'} cores</p>
          {system.cpu_model && (
            <p className="text-xs text-gray-500 mt-1 truncate">{system.cpu_model}</p>
          )}
        </div>

        <div className="card p-6">
          <div className="flex items-center space-x-3 mb-3">
            <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <Activity className="w-5 h-5 text-green-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">RAM</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">{system.ram_total_gb || 'N/A'} GB</p>
        </div>

        <div className="card p-6">
          <div className="flex items-center space-x-3 mb-3">
            <div className="w-10 h-10 bg-orange-100 rounded-lg flex items-center justify-center">
              <HardDrive className="w-5 h-5 text-orange-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">Disk</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">{system.disk_total_gb || 'N/A'} GB</p>
        </div>

        <div className="card p-6">
          <div className="flex items-center space-x-3 mb-3">
            <div className="w-10 h-10 bg-indigo-100 rounded-lg flex items-center justify-center">
              <Server className="w-5 h-5 text-indigo-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">Uptime</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">
            {metrics.length > 0 && metrics[metrics.length - 1]?.uptime_seconds !== null && metrics[metrics.length - 1]?.uptime_seconds !== undefined
              ? `${Math.floor((metrics[metrics.length - 1]?.uptime_seconds ?? 0) / 3600)}h ${Math.floor(((metrics[metrics.length - 1]?.uptime_seconds ?? 0) % 3600) / 60)}m`
              : 'N/A'}
          </p>
        </div>

        <div className="card p-6">
          <div className="flex items-center space-x-3 mb-3">
            <div className="w-10 h-10 bg-cyan-100 rounded-lg flex items-center justify-center">
              <Activity className="w-5 h-5 text-cyan-600" />
            </div>
            <span className="text-sm font-medium text-gray-600">Logged In Users</span>
          </div>
          <p className="text-2xl font-bold text-gray-900">
            {metrics.length > 0 && metrics[metrics.length - 1].logged_in_users !== null && metrics[metrics.length - 1].logged_in_users !== undefined
              ? metrics[metrics.length - 1].logged_in_users
              : 'N/A'}
          </p>
        </div>
      </div>

      {/* Metrics Mode Toggle */}
      <div className="flex items-center justify-between mb-8">
        <h2 className="text-2xl font-bold text-gray-900">Performance Metrics</h2>
        
        <div className="flex items-center space-x-6">
          {/* Mode Toggle: Live vs Aggregate vs CFRS */}
          <div className="flex items-center space-x-2 bg-gray-100 rounded-lg p-1">
            <button
              onClick={() => setMetricsMode('live')}
              className={`px-4 py-2 rounded-md font-medium transition ${
                metricsMode === 'live'
                  ? 'bg-white text-orange-600 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              <TrendingUp className="w-4 h-4 inline mr-2" />
              Live
            </button>
            <button
              onClick={() => setMetricsMode('aggregate')}
              className={`px-4 py-2 rounded-md font-medium transition ${
                metricsMode === 'aggregate'
                  ? 'bg-white text-orange-600 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              <BarChart3 className="w-4 h-4 inline mr-2" />
              Aggregate
            </button>
            <button
              onClick={() => setMetricsMode('cfrs')}
              className={`px-4 py-2 rounded-md font-medium transition ${
                metricsMode === 'cfrs'
                  ? 'bg-white text-yellow-600 shadow-sm'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              <Zap className="w-4 h-4 inline mr-2" />
              CFRS
            </button>
          </div>

          {/* View Type Toggle: Only show for Live metrics */}
          {metricsMode === 'live' && (
            <div className="flex items-center space-x-2 bg-gray-100 rounded-lg p-1">
              <button
                onClick={() => setViewType('graphs')}
                className={`px-4 py-2 rounded-md font-medium transition ${
                  viewType === 'graphs'
                    ? 'bg-white text-blue-600 shadow-sm'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                Graphs
              </button>
              <button
                onClick={() => setViewType('numeric')}
                className={`px-4 py-2 rounded-md font-medium transition ${
                  viewType === 'numeric'
                    ? 'bg-white text-blue-600 shadow-sm'
                    : 'text-gray-600 hover:text-gray-900'
                }`}
              >
                Numeric
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Additional System Info */}
      <div className="card p-6 mb-8">
        <h3 className="text-lg font-semibold text-gray-900 mb-4">System Information</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          <div>
            <p className="text-sm text-gray-500">MAC Address</p>
            <p className="text-sm font-mono text-gray-900">{system.mac_address || 'N/A'}</p>
          </div>
          {system.gpu_model && (
            <>
              <div>
                <p className="text-sm text-gray-500">GPU Model</p>
                <p className="text-sm text-gray-900">{system.gpu_model}</p>
              </div>
              {system.gpu_memory && (
                <div>
                  <p className="text-sm text-gray-500">GPU Memory</p>
                  <p className="text-sm text-gray-900">{system.gpu_memory} GB</p>
                </div>
              )}
            </>
          )}
          <div>
            <p className="text-sm text-gray-500">Added</p>
            <p className="text-sm text-gray-900">{new Date(system.created_at).toLocaleDateString()}</p>
          </div>
        </div>
      </div>

      {/* Metrics Visualization */}
      {metricsMode === 'cfrs' ? (
        // CFRS SCORE DISPLAY SECTION
        <>
          <CFRSScoreDisplay systemId={systemId || ''} />
          <div className="mt-8">
            <h3 className="text-xl font-bold text-gray-900 mb-4">CFRS Raw Metrics</h3>
            <CFRSMetricsViewer systemId={systemId || ''} />
          </div>
        </>
      ) : metricsMode === 'live' ? (
        // LIVE METRICS SECTION
        metrics.length > 0 ? (
          <>
            {viewType === 'graphs' ? (
              // LIVE - GRAPHS VIEW
              <>
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-8">
                  {/* CPU Usage */}
                  <div className="card p-6">
                    <div className="flex items-center space-x-2 mb-4">
                      <Cpu className="w-5 h-5 text-purple-600" />
                      <h3 className="text-lg font-semibold text-gray-900">CPU Usage</h3>
                    </div>
                    <div className="h-64">
                      <Line data={prepareChartData('cpu_percent', 'CPU %', '#9333ea')} options={percentChartOptions} />
                    </div>
                  </div>

                  {/* CPU Temperature */}
            <div className="card p-6">
              <div className="flex items-center space-x-2 mb-4">
                <Cpu className="w-5 h-5 text-red-600" />
                <h3 className="text-lg font-semibold text-gray-900">CPU Temperature</h3>
              </div>
              <div className="h-64">
                <Line data={prepareChartData('cpu_temperature', 'Temperature °C', '#dc2626')} options={tempChartOptions} />
              </div>
            </div>

            {/* RAM Usage */}
            <div className="card p-6">
              <div className="flex items-center space-x-2 mb-4">
                <Activity className="w-5 h-5 text-green-600" />
                <h3 className="text-lg font-semibold text-gray-900">RAM Usage</h3>
              </div>
              <div className="h-64">
                <Line data={prepareChartData('ram_percent', 'RAM %', '#16a34a')} options={percentChartOptions} />
              </div>
            </div>

            {/* Disk Usage */}
            <div className="card p-6">
              <div className="flex items-center space-x-2 mb-4">
                <HardDrive className="w-5 h-5 text-orange-600" />
                <h3 className="text-lg font-semibold text-gray-900">Disk Usage</h3>
              </div>
              <div className="h-64">
                <Line data={prepareChartData('disk_percent', 'Disk %', '#ea580c')} options={percentChartOptions} />
              </div>
            </div>

            {/* Disk I/O */}
            <div className="card p-6">
              <div className="flex items-center space-x-2 mb-4">
                <HardDrive className="w-5 h-5 text-teal-600" />
                <h3 className="text-lg font-semibold text-gray-900">Disk I/O</h3>
              </div>
              <div className="h-64">
                <Line 
                  data={{
                    labels: metrics.map(m => new Date(m.timestamp).toLocaleTimeString()),
                    datasets: [
                      {
                        label: 'Read',
                        data: metrics.map(m => m.disk_read_mbps || 0),
                        borderColor: '#0d9488',
                        backgroundColor: '#0d948820',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 2,
                      },
                      {
                        label: 'Write',
                        data: metrics.map(m => m.disk_write_mbps || 0),
                        borderColor: '#d97706',
                        backgroundColor: '#d9770620',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 2,
                      }
                    ]
                  }}
                  options={networkChartOptions}
                />
              </div>
            </div>

            {/* Network I/O */}
            <div className="card p-6">
              <div className="flex items-center space-x-2 mb-4">
                <Network className="w-5 h-5 text-blue-600" />
                <h3 className="text-lg font-semibold text-gray-900">Network I/O</h3>
              </div>
              <div className="h-64">
                <Line 
                  data={{
                    labels: metrics.map(m => new Date(m.timestamp).toLocaleTimeString()),
                    datasets: [
                      {
                        label: 'Sent',
                        data: metrics.map(m => m.network_sent_mbps || 0),
                        borderColor: '#2563eb',
                        backgroundColor: '#2563eb20',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 2,
                      },
                      {
                        label: 'Received',
                        data: metrics.map(m => m.network_recv_mbps || 0),
                        borderColor: '#10b981',
                        backgroundColor: '#10b98120',
                        fill: true,
                        tension: 0.4,
                        pointRadius: 2,
                      }
                    ]
                  }}
                  options={networkChartOptions}
                />
              </div>
            </div>

            {/* GPU Usage (if available) */}
            {metrics.some(m => m.gpu_percent !== null && m.gpu_percent !== undefined) && (
              <div className="card p-6">
                <div className="flex items-center space-x-2 mb-4">
                  <Activity className="w-5 h-5 text-pink-600" />
                  <h3 className="text-lg font-semibold text-gray-900">GPU Usage</h3>
                </div>
                <div className="h-64">
                  <Line data={prepareChartData('gpu_percent', 'GPU %', '#ec4899')} options={percentChartOptions} />
                </div>
              </div>
            )}

            {/* GPU Memory (if available) */}
            {metrics.some(m => m.gpu_memory_used_gb !== null && m.gpu_memory_used_gb !== undefined) && (
              <div className="card p-6">
                <div className="flex items-center space-x-2 mb-4">
                  <Activity className="w-5 h-5 text-rose-600" />
                  <h3 className="text-lg font-semibold text-gray-900">GPU Memory</h3>
                </div>
                <div className="h-64">
                  <Line 
                    data={prepareChartData('gpu_memory_used_gb', 'Memory GB', '#f43f5e')} 
                    options={{
                      ...chartOptions,
                      scales: {
                        y: {
                          beginAtZero: true,
                          ticks: {
                            callback: (value: any) => value.toFixed(2) + ' GB'
                          }
                        }
                      }
                    }}
                  />
                </div>
              </div>
            )}

            {/* GPU Temperature (if available) */}
            {metrics.some(m => m.gpu_temperature !== null && m.gpu_temperature !== undefined) && (
              <div className="card p-6">
                <div className="flex items-center space-x-2 mb-4">
                  <Activity className="w-5 h-5 text-orange-600" />
                  <h3 className="text-lg font-semibold text-gray-900">GPU Temperature</h3>
                </div>
                <div className="h-64">
                  <Line data={prepareChartData('gpu_temperature', 'Temperature °C', '#f97316')} options={tempChartOptions} />
                </div>
              </div>
            )}
          </div>
            </>
            ) : (
              // LIVE - NUMERIC VIEW
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
                {/* Current CPU */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">CPU Usage</p>
                      <p className="text-3xl font-bold text-purple-600">{(metrics[metrics.length - 1]?.cpu_percent ?? 0).toFixed(2)}%</p>
                    </div>
                    <Cpu className="w-12 h-12 text-purple-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Current CPU Temperature */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">CPU Temp</p>
                      <p className="text-3xl font-bold text-red-600">{(metrics[metrics.length - 1]?.cpu_temperature ?? 0).toFixed(1)}°C</p>
                    </div>
                    <Cpu className="w-12 h-12 text-red-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Current RAM */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">RAM Usage</p>
                      <p className="text-3xl font-bold text-green-600">{(metrics[metrics.length - 1]?.ram_percent ?? 0).toFixed(2)}%</p>
                    </div>
                    <Activity className="w-12 h-12 text-green-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Current Disk */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">Disk Usage</p>
                      <p className="text-3xl font-bold text-orange-600">{(metrics[metrics.length - 1]?.disk_percent ?? 0).toFixed(2)}%</p>
                    </div>
                    <HardDrive className="w-12 h-12 text-orange-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Network Upload */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">Network Upload</p>
                      <p className="text-3xl font-bold text-blue-600">{(metrics[metrics.length - 1]?.network_sent_mbps ?? 0).toFixed(2)} Mbps</p>
                    </div>
                    <Network className="w-12 h-12 text-blue-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Network Download */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">Network Download</p>
                      <p className="text-3xl font-bold text-green-600">{(metrics[metrics.length - 1]?.network_recv_mbps ?? 0).toFixed(2)} Mbps</p>
                    </div>
                    <Network className="w-12 h-12 text-green-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Disk Read Speed */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">Disk Read</p>
                      <p className="text-3xl font-bold text-teal-600">{(metrics[metrics.length - 1]?.disk_read_mbps ?? 0).toFixed(2)} MB/s</p>
                    </div>
                    <HardDrive className="w-12 h-12 text-teal-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {/* Disk Write Speed */}
                <div className="card p-6">
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <p className="text-sm text-gray-500">Disk Write</p>
                      <p className="text-3xl font-bold text-amber-600">{(metrics[metrics.length - 1]?.disk_write_mbps ?? 0).toFixed(2)} MB/s</p>
                    </div>
                    <HardDrive className="w-12 h-12 text-amber-200" />
                  </div>
                  <p className="text-xs text-gray-400">Latest reading</p>
                </div>

                {metrics[metrics.length - 1]?.gpu_percent !== null && metrics[metrics.length - 1]?.gpu_percent !== undefined && (
                  <div className="card p-6">
                    <div className="flex items-center justify-between mb-4">
                      <div>
                        <p className="text-sm text-gray-500">GPU Usage</p>
                        <p className="text-3xl font-bold text-pink-600">{(metrics[metrics.length - 1]?.gpu_percent ?? 0).toFixed(2)}%</p>
                      </div>
                      <Activity className="w-12 h-12 text-pink-200" />
                    </div>
                    <p className="text-xs text-gray-400">Latest reading</p>
                  </div>
                )}
              </div>
            )}
          </>
        ) : (
        <div className="card p-12 text-center">
          <Activity className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-xl font-semibold text-gray-900 mb-2">No Metrics Available</h3>
          <p className="text-gray-600">No performance metrics have been collected for this system yet.</p>
        </div>
      )
      ) : (
        // AGGREGATE METRICS SECTION
        aggregateMetrics.length > 0 ? (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-8">
            {aggregateMetrics.map((metric, idx) => (
              <div key={idx} className="card p-6">
                <h3 className="text-sm font-semibold text-gray-600 mb-4">
                  {metric.hour_bucket ? new Date(metric.hour_bucket).toLocaleString() : new Date(metric.day_bucket || '').toLocaleString()}
                </h3>
                <div className="space-y-3">
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-500">Avg CPU</span>
                    <span className="font-bold text-purple-600">{metric.avg_cpu_percent.toFixed(1)}%</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-500">Max CPU</span>
                    <span className="font-bold text-purple-700">{metric.max_cpu_percent.toFixed(1)}%</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-500">P95 CPU</span>
                    <span className="font-bold text-purple-500">{metric.p95_cpu_percent.toFixed(1)}%</span>
                  </div>
                  <hr className="my-2" />
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-500">Avg RAM</span>
                    <span className="font-bold text-green-600">{metric.avg_ram_percent.toFixed(1)}%</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-500">Max RAM</span>
                    <span className="font-bold text-green-700">{metric.max_ram_percent.toFixed(1)}%</span>
                  </div>
                  <div className="flex justify-between items-center">
                    <span className="text-sm text-gray-500">P95 RAM</span>
                    <span className="font-bold text-green-500">{metric.p95_ram_percent.toFixed(1)}%</span>
                  </div>
                  {metric.total_disk_read_gb !== undefined && (
                    <>
                      <hr className="my-2" />
                      <div className="flex justify-between items-center">
                        <span className="text-sm text-gray-500">Disk Read</span>
                        <span className="font-bold text-teal-600">{metric.total_disk_read_gb.toFixed(2)} GB</span>
                      </div>
                      <div className="flex justify-between items-center">
                        <span className="text-sm text-gray-500">Disk Write</span>
                        <span className="font-bold text-amber-600">{(metric.total_disk_write_gb || 0).toFixed(2)} GB</span>
                      </div>
                    </>
                  )}
                  {metric.avg_gpu_percent !== undefined && metric.avg_gpu_percent !== null && (
                    <>
                      <hr className="my-2" />
                      <div className="flex justify-between items-center">
                        <span className="text-sm text-gray-500">Avg GPU</span>
                        <span className="font-bold text-pink-600">{metric.avg_gpu_percent.toFixed(1)}%</span>
                      </div>
                      <div className="flex justify-between items-center">
                        <span className="text-sm text-gray-500">Max GPU</span>
                        <span className="font-bold text-pink-700">{(metric.max_gpu_percent || 0).toFixed(1)}%</span>
                      </div>
                    </>
                  )}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="card p-12 text-center">
            <BarChart3 className="w-16 h-16 text-gray-300 mx-auto mb-4" />
            <h3 className="text-xl font-semibold text-gray-900 mb-2">No Aggregate Data Available</h3>
            <p className="text-gray-600">Aggregate metrics are still being computed. Please check back later.</p>
          </div>
        )
      )}

      {/* Add to Maintenance Modal */}
      <Modal
        isOpen={showMaintenanceModal}
        onClose={() => {
          setShowMaintenanceModal(false)
          setMaintenanceForm({ severity: 'medium', message: '' })
        }}
        title="Add to Maintenance Logs"
        size="md"
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Severity <span className="text-red-500">*</span>
            </label>
            <select
              value={maintenanceForm.severity}
              onChange={(e) => setMaintenanceForm({ ...maintenanceForm, severity: e.target.value })}
              className="w-full px-4 py-2.5 bg-white text-gray-900 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
            >
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Problem Description <span className="text-red-500">*</span>
            </label>
            <textarea
              value={maintenanceForm.message}
              onChange={(e) => setMaintenanceForm({ ...maintenanceForm, message: e.target.value })}
              className="w-full px-4 py-2.5 bg-white text-gray-900 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              rows={4}
              placeholder="Describe the issue or maintenance requirement..."
            />
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button
              onClick={() => {
                setShowMaintenanceModal(false)
                setMaintenanceForm({ severity: 'medium', message: '' })
              }}
              className="btn-secondary"
            >
              Cancel
            </button>
            <button onClick={handleAddToMaintenance} className="btn-primary">
              Add to Maintenance
            </button>
          </div>
        </div>
      </Modal>

      {/* Toast */}
      <Toast toasts={toasts} removeToast={removeToast} />
    </div>
  )
}
