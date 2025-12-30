import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Building2, Plus, Trash2, ArrowRight } from 'lucide-react'
import Modal from '../components/Modal'
import Toast, { ToastMessage } from '../components/Toast'
import ConfirmDialog from '../components/ConfirmDialog'
import Loading from '../components/Loading'
import api from '../lib/api'

interface Department {
  dept_id: number
  dept_name: string
  dept_code: string
  vlan_id?: string
  subnet_cidr?: string
  description?: string
  hod_id?: number
}

export default function Departments() {
  const navigate = useNavigate()
  const [departments, setDepartments] = useState<Department[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [showCreateModal, setShowCreateModal] = useState(false)
  const [showDeleteDialog, setShowDeleteDialog] = useState(false)
  const [selectedDept, setSelectedDept] = useState<Department | null>(null)
  const [toasts, setToasts] = useState<ToastMessage[]>([])
  
  const [formData, setFormData] = useState({
    dept_name: '',
    dept_code: '',
    vlan_id: '',
    subnet_cidr: '',
    description: '',
  })

  const addToast = (message: string, type: 'success' | 'error' | 'info' | 'warning') => {
    const id = Date.now().toString()
    setToasts(prev => [...prev, { id, message, type }])
  }

  const removeToast = (id: string) => {
    setToasts(prev => prev.filter(t => t.id !== id))
  }

  useEffect(() => {
    fetchDepartments()
  }, [])

  const fetchDepartments = async () => {
    try {
      setLoading(true)
      setError(null)
      const response = await api.get('/departments')
      setDepartments(response.data)
    } catch (err: any) {
      console.error('Failed to fetch departments:', err)
      setError(err.response?.data?.error || 'Failed to load departments')
      addToast('Failed to load departments', 'error')
    } finally {
      setLoading(false)
    }
  }

  const handleCreate = async () => {
    if (!formData.dept_name.trim() || !formData.dept_code.trim()) {
      addToast('Department name and code are required', 'error')
      return
    }

    try {
      await api.post('/departments', {
        name: formData.dept_name,
        code: formData.dept_code,
        vlan: formData.vlan_id || null,
        subnet: formData.subnet_cidr || null,
        description: formData.description || null,
        hodID: null,
      })
      addToast('Department created successfully', 'success')
      setShowCreateModal(false)
      setFormData({ dept_name: '', dept_code: '', vlan_id: '', subnet_cidr: '', description: '' })
      fetchDepartments()
    } catch (error) {
      console.error('Failed to create department:', error)
      addToast('Failed to create department', 'error')
    }
  }

  const handleDelete = async () => {
    if (!selectedDept) return

    try {
      await api.delete(`/departments/${selectedDept.dept_id}`)
      addToast('Department deleted successfully', 'success')
      setShowDeleteDialog(false)
      setSelectedDept(null)
      fetchDepartments()
    } catch (error) {
      console.error('Failed to delete department:', error)
      addToast('Failed to delete department', 'error')
    }
  }

  const openDeleteDialog = (dept: Department) => {
    setSelectedDept(dept)
    setShowDeleteDialog(true)
  }

  const handleDepartmentClick = (deptId: number) => {
    navigate(`/departments/${deptId}`)
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Departments</h1>
          <p className="text-gray-600">Manage departments and their resources</p>
        </div>
        <Loading text="Loading departments..." />
      </div>
    )
  }

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="flex items-center justify-between mb-8">
        <div>
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Departments</h1>
          <p className="text-gray-600">Manage departments and their resources</p>
        </div>
        <button
          onClick={() => setShowCreateModal(true)}
          className="btn-primary flex items-center space-x-2"
        >
          <Plus className="w-5 h-5" />
          <span>Add Department</span>
        </button>
      </div>

      {departments.length === 0 ? (
        <div className="card p-12 text-center">
          <Building2 className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-xl font-semibold text-gray-900 mb-2">No Departments Yet</h3>
          <p className="text-gray-600 mb-6">Get started by creating your first department</p>
          <button
            onClick={() => setShowCreateModal(true)}
            className="btn-primary inline-flex items-center space-x-2"
          >
            <Plus className="w-5 h-5" />
            <span>Add Department</span>
          </button>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {departments.map((dept) => (
            <div
              key={dept.dept_id}
              className="card p-6 hover:shadow-xl transition-all duration-200 cursor-pointer group relative"
            >
              <div onClick={() => handleDepartmentClick(dept.dept_id)}>
                <div className="flex items-start justify-between mb-4">
                  <div className="w-12 h-12 bg-gradient-to-br from-primary-500 to-primary-600 rounded-lg flex items-center justify-center">
                    <Building2 className="w-6 h-6 text-white" />
                  </div>
                  <ArrowRight className="w-5 h-5 text-gray-400 group-hover:text-primary-600 group-hover:translate-x-1 transition-all" />
                </div>
                <h3 className="text-xl font-bold text-gray-900 mb-1">{dept.dept_name}</h3>
                <p className="text-sm text-gray-500 mb-4">Code: {dept.dept_code}</p>
                {dept.description && (
                  <p className="text-sm text-gray-600 mb-4 line-clamp-2">{dept.description}</p>
                )}
                {dept.subnet_cidr && (
                  <div className="text-xs text-gray-500 mb-2">
                    <span className="font-medium">Subnet:</span> {dept.subnet_cidr}
                  </div>
                )}
                {dept.vlan_id && (
                  <div className="text-xs text-gray-500">
                    <span className="font-medium">VLAN:</span> {dept.vlan_id}
                  </div>
                )}
              </div>
              <button
                onClick={(e) => {
                  e.stopPropagation()
                  openDeleteDialog(dept)
                }}
                className="absolute top-4 right-4 p-2 text-gray-400 hover:text-red-600 hover:bg-red-50 rounded-lg transition-all opacity-0 group-hover:opacity-100"
              >
                <Trash2 className="w-4 h-4" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Create Department Modal */}
      <Modal
        isOpen={showCreateModal}
        onClose={() => {
          setShowCreateModal(false)
          setFormData({ dept_name: '', dept_code: '', vlan_id: '', subnet_cidr: '', description: '' })
        }}
        title="Add New Department"
        size="md"
      >
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Department Name <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={formData.dept_name}
              onChange={(e) => setFormData({ ...formData, dept_name: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="e.g., Information Science & Engineering"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Department Code <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={formData.dept_code}
              onChange={(e) => setFormData({ ...formData, dept_code: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="e.g., ISE"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">VLAN ID</label>
            <input
              type="text"
              value={formData.vlan_id}
              onChange={(e) => setFormData({ ...formData, vlan_id: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="e.g., VLAN100"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Subnet CIDR</label>
            <input
              type="text"
              value={formData.subnet_cidr}
              onChange={(e) => setFormData({ ...formData, subnet_cidr: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              placeholder="e.g., 10.30.0.0/16"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Description</label>
            <textarea
              value={formData.description}
              onChange={(e) => setFormData({ ...formData, description: e.target.value })}
              className="w-full px-4 py-2.5 border border-gray-300 rounded-lg focus:ring-2 focus:ring-primary-500 focus:border-primary-500"
              rows={3}
              placeholder="Brief description of the department"
            />
          </div>
          <div className="flex justify-end space-x-3 pt-4">
            <button
              onClick={() => {
                setShowCreateModal(false)
                setFormData({ dept_name: '', dept_code: '', vlan_id: '', subnet_cidr: '', description: '' })
              }}
              className="btn-secondary"
            >
              Cancel
            </button>
            <button onClick={handleCreate} className="btn-primary">
              Create Department
            </button>
          </div>
        </div>
      </Modal>

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        isOpen={showDeleteDialog}
        onClose={() => {
          setShowDeleteDialog(false)
          setSelectedDept(null)
        }}
        onConfirm={handleDelete}
        title="Delete Department"
        message={`Are you sure you want to delete "${selectedDept?.dept_name}"? This will also delete all associated labs and systems.`}
        confirmText="Delete"
        variant="danger"
      />

      {/* Toast Notification */}
      <Toast toasts={toasts} removeToast={removeToast} />
    </div>
  )
}
