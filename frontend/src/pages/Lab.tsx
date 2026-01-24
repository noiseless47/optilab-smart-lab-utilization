import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Server, Activity } from 'lucide-react'
import Toast, { ToastMessage } from '../components/Toast'
import Loading from '../components/Loading'
import api from '../lib/api'

interface System {
  system_id: number
  system_number: number
  hostname: string
  ip_address: string
  mac_address?: string
  status: string
  cpu_cores?: number
  ram_total_gb?: number
  disk_total_gb?: number
}

interface Lab {
  lab_id: number
  lab_number: number
  lab_dept: number
}

interface Department {
  dept_id: number
  dept_name: string
  dept_code: string
}

export default function Lab() {
  const { deptId, labId } = useParams<{ deptId: string; labId: string }>()
  const navigate = useNavigate()
  
  const [lab, setLab] = useState<Lab | null>(null)
  const [department, setDepartment] = useState<Department | null>(null)
  const [systems, setSystems] = useState<System[]>([])
  const [loading, setLoading] = useState(true)
  const [toasts, setToasts] = useState<ToastMessage[]>([])

  const addToast = (message: string, type: 'success' | 'error' | 'info' | 'warning') => {
    const id = Date.now().toString()
    setToasts(prev => [...prev, { id, message, type }])
  }

  const removeToast = (id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id))
  }

  useEffect(() => {
    if (deptId && labId) {
      fetchLabData()
    }
  }, [deptId, labId])

  const fetchLabData = async () => {
    try {
      setLoading(true)
      const [deptRes, labRes, systemsRes] = await Promise.all([
        api.get(`/departments/${deptId}`),
        api.get(`/departments/${deptId}/labs/${labId}`),
        api.get(`/departments/${deptId}/labs/${labId}/systems`)
      ])
      
      setDepartment(deptRes.data)
      setLab(labRes.data)
      setSystems(Array.isArray(systemsRes.data) ? systemsRes.data : [])
    } catch (error) {
      console.error('Failed to fetch lab data:', error)
      addToast('Failed to load lab data', 'error')
    } finally {
      setLoading(false)
    }
  }

  const handleSystemClick = (systemId: number) => {
    navigate(`/departments/${deptId}/labs/${labId}/systems/${systemId}`)
  }

  // Status is dynamically calculated based on last metrics timestamp
  // - 'active': metrics received within last 10 minutes
  // - 'offline': no metrics for 10+ minutes  
  // - 'unknown': never sent metrics
  // See docs/DYNAMIC_STATUS.md for details
  const getStatusColor = (status: string) => {
    switch (status?.toLowerCase()) {
      case 'active':
      case 'online':
        return 'bg-green-100 text-green-700'
      case 'offline':
        return 'bg-gray-100 text-gray-700'
      case 'unknown':
        return 'bg-blue-100 text-blue-700'
      case 'maintenance':
        return 'bg-yellow-100 text-yellow-700'
      case 'critical':
        return 'bg-red-100 text-red-700'
      default:
        return 'bg-gray-100 text-gray-700'
    }
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <Loading text="Loading lab..." />
      </div>
    )
  }

  if (!lab || !department) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="card p-12 text-center">
          <h3 className="text-xl font-semibold text-gray-900 mb-2">Lab Not Found</h3>
          <button onClick={() => navigate('/departments')} className="btn-primary mt-4">
            Back to Departments
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
          onClick={() => navigate(`/departments/${deptId}`)}
          className="flex items-center space-x-2 text-gray-600 hover:text-gray-900 mb-4"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to {department.dept_name}</span>
        </button>
        <h1 className="text-4xl font-bold text-gray-900 mb-2">
          {department.dept_code} Lab {lab.lab_number}
        </h1>
        <p className="text-gray-600">{systems.length} system{systems.length !== 1 ? 's' : ''} in this lab</p>
      </div>

      {/* Systems Grid */}
      {systems.length === 0 ? (
        <div className="card p-12 text-center">
          <Server className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-xl font-semibold text-gray-900 mb-2">No Systems Yet</h3>
          <p className="text-gray-600">No systems have been added to this lab.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6">
          {systems.map((system) => (
            <div
              key={system.system_id}
              onClick={() => handleSystemClick(system.system_id)}
              className="card p-6 hover:shadow-xl transition-all duration-200 cursor-pointer group"
            >
              {/* Header */}
              <div className="flex items-start justify-between mb-4">
                <div className="w-12 h-12 bg-gradient-to-br from-primary-500 to-primary-600 rounded-lg flex items-center justify-center">
                  <Server className="w-6 h-6 text-white" />
                </div>
                <span className={`px-2 py-1 text-xs font-semibold rounded-full ${getStatusColor(system.status)}`}>
                  {system.status || 'Unknown'}
                </span>
              </div>

              {/* System Info */}
              <h3 className="text-lg font-bold text-gray-900 mb-1 group-hover:text-primary-600 transition-colors">
                {system.hostname}
              </h3>
              <p className="text-sm text-gray-500 mb-4">System #{system.system_number}</p>

              {/* Metrics */}
              <div className="space-y-2">
                <div className="flex items-center justify-between text-xs">
                  <span className="text-gray-500">IP Address</span>
                  <span className="text-gray-900 font-mono">{system.ip_address}</span>
                </div>
                {system.cpu_cores && (
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-gray-500">CPU Cores</span>
                    <span className="text-gray-900 font-semibold">{system.cpu_cores}</span>
                  </div>
                )}
                {system.ram_total_gb && (
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-gray-500">RAM</span>
                    <span className="text-gray-900 font-semibold">{system.ram_total_gb} GB</span>
                  </div>
                )}
                {system.disk_total_gb && (
                  <div className="flex items-center justify-between text-xs">
                    <span className="text-gray-500">Disk</span>
                    <span className="text-gray-900 font-semibold">{system.disk_total_gb} GB</span>
                  </div>
                )}
              </div>

              {/* View Details Link */}
              <div className="mt-4 pt-4 border-t border-gray-100">
                <div className="flex items-center justify-between text-sm text-primary-600 group-hover:text-primary-700">
                  <span className="font-medium">View Details</span>
                  <Activity className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Toast */}
      <Toast toasts={toasts} removeToast={removeToast} />
    </div>
  )
}
