import { useState, useEffect } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, FlaskConical, Users, Wrench, Plus, Trash2, ArrowRight } from 'lucide-react'
import Modal from '../components/Modal'
import Toast, { ToastMessage } from '../components/Toast'
import ConfirmDialog from '../components/ConfirmDialog'
import Loading from '../components/Loading'
import api from '../lib/api'

interface Department {
  dept_id: number
  dept_name: string
  dept_code: string
  description?: string
}

interface Lab {
  lab_id: number
  lab_dept: number
  lab_number: number
}

interface LabAssistant {
  lab_assistant_id: number
  lab_assistant_name: string
  lab_assistant_email: string
  lab_assistant_dept: number
  lab_assigned?: number
}

interface MaintenanceLog {
  maintainence_id: number
  system_id: number
  date_at: string
  severity: string
  message: string
  is_acknowledged: boolean
  resolved_at?: string
}

export default function DepartmentDetail() {
  const { deptId } = useParams<{ deptId: string }>()
  const navigate = useNavigate()
  
  const [department, setDepartment] = useState<Department | null>(null)
  const [labs, setLabs] = useState<Lab[]>([])
  const [labAssistants, setLabAssistants] = useState<LabAssistant[]>([])
  const [maintenanceLogs, setMaintenanceLogs] = useState<MaintenanceLog[]>([])
  const [loading, setLoading] = useState(true)
  
  const [showLabModal, setShowLabModal] = useState(false)
  const [showAssistantModal, setShowAssistantModal] = useState(false)
  const [showDeleteLabDialog, setShowDeleteLabDialog] = useState(false)
  const [showDeleteAssistantDialog, setShowDeleteAssistantDialog] = useState(false)
  const [selectedLab, setSelectedLab] = useState<Lab | null>(null)
  const [selectedAssistant, setSelectedAssistant] = useState<LabAssistant | null>(null)
  const [toasts, setToasts] = useState<ToastMessage[]>([])
  
  const [labNumber, setLabNumber] = useState('')
  const [assistantForm, setAssistantForm] = useState({
    name: '',
    email: '',
  })

  const addToast = (message: string, type: 'success' | 'error' | 'info' | 'warning') => {
    const id = Date.now().toString()
    setToasts(prev => [...prev, { id, message, type }])
  }

  const removeToast = (id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id))
  }

  useEffect(() => {
    if (deptId) {
      fetchDepartmentData()
    }
  }, [deptId])

  const fetchDepartmentData = async () => {
    try {
      setLoading(true)
      const [deptRes, labsRes, assistantsRes] = await Promise.all([
        api.get(`/departments/${deptId}`),
        api.get(`/departments/${deptId}/labs`),
        api.get(`/departments/${deptId}/faculty`),
      ])
      
      setDepartment(deptRes.data)
      setLabs(labsRes.data)
      setLabAssistants(assistantsRes.data)
      
      // Fetch maintenance logs for all labs in this department
      const logsPromises = labsRes.data.map((lab: Lab) =>
        api.get(`/departments/${deptId}/labs/${lab.lab_id}/maintenance`)
          .then(res => res.data)
          .catch(() => [])
      )
      const allLogs = await Promise.all(logsPromises)
      setMaintenanceLogs(allLogs.flat())
    } catch (error) {
      console.error('Failed to fetch department data:', error)
      addToast('Failed to load department data', 'error')
    } finally {
      setLoading(false)
    }
  }

  const handleCreateLab = async () => {
    if (!labNumber.trim()) {
      addToast('Lab number is required', 'error')
      return
    }

    try {
      await api.post(`/api/departments/${deptId}/labs`, { number: parseInt(labNumber) })
      addToast('Lab created successfully', 'success')
      setShowLabModal(false)
      setLabNumber('')
      fetchDepartmentData()
    } catch (error) {
      console.error('Failed to create lab:', error)
      addToast('Failed to create lab', 'error')
    }
  }

  const handleDeleteLab = async () => {
    if (!selectedLab) return

    try {
      await api.delete(`/api/departments/${deptId}/labs/${selectedLab.lab_id}`)
      addToast('Lab deleted successfully', 'success')
      setShowDeleteLabDialog(false)
      setSelectedLab(null)
      fetchDepartmentData()
    } catch (error) {
      console.error('Failed to delete lab:', error)
      addToast('Failed to delete lab', 'error')
    }
  }

  const handleCreateAssistant = async () => {
    if (!assistantForm.name.trim() || !assistantForm.email.trim()) {
      addToast('Name and email are required', 'error')
      return
    }

    try {
      await api.post(`/departments/${deptId}/faculty`, {
        name: assistantForm.name,
        email: assistantForm.email,
      })
      addToast('Lab assistant added successfully', 'success')
      setShowAssistantModal(false)
      setAssistantForm({ name: '', email: '' })
      fetchDepartmentData()
    } catch (error) {
      console.error('Failed to add lab assistant:', error)
      addToast('Failed to add lab assistant', 'error')
    }
  }

  const handleDeleteAssistant = async () => {
    if (!selectedAssistant) return

    try {
      await api.delete(`/departments/${deptId}/faculty/${selectedAssistant.lab_assistant_id}`)
      addToast('Lab assistant deleted successfully', 'success')
      setShowDeleteAssistantDialog(false)
      setSelectedAssistant(null)
      fetchDepartmentData()
    } catch (error) {
      console.error('Failed to delete lab assistant:', error)
      addToast('Failed to delete lab assistant', 'error')
    }
  }

  const openDeleteLabDialog = (lab: Lab) => {
    setSelectedLab(lab)
    setShowDeleteLabDialog(true)
  }

  const openDeleteAssistantDialog = (assistant: LabAssistant) => {
    setSelectedAssistant(assistant)
    setShowDeleteAssistantDialog(true)
  }

  const handleLabClick = (labId: number) => {
    navigate(`/departments/${deptId}/labs/${labId}`)
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <Loading text="Loading department..." />
      </div>
    )
  }

  if (!department) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="card p-12 text-center">
          <h3 className="text-xl font-semibold text-gray-900 mb-2">Department Not Found</h3>
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
          onClick={() => navigate('/departments')}
          className="flex items-center space-x-2 text-gray-600 hover:text-gray-900 mb-4"
        >
          <ArrowLeft className="w-4 h-4" />
          <span>Back to Departments</span>
        </button>
        <h1 className="text-4xl font-bold text-gray-900 mb-2">{department.dept_name}</h1>
        <p className="text-gray-600">Code: {department.dept_code}</p>
      </div>

      {/* Labs Section */}
      <div className="mb-12">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center space-x-3">
            <FlaskConical className="w-6 h-6 text-primary-600" />
            <h2 className="text-2xl font-bold text-gray-900">Labs</h2>
          </div>
          <button
            onClick={() => setShowLabModal(true)}
            className="btn-primary flex items-center space-x-2"
          >
            <Plus className="w-4 h-4" />
            <span>Add Lab</span>
          </button>
        </div>
        
        {labs.length === 0 ? (
          <div className="card p-8 text-center">
            <FlaskConical className="w-12 h-12 text-gray-300 mx-auto mb-3" />
            <p className="text-gray-600">No labs yet. Add your first lab to get started.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {labs.map((lab) => (
              <div
                key={lab.lab_id}
                className="card p-6 hover:shadow-lg transition-all cursor-pointer group relative"
              >
                <div onClick={() => handleLabClick(lab.lab_id)}>
                  <div className="flex items-center justify-between mb-2">
                    <div className="w-10 h-10 bg-primary-100 rounded-lg flex items-center justify-center">
                      <FlaskConical className="w-5 h-5 text-primary-600" />
                    </div>
                    <ArrowRight className="w-4 h-4 text-gray-400 group-hover:text-primary-600 group-hover:translate-x-1 transition-all" />
                  </div>
                  <h3 className="text-lg font-bold text-gray-900">Lab {lab.lab_number}</h3>
                  <p className="text-sm text-gray-500">ID: {lab.lab_id}</p>
                </div>
                <button
                  onClick={(e) => {
                    e.stopPropagation()
                    openDeleteLabDialog(lab)
                  }}
                  className="absolute top-3 right-3 p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-all opacity-0 group-hover:opacity-100"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Lab Assistants Section */}
      <div className="mb-12">
        <div className="flex items-center justify-between mb-6">
          <div className="flex items-center space-x-3">
            <Users className="w-6 h-6 text-primary-600" />
            <h2 className="text-2xl font-bold text-gray-900">Lab Assistants</h2>
          </div>
          <button
            onClick={() => setShowAssistantModal(true)}
            className="btn-primary flex items-center space-x-2"
          >
            <Plus className="w-4 h-4" />
            <span>Add Assistant</span>
          </button>
        </div>
        
        {labAssistants.length === 0 ? (
          <div className="card p-8 text-center">
            <Users className="w-12 h-12 text-gray-300 mx-auto mb-3" />
            <p className="text-gray-600">No lab assistants yet.</p>
          </div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {labAssistants.map((assistant) => (
              <div key={assistant.lab_assistant_id} className="card p-4 group relative">
                <div className="flex items-start space-x-3">
                  <div className="w-10 h-10 bg-primary-100 rounded-full flex items-center justify-center flex-shrink-0">
                    <Users className="w-5 h-5 text-primary-600" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <h3 className="font-semibold text-gray-900">{assistant.lab_assistant_name}</h3>
                    <p className="text-sm text-gray-600 truncate">{assistant.lab_assistant_email}</p>
                  </div>
                </div>
                <button
                  onClick={() => openDeleteAssistantDialog(assistant)}
                  className="absolute top-3 right-3 p-1.5 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded transition-all opacity-0 group-hover:opacity-100"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Maintenance Logs Section */}
      <div>
        <div className="flex items-center space-x-3 mb-6">
          <Wrench className="w-6 h-6 text-primary-600" />
          <h2 className="text-2xl font-bold text-gray-900">Maintenance Logs</h2>
        </div>
        
        {maintenanceLogs.length === 0 ? (
          <div className="card p-8 text-center">
            <Wrench className="w-12 h-12 text-gray-300 mx-auto mb-3" />
            <p className="text-gray-600">No maintenance logs yet.</p>
          </div>
        ) : (
          <div className="space-y-3">
            {maintenanceLogs.map((log) => (
              <div key={log.maintainence_id} className="card p-4">
                <div className="flex items-start justify-between">
                  <div className="flex-1">
                    <div className="flex items-center space-x-2 mb-2">
                      <span className={`px-2 py-1 text-xs font-semibold rounded-full ${
                        log.severity === 'critical' ? 'bg-red-100 text-red-700' :
                        log.severity === 'high' ? 'bg-orange-100 text-orange-700' :
                        log.severity === 'medium' ? 'bg-yellow-100 text-yellow-700' :
                        'bg-blue-100 text-blue-700'
                      }`}>
                        {log.severity}
                      </span>
                      {log.is_acknowledged && (
                        <span className="px-2 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-700">
                          Acknowledged
                        </span>
                      )}
                      {log.resolved_at && (
                        <span className="px-2 py-1 text-xs font-semibold rounded-full bg-gray-100 text-gray-700">
                          Resolved
                        </span>
                      )}
                    </div>
                    <p className="text-gray-900 font-medium mb-1">{log.message}</p>
                    <div className="text-sm text-gray-500">
                      System ID: {log.system_id} • {new Date(log.date_at).toLocaleDateString()}
                    </div>
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Create Lab Modal */}
      <Modal
        isOpen={showLabModal}
        onClose={() => {
          setShowLabModal(false)
          setLabNumber('')
        }}
        title="Add New Lab"
        size="sm"
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Lab Number <span className="text-red-500">*</span>
            </label>
            <input
              type="number"
              value={labNumber}
              onChange={(e) => setLabNumber(e.target.value)}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="e.g., 1, 2, 3"
            />
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button
              onClick={() => {
                setShowLabModal(false)
                setLabNumber('')
              }}
              className="btn-secondary"
            >
              Cancel
            </button>
            <button onClick={handleCreateLab} className="btn-primary">
              Create Lab
            </button>
          </div>
        </div>
      </Modal>

      {/* Create Assistant Modal */}
      <Modal
        isOpen={showAssistantModal}
        onClose={() => {
          setShowAssistantModal(false)
          setAssistantForm({ name: '', email: '' })
        }}
        title="Add Lab Assistant"
        size="md"
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Name <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={assistantForm.name}
              onChange={(e) => setAssistantForm({ ...assistantForm, name: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="Full name"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Email <span className="text-red-500">*</span>
            </label>
            <input
              type="email"
              value={assistantForm.email}
              onChange={(e) => setAssistantForm({ ...assistantForm, email: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="email@example.com"
            />
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button
              onClick={() => {
                setShowAssistantModal(false)
                setAssistantForm({ name: '', email: '' })
              }}
              className="btn-secondary"
            >
              Cancel
            </button>
            <button onClick={handleCreateAssistant} className="btn-primary">
              Add Assistant
            </button>
          </div>
        </div>
      </Modal>

      {/* Delete Dialogs */}
      <ConfirmDialog
        isOpen={showDeleteLabDialog}
        onClose={() => {
          setShowDeleteLabDialog(false)
          setSelectedLab(null)
        }}
        onConfirm={handleDeleteLab}
        title="Delete Lab"
        message={`Are you sure you want to delete Lab ${selectedLab?.lab_number}? This will also delete all systems in this lab.`}
        confirmText="Delete"
        variant="danger"
      />

      <ConfirmDialog
        isOpen={showDeleteAssistantDialog}
        onClose={() => {
          setShowDeleteAssistantDialog(false)
          setSelectedAssistant(null)
        }}
        onConfirm={handleDeleteAssistant}
        title="Delete Lab Assistant"
        message={`Are you sure you want to remove ${selectedAssistant?.lab_assistant_name}?`}
        confirmText="Delete"
        variant="danger"
      />

      {/* Toast */}
      <Toast toasts={toasts} removeToast={removeToast} />
    </div>
  )
}
