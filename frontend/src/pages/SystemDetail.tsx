import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Server, Cpu, HardDrive, Activity, Network, Plus } from 'lucide-react'
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

export default function SystemDetail() {
  const { deptId, labId, systemId } = useParams<{ deptId: string; labId: string; systemId: string }>()
  const navigate = useNavigate()
  
  const [system, setSystem] = useState<System | null>(null)
  const [metrics, setMetrics] = useState<Metric[]>([])
  const [loading, setLoading] = useState(true)
  const [showMaintenanceModal, setShowMaintenanceModal] = useState(false)
  const [toasts, setToasts] = useState<ToastMessage[]>([])
  
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
      const [labSystemsRes, metricsRes] = await Promise.all([
        api.get(`/departments/${deptId}/labs/${labId}/systems`),
        api.get(`/departments/${deptId}/labs/${labId}/${systemId}/metrics`, { params: { hours: 24, limit: 100 } })
      ])
      
      // Find the specific system from the lab's systems
      const system = labSystemsRes.data.find((s: any) => s.system_id === parseInt(systemId || '0'))
      if (!system) {
        throw new Error('System not found')
      }
      
      setSystem(system)
      setMetrics(metricsRes.data.reverse())
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
      {metrics.length > 0 ? (
        <>
          <h2 className="text-2xl font-bold text-gray-900 mb-6">Performance Metrics (Last 24 Hours)</h2>
          
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
        <div className="card p-12 text-center">
          <Activity className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-xl font-semibold text-gray-900 mb-2">No Metrics Available</h3>
          <p className="text-gray-600">No performance metrics have been collected for this system yet.</p>
        </div>
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
