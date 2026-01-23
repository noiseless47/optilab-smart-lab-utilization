import { useEffect, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { ArrowLeft, Filter, CheckCircle, AlertTriangle, XCircle, Clock, Trash2, CheckCheck } from 'lucide-react'
import Loading from '../components/Loading'
import ConfirmDialog from '../components/ConfirmDialog'
import api from '../lib/api'

interface MaintenanceLog {
  maintainence_id: number
  system_id: number
  hostname: string
  date_at: string
  severity: 'low' | 'medium' | 'high' | 'critical'
  message: string
  isACK: boolean
  ACKat: string | null
  ACKby: string | null
  resolved_at: string | null
}

export default function MaintenanceLogs() {
  const { deptId } = useParams()
  const navigate = useNavigate()
  const [loading, setLoading] = useState(true)
  const [logs, setLogs] = useState<MaintenanceLog[]>([])
  const [filteredLogs, setFilteredLogs] = useState<MaintenanceLog[]>([])
  const [departmentName, setDepartmentName] = useState('')
  const [selectedLogIds, setSelectedLogIds] = useState<number[]>([])
  const [showDeleteDialog, setShowDeleteDialog] = useState(false)
  const [showResolveDialog, setShowResolveDialog] = useState(false)
  const [processingBulk, setProcessingBulk] = useState(false)
  
  // Filters
  const [statusFilter, setStatusFilter] = useState<'all' | 'unresolved' | 'resolved'>('all')
  const [ackFilter, setAckFilter] = useState<'all' | 'acknowledged' | 'unacknowledged'>('all')
  const [severityFilter, setSeverityFilter] = useState<'all' | 'low' | 'medium' | 'high' | 'critical'>('all')

  useEffect(() => {
    fetchMaintenanceLogs()
  }, [deptId])

  useEffect(() => {
    applyFilters()
  }, [logs, statusFilter, ackFilter, severityFilter])

  const fetchMaintenanceLogs = async () => {
    try {
      setLoading(true)
      const [deptRes, logsRes] = await Promise.all([
        api.get(`/departments/${deptId}`),
        api.get(`/departments/${deptId}/maintenance`)
      ])
      setDepartmentName(deptRes.data.dept_name)
      setLogs(logsRes.data)
    } catch (error) {
      console.error('Failed to fetch maintenance logs:', error)
    } finally {
      setLoading(false)
    }
  }

  const applyFilters = () => {
    let filtered = [...logs]

    // Status filter
    if (statusFilter === 'resolved') {
      filtered = filtered.filter(log => log.resolved_at !== null)
    } else if (statusFilter === 'unresolved') {
      filtered = filtered.filter(log => log.resolved_at === null)
    }

    // Acknowledgment filter
    if (ackFilter === 'acknowledged') {
      filtered = filtered.filter(log => log.isACK)
    } else if (ackFilter === 'unacknowledged') {
      filtered = filtered.filter(log => !log.isACK)
    }

    // Severity filter
    if (severityFilter !== 'all') {
      filtered = filtered.filter(log => log.severity === severityFilter)
    }

    setFilteredLogs(filtered)
  }

  const getSeverityColor = (severity: string) => {
    const colors = {
      low: 'bg-blue-100 text-blue-800 border-blue-200',
      medium: 'bg-yellow-100 text-yellow-800 border-yellow-200',
      high: 'bg-orange-100 text-orange-800 border-orange-200',
      critical: 'bg-red-100 text-red-800 border-red-200'
    }
    return colors[severity as keyof typeof colors] || colors.low
  }

  const getSeverityIcon = (severity: string) => {
    const icons = {
      low: <CheckCircle className="w-4 h-4" />,
      medium: <Clock className="w-4 h-4" />,
      high: <AlertTriangle className="w-4 h-4" />,
      critical: <XCircle className="w-4 h-4" />
    }
    return icons[severity as keyof typeof icons] || icons.low
  }

  const toggleSelectLog = (logId: number) => {
    setSelectedLogIds(prev =>
      prev.includes(logId) ? prev.filter(id => id !== logId) : [...prev, logId]
    )
  }

  const toggleSelectAll = () => {
    if (selectedLogIds.length === filteredLogs.length) {
      setSelectedLogIds([])
    } else {
      setSelectedLogIds(filteredLogs.map(log => log.maintainence_id))
    }
  }

  const handleBulkResolve = async () => {
    try {
      setProcessingBulk(true)
      const resolvePromises = selectedLogIds.map(async (logId) => {
        const log = logs.find(l => l.maintainence_id === logId)
        if (!log) return
        return api.put(
          `/departments/${deptId}/labs/${log.lab_id}/maintenance/${logId}`,
          { resolved_at: new Date().toISOString() }
        )
      })
      await Promise.all(resolvePromises)
      setShowResolveDialog(false)
      setSelectedLogIds([])
      fetchMaintenanceLogs()
    } catch (error) {
      console.error('Failed to resolve logs:', error)
    } finally {
      setProcessingBulk(false)
    }
  }

  const handleBulkDelete = async () => {
    try {
      setProcessingBulk(true)
      const deletePromises = selectedLogIds.map(async (logId) => {
        const log = logs.find(l => l.maintainence_id === logId)
        if (!log) return
        return api.delete(
          `/departments/${deptId}/labs/${log.lab_id}/maintenance/${logId}`
        )
      })
      await Promise.all(deletePromises)
      setShowDeleteDialog(false)
      setSelectedLogIds([])
      fetchMaintenanceLogs()
    } catch (error) {
      console.error('Failed to delete logs:', error)
    } finally {
      setProcessingBulk(false)
    }
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <Loading text="Loading maintenance logs..." />
      </div>
    )
  }

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      {/* Header */}
      <div className="mb-8">
        <button
          onClick={() => navigate(`/departments/${deptId}`)}
          className="flex items-center text-gray-600 hover:text-gray-900 mb-4"
        >
          <ArrowLeft className="w-5 h-5 mr-2" />
          Back to {departmentName}
        </button>
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-4xl font-bold text-gray-900 mb-2">Maintenance Logs</h1>
            <p className="text-gray-600">
              Showing {filteredLogs.length} of {logs.length} maintenance logs
            </p>
          </div>
          {selectedLogIds.length > 0 && (
            <div className="flex items-center gap-3">
              <span className="text-sm text-gray-600">{selectedLogIds.length} selected</span>
              <button
                onClick={() => setShowResolveDialog(true)}
                className="btn-primary flex items-center gap-2"
              >
                <CheckCheck className="w-4 h-4" />
                Mark as Resolved
              </button>
              <button
                onClick={() => setShowDeleteDialog(true)}
                className="btn-secondary flex items-center gap-2 bg-red-50 text-red-700 hover:bg-red-100"
              >
                <Trash2 className="w-4 h-4" />
                Delete
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Filters */}
      <div className="card p-6 mb-8">
        <div className="flex items-center justify-between mb-4">
          <div className="flex items-center">
            <Filter className="w-5 h-5 text-gray-600 mr-2" />
            <h2 className="text-lg font-semibold text-gray-900">Filters</h2>
          </div>
          {filteredLogs.length > 0 && (
            <button
              onClick={toggleSelectAll}
              className="text-sm text-purple-600 hover:text-purple-700 font-medium"
            >
              {selectedLogIds.length === filteredLogs.length ? 'Deselect All' : 'Select All'}
            </button>
          )}
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Status Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Status</label>
            <select
              value={statusFilter}
              onChange={(e) => setStatusFilter(e.target.value as any)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            >
              <option value="all">All</option>
              <option value="unresolved">Unresolved</option>
              <option value="resolved">Resolved</option>
            </select>
          </div>

          {/* Acknowledgment Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Acknowledgment</label>
            <select
              value={ackFilter}
              onChange={(e) => setAckFilter(e.target.value as any)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            >
              <option value="all">All</option>
              <option value="acknowledged">Acknowledged</option>
              <option value="unacknowledged">Unacknowledged</option>
            </select>
          </div>

          {/* Severity Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">Severity</label>
            <select
              value={severityFilter}
              onChange={(e) => setSeverityFilter(e.target.value as any)}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            >
              <option value="all">All</option>
              <option value="low">Low</option>
              <option value="medium">Medium</option>
              <option value="high">High</option>
              <option value="critical">Critical</option>
            </select>
          </div>
        </div>
      </div>

      {/* Logs List */}
      {filteredLogs.length === 0 ? (
        <div className="card p-12 text-center">
          <p className="text-gray-500">No maintenance logs match the selected filters</p>
        </div>
      ) : (
        <div className="space-y-4">
          {filteredLogs.map((log) => (
            <div
              key={log.maintainence_id}
              className={`card p-6 hover:shadow-lg transition-shadow ${
                selectedLogIds.includes(log.maintainence_id) ? 'ring-2 ring-purple-500' : ''
              }`}
            >
              <div className="flex items-start gap-4">
                <input
                  type="checkbox"
                  checked={selectedLogIds.includes(log.maintainence_id)}
                  onChange={() => toggleSelectLog(log.maintainence_id)}
                  className="mt-1 w-5 h-5 text-purple-600 rounded focus:ring-purple-500"
                />
                <div className="flex-1">
                  <div className="flex items-center gap-3 mb-2">
                    <span className={`px-3 py-1 rounded-full text-sm font-medium border flex items-center gap-1 ${getSeverityColor(log.severity)}`}>
                      {getSeverityIcon(log.severity)}
                      {log.severity.toUpperCase()}
                    </span>
                    <span className="font-semibold text-gray-900">{log.hostname}</span>
                    {log.isACK && (
                      <span className="px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs">
                        Acknowledged
                      </span>
                    )}
                    {log.resolved_at && (
                      <span className="px-2 py-1 bg-green-100 text-green-700 rounded text-xs">
                        Resolved
                      </span>
                    )}
                  </div>
                  <p className="text-gray-700 mb-3">{log.message}</p>
                  <div className="flex items-center gap-6 text-sm text-gray-500">
                    <span>Reported: {new Date(log.date_at).toLocaleString()}</span>
                    {log.ACKat && <span>Acknowledged: {new Date(log.ACKat).toLocaleString()}</span>}
                    {log.resolved_at && <span>Resolved: {new Date(log.resolved_at).toLocaleString()}</span>}
                  </div>
                </div>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Delete Confirmation Dialog */}
      <ConfirmDialog
        isOpen={showDeleteDialog}
        onClose={() => setShowDeleteDialog(false)}
        onConfirm={handleBulkDelete}
        title="Delete Maintenance Logs"
        message={`Are you sure you want to delete ${selectedLogIds.length} maintenance log(s)? This action cannot be undone.`}
        confirmText="Delete"
        cancelText="Cancel"
        isDestructive
        isProcessing={processingBulk}
      />

      {/* Resolve Confirmation Dialog */}
      <ConfirmDialog
        isOpen={showResolveDialog}
        onClose={() => setShowResolveDialog(false)}
        onConfirm={handleBulkResolve}
        title="Mark as Resolved"
        message={`Mark ${selectedLogIds.length} maintenance log(s) as resolved?`}
        confirmText="Mark as Resolved"
        cancelText="Cancel"
        isProcessing={processingBulk}
      />
    </div>
  )
}
