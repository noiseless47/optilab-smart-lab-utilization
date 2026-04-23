import { useState, useMemo, useEffect } from 'react'
import { Search, Filter, Server, X, ChevronDown, ArrowUpDown, Check } from 'lucide-react'
import Modal from '../components/Modal'
import Loading from '../components/Loading'
import api from '../lib/api'

type SortOption = 'name' | 'status' | 'department' | 'lab'

interface SystemRow {
  system_id: number
  system_number?: number | null
  hostname: string
  ip_address: string
  mac_address?: string | null
  lab_id?: number | null
  dept_id?: number | null
  status: string
  cpu_model?: string | null
  cpu_cores?: number | null
  ram_total_gb?: number | null
  disk_total_gb?: number | null
  gpu_model?: string | null
  gpu_memory?: number | null
  ssh_port?: number | null
  created_at?: string | null
  updated_at?: string | null
}

interface Department {
  dept_id: number
  dept_name: string
  dept_code?: string
}

interface Lab {
  lab_id: number
  lab_number: number
  lab_dept: number
}

export default function Systems() {
  const [searchQuery, setSearchQuery] = useState('')
  const [showFilters, setShowFilters] = useState(false)
  const [showSort, setShowSort] = useState(false)
  const [sortBy, setSortBy] = useState<SortOption>('name')

  const [selectedSystem, setSelectedSystem] = useState<SystemRow | null>(null)
  const [statusFilters, setStatusFilters] = useState<string[]>([])
  const [labFilters, setLabFilters] = useState<string[]>([])
  const [departmentFilters, setDepartmentFilters] = useState<string[]>([])

  const [systems, setSystems] = useState<SystemRow[]>([])
  const [discoveredSystems, setDiscoveredSystems] = useState<SystemRow[]>([])
  const [departments, setDepartments] = useState<Department[]>([])
  const [labsByDept, setLabsByDept] = useState<Record<number, Lab[]>>({})

  const [assignTarget, setAssignTarget] = useState<SystemRow | null>(null)
  const [assignDeptId, setAssignDeptId] = useState<number | ''>('')
  const [assignLabId, setAssignLabId] = useState<number | ''>('')
  const [assignLoading, setAssignLoading] = useState(false)

  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [actionMessage, setActionMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  useEffect(() => {
    fetchSystems()
  }, [])

  const getDeptLabel = (deptId?: number | null) => {
    if (!deptId) return 'Unknown'
    const dept = departments.find((d) => d.dept_id === deptId)
    if (!dept) return `Dept ${deptId}`
    return dept.dept_code || dept.dept_name
  }

  const getLabLabel = (system: { lab_id?: number | null; dept_id?: number | null }) => {
    if (!system.lab_id) return 'Unassigned'
    const deptId = system.dept_id || 0
    const labs = labsByDept[deptId] || []
    const lab = labs.find((item) => item.lab_id === system.lab_id)
    if (!lab) return `Lab ${system.lab_id}`
    return `${getDeptLabel(deptId)} Lab ${lab.lab_number}`
  }

  const formatDateTime = (value?: string | null) => {
    if (!value) return 'N/A'
    const dt = new Date(value)
    if (Number.isNaN(dt.getTime())) return value
    return dt.toLocaleString()
  }

  const fetchSystems = async () => {
    try {
      setLoading(true)
      setError(null)
      setActionMessage(null)

      const [systemsRes, discoveredRes, departmentsRes] = await Promise.all([
        api.get('/systems/all'),
        api.get('/systems/discovered'),
        api.get('/departments'),
      ])

      const systemsData = Array.isArray(systemsRes.data) ? systemsRes.data : []
      const discoveredData = Array.isArray(discoveredRes.data) ? discoveredRes.data : []
      const departmentsData = Array.isArray(departmentsRes.data) ? departmentsRes.data : []
      setDepartments(departmentsData)

      const deptLabPairs = await Promise.all(
        departmentsData.map(async (dept: Department) => {
          try {
            const labsRes = await api.get(`/departments/${dept.dept_id}/labs`)
            return [dept.dept_id, Array.isArray(labsRes.data) ? labsRes.data : []] as [number, Lab[]]
          } catch {
            return [dept.dept_id, []] as [number, Lab[]]
          }
        })
      )

      const labMap: Record<number, Lab[]> = {}
      deptLabPairs.forEach(([deptId, labs]) => {
        labMap[deptId] = labs
      })
      setLabsByDept(labMap)

      setSystems(systemsData)
      setDiscoveredSystems(discoveredData)
    } catch (fetchError: any) {
      console.error('Failed to fetch systems:', fetchError)
      setError(fetchError.response?.data?.error || 'Failed to load systems')
    } finally {
      setLoading(false)
    }
  }

  const schemaStatuses = useMemo(() => {
    const values = new Set<string>()
    systems.forEach((system) => {
      if (system.status) values.add(system.status)
    })
    return Array.from(values)
  }, [systems])

  const departmentOptions = useMemo(() => {
    const names = new Set<string>()
    systems.forEach((system) => names.add(getDeptLabel(system.dept_id)))
    return Array.from(names).sort((a, b) => a.localeCompare(b))
  }, [systems, departments])

  const labOptions = useMemo(() => {
    const labels = new Set<string>()
    systems.forEach((system) => labels.add(getLabLabel(system)))
    return Array.from(labels).sort((a, b) => a.localeCompare(b))
  }, [systems, departments, labsByDept])

  const visibleSystems = useMemo(() => {
    const query = searchQuery.trim().toLowerCase()

    return systems.filter((system) => {
      const deptLabel = getDeptLabel(system.dept_id)
      const labLabel = getLabLabel(system)

      const statusPass = statusFilters.length === 0 || statusFilters.includes(system.status)
      const deptPass = departmentFilters.length === 0 || departmentFilters.includes(deptLabel)
      const labPass = labFilters.length === 0 || labFilters.includes(labLabel)

      const searchPass =
        query.length === 0 ||
        system.hostname?.toLowerCase().includes(query) ||
        system.ip_address?.toLowerCase().includes(query) ||
        (system.mac_address || '').toLowerCase().includes(query) ||
        (system.cpu_model || '').toLowerCase().includes(query) ||
        (system.gpu_model || '').toLowerCase().includes(query) ||
        deptLabel.toLowerCase().includes(query) ||
        labLabel.toLowerCase().includes(query)

      return statusPass && deptPass && labPass && searchPass
    })
  }, [systems, searchQuery, statusFilters, departmentFilters, labFilters, departments, labsByDept])

  const sortedSystems = useMemo(() => {
    const list = [...visibleSystems]

    switch (sortBy) {
      case 'name':
        return list.sort((a, b) => a.hostname.localeCompare(b.hostname))
      case 'status':
        return list.sort((a, b) => a.status.localeCompare(b.status))
      case 'department':
        return list.sort((a, b) => getDeptLabel(a.dept_id).localeCompare(getDeptLabel(b.dept_id)))
      case 'lab':
        return list.sort((a, b) => getLabLabel(a).localeCompare(getLabLabel(b)))
      default:
        return list
    }
  }, [visibleSystems, sortBy, departments, labsByDept])

  const toggleStatusFilter = (status: string) => {
    setStatusFilters((prev) => (prev.includes(status) ? prev.filter((s) => s !== status) : [...prev, status]))
  }

  const toggleDepartmentFilter = (dept: string) => {
    setDepartmentFilters((prev) => (prev.includes(dept) ? prev.filter((d) => d !== dept) : [...prev, dept]))
  }

  const toggleLabFilter = (lab: string) => {
    setLabFilters((prev) => (prev.includes(lab) ? prev.filter((l) => l !== lab) : [...prev, lab]))
  }

  const clearAllFilters = () => {
    setStatusFilters([])
    setDepartmentFilters([])
    setLabFilters([])
  }

  const handleSortChange = (option: SortOption) => {
    setSortBy(option)
    setShowSort(false)
  }

  const openAssignModal = (system: SystemRow) => {
    setAssignTarget(system)
    const initialDept = system.dept_id || departments[0]?.dept_id || ''
    setAssignDeptId(initialDept)

    if (initialDept) {
      const labs = labsByDept[initialDept] || []
      setAssignLabId(labs[0]?.lab_id || '')
    } else {
      setAssignLabId('')
    }
  }

  const handleAssign = async () => {
    if (!assignTarget || !assignLabId) {
      setActionMessage({ type: 'error', text: 'Please select a lab before assigning.' })
      return
    }

    try {
      setAssignLoading(true)
      await api.patch(`/systems/${assignTarget.system_id}/assign-lab`, { lab_id: Number(assignLabId) })
      setActionMessage({ type: 'success', text: `${assignTarget.hostname} assigned successfully.` })
      setAssignTarget(null)
      await fetchSystems()
    } catch (assignError: any) {
      console.error('Failed to assign lab:', assignError)
      setActionMessage({
        type: 'error',
        text: assignError.response?.data?.error || 'Failed to assign discovered system to lab',
      })
    } finally {
      setAssignLoading(false)
    }
  }

  const assignDeptLabs = assignDeptId ? labsByDept[assignDeptId] || [] : []
  const activeFilterCount = statusFilters.length + departmentFilters.length + labFilters.length

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Systems</h1>
        <p className="text-gray-600">Static system inventory from the database</p>
      </div>

      {error && <div className="mb-6 rounded-lg border border-red-200 bg-red-50 p-4 text-red-700 text-sm font-medium">{error}</div>}

      {actionMessage && (
        <div
          className={`mb-6 rounded-lg p-4 text-sm font-medium ${
            actionMessage.type === 'success'
              ? 'border border-green-200 bg-green-50 text-green-700'
              : 'border border-red-200 bg-red-50 text-red-700'
          }`}
        >
          {actionMessage.text}
        </div>
      )}

      <div className="card mb-8 p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-2">Discovered Systems Queue</h2>
        <p className="text-sm text-gray-600 mb-4">Newly discovered systems appear here first. Assign each one to a lab.</p>

        {discoveredSystems.length === 0 ? (
          <div className="rounded-md border border-dashed border-gray-300 p-4 text-sm text-gray-500">No pending discovered systems.</div>
        ) : (
          <div className="space-y-3">
            {discoveredSystems.map((system) => (
              <div key={system.system_id} className="flex flex-col md:flex-row md:items-center md:justify-between gap-3 rounded-lg border border-gray-200 p-4">
                <div>
                  <div className="font-semibold text-gray-900">{system.hostname}</div>
                  <div className="text-sm text-gray-600">
                    {system.ip_address} | {getDeptLabel(system.dept_id)}
                  </div>
                </div>
                <button onClick={() => openAssignModal(system)} className="btn-primary">
                  Assign To Lab
                </button>
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="flex items-center space-x-4 mb-8">
        <div className="flex-1 relative">
          <Search className="absolute left-4 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input
            type="text"
            placeholder="Search by hostname, IP, MAC, CPU model, GPU model..."
            className="w-full pl-12 pr-4 py-3.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 placeholder:text-gray-400 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300 shadow-sm"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>

        <button onClick={() => setShowFilters(!showFilters)} className="btn-secondary flex items-center space-x-2 relative">
          <Filter className="w-4 h-4" />
          <span>Filters</span>
          {activeFilterCount > 0 && (
            <span className="absolute -top-2 -right-2 bg-primary-500 text-white text-xs font-bold rounded-full w-5 h-5 flex items-center justify-center">
              {activeFilterCount}
            </span>
          )}
        </button>

        <div className="relative">
          <button onClick={() => setShowSort(!showSort)} className="btn-secondary flex items-center space-x-2">
            <ArrowUpDown className="w-4 h-4" />
            <span>Sort</span>
          </button>
          {showSort && (
            <div className="absolute right-0 mt-2 w-64 bg-white rounded-lg shadow-xl border border-gray-200 py-2 z-50">
              <div className="px-4 py-2 border-b border-gray-100">
                <p className="text-xs font-semibold text-gray-500 uppercase">Sort By</p>
              </div>
              {[
                { value: 'name' as SortOption, label: 'Name (A-Z)' },
                { value: 'status' as SortOption, label: 'Status' },
                { value: 'department' as SortOption, label: 'Department' },
                { value: 'lab' as SortOption, label: 'Lab' },
              ].map((option) => (
                <button
                  key={option.value}
                  onClick={() => handleSortChange(option.value)}
                  className={`w-full px-4 py-2.5 text-left text-sm hover:bg-gray-50 transition-colors flex items-center justify-between group ${
                    sortBy === option.value ? 'bg-primary-50 text-primary-700' : 'text-gray-700'
                  }`}
                >
                  <span className="group-hover:text-gray-900">{option.label}</span>
                  {sortBy === option.value && <Check className="w-4 h-4 text-primary-600" />}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
        <div className="card p-6">
          <div className="text-sm text-gray-500 mb-1">Total Systems</div>
          <div className="text-3xl font-bold text-gray-900">{sortedSystems.length}</div>
        </div>
        <div className="card p-6">
          <div className="text-sm text-gray-500 mb-1">Active</div>
          <div className="text-3xl font-bold text-green-600">{sortedSystems.filter((s) => s.status === 'active').length}</div>
        </div>
        <div className="card p-6">
          <div className="text-sm text-gray-500 mb-1">Offline</div>
          <div className="text-3xl font-bold text-gray-600">{sortedSystems.filter((s) => s.status === 'offline').length}</div>
        </div>
        <div className="card p-6">
          <div className="text-sm text-gray-500 mb-1">Discovered</div>
          <div className="text-3xl font-bold text-blue-600">{discoveredSystems.length}</div>
        </div>
      </div>

      {showFilters && (
        <div className="card mb-6 overflow-hidden">
          <div className="bg-gray-50 px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <h3 className="font-semibold text-gray-900">Filter Systems</h3>
            <button onClick={() => setShowFilters(false)} className="text-gray-400 hover:text-gray-600">
              <X className="w-5 h-5" />
            </button>
          </div>

          <div className="p-6 space-y-6">
            <div>
              <h4 className="font-medium text-gray-900 mb-3 flex items-center justify-between">
                Status
                <ChevronDown className="w-4 h-4 text-gray-400" />
              </h4>
              <div className="space-y-2.5">
                {schemaStatuses.map((status) => (
                  <label key={status} className="flex items-center space-x-3 cursor-pointer group p-2 rounded-lg hover:bg-gray-50 transition-all">
                    <div className="relative">
                      <input
                        type="checkbox"
                        checked={statusFilters.includes(status)}
                        onChange={() => toggleStatusFilter(status)}
                        className="sr-only peer"
                      />
                      <div className="w-5 h-5 border-2 border-gray-300 rounded peer-checked:border-primary-500 peer-checked:bg-primary-500 transition-all duration-200 flex items-center justify-center group-hover:border-primary-400">
                        {statusFilters.includes(status) && <Check className="w-3.5 h-3.5 text-white" strokeWidth={3} />}
                      </div>
                    </div>
                    <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900 capitalize flex-1">{status}</span>
                  </label>
                ))}
              </div>
            </div>

            <div className="border-t border-gray-200"></div>

            <div>
              <h4 className="font-medium text-gray-900 mb-3 flex items-center justify-between">
                Department
                <ChevronDown className="w-4 h-4 text-gray-400" />
              </h4>
              <div className="space-y-2.5 max-h-52 overflow-y-auto pr-1">
                {departmentOptions.map((dept) => (
                  <label key={dept} className="flex items-center space-x-3 cursor-pointer group p-2 rounded-lg hover:bg-gray-50 transition-all">
                    <div className="relative">
                      <input
                        type="checkbox"
                        checked={departmentFilters.includes(dept)}
                        onChange={() => toggleDepartmentFilter(dept)}
                        className="sr-only peer"
                      />
                      <div className="w-5 h-5 border-2 border-gray-300 rounded peer-checked:border-primary-500 peer-checked:bg-primary-500 transition-all duration-200 flex items-center justify-center group-hover:border-primary-400">
                        {departmentFilters.includes(dept) && <Check className="w-3.5 h-3.5 text-white" strokeWidth={3} />}
                      </div>
                    </div>
                    <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900 flex-1">{dept}</span>
                  </label>
                ))}
              </div>
            </div>

            <div className="border-t border-gray-200"></div>

            <div>
              <h4 className="font-medium text-gray-900 mb-3 flex items-center justify-between">
                Lab
                <ChevronDown className="w-4 h-4 text-gray-400" />
              </h4>
              <div className="space-y-2.5 max-h-52 overflow-y-auto pr-1">
                {labOptions.map((lab) => (
                  <label key={lab} className="flex items-center space-x-3 cursor-pointer group p-2 rounded-lg hover:bg-gray-50 transition-all">
                    <div className="relative">
                      <input
                        type="checkbox"
                        checked={labFilters.includes(lab)}
                        onChange={() => toggleLabFilter(lab)}
                        className="sr-only peer"
                      />
                      <div className="w-5 h-5 border-2 border-gray-300 rounded peer-checked:border-primary-500 peer-checked:bg-primary-500 transition-all duration-200 flex items-center justify-center group-hover:border-primary-400">
                        {labFilters.includes(lab) && <Check className="w-3.5 h-3.5 text-white" strokeWidth={3} />}
                      </div>
                    </div>
                    <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900 flex-1">{lab}</span>
                  </label>
                ))}
              </div>
            </div>
          </div>

          <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex items-center justify-between">
            <button onClick={clearAllFilters} className="text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors">
              Clear All
            </button>
            <button onClick={() => setShowFilters(false)} className="btn-secondary">
              Close
            </button>
          </div>
        </div>
      )}

      {loading ? (
        <Loading text="Loading systems..." />
      ) : sortedSystems.length === 0 ? (
        <div className="card p-12 text-center">
          <Server className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-xl font-semibold text-gray-900 mb-2">No Systems Found</h3>
          <p className="text-gray-600">No system records are available.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {sortedSystems.map((system) => (
            <SystemCard
              key={system.system_id}
              system={system}
              lab={getLabLabel(system)}
              department={getDeptLabel(system.dept_id)}
              onViewDetails={() => setSelectedSystem(system)}
              onAssignToLab={() => openAssignModal(system)}
            />
          ))}
        </div>
      )}

      <Modal isOpen={selectedSystem !== null} onClose={() => setSelectedSystem(null)} title="System Details" size="lg">
        {selectedSystem && (
          <div className="space-y-5">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <DetailRow label="Hostname" value={selectedSystem.hostname} />
              <DetailRow label="Status" value={selectedSystem.status} capitalize />
              <DetailRow label="Department" value={getDeptLabel(selectedSystem.dept_id)} />
              <DetailRow label="Lab" value={getLabLabel(selectedSystem)} />
              <DetailRow label="IP Address" value={selectedSystem.ip_address} mono />
              <DetailRow label="MAC Address" value={selectedSystem.mac_address || 'N/A'} mono />
              <DetailRow label="System Number" value={selectedSystem.system_number?.toString() || 'N/A'} />
              <DetailRow label="SSH Port" value={selectedSystem.ssh_port?.toString() || 'N/A'} />
              <DetailRow label="CPU Model" value={selectedSystem.cpu_model || 'N/A'} />
              <DetailRow label="CPU Cores" value={selectedSystem.cpu_cores?.toString() || 'N/A'} />
              <DetailRow label="RAM Total" value={selectedSystem.ram_total_gb != null ? `${selectedSystem.ram_total_gb} GB` : 'N/A'} />
              <DetailRow label="Disk Total" value={selectedSystem.disk_total_gb != null ? `${selectedSystem.disk_total_gb} GB` : 'N/A'} />
              <DetailRow label="GPU Model" value={selectedSystem.gpu_model || 'N/A'} />
              <DetailRow label="GPU Memory" value={selectedSystem.gpu_memory != null ? `${selectedSystem.gpu_memory} GB` : 'N/A'} />
              <DetailRow label="Created At" value={formatDateTime(selectedSystem.created_at)} />
              <DetailRow label="Updated At" value={formatDateTime(selectedSystem.updated_at)} />
            </div>
          </div>
        )}
      </Modal>

      <Modal isOpen={assignTarget !== null} onClose={() => setAssignTarget(null)} title="Assign Discovered System" size="md">
        {assignTarget && (
          <div className="space-y-5">
            <div className="rounded-lg bg-gray-50 border border-gray-200 p-4">
              <p className="text-sm text-gray-600">System</p>
              <p className="font-semibold text-gray-900">{assignTarget.hostname}</p>
              <p className="text-sm text-gray-600">{assignTarget.ip_address}</p>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Department</label>
              <select
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                value={assignDeptId}
                onChange={(e) => {
                  const deptValue = Number(e.target.value) || ''
                  setAssignDeptId(deptValue)
                  if (deptValue) {
                    const deptLabs = labsByDept[deptValue] || []
                    setAssignLabId(deptLabs[0]?.lab_id || '')
                  } else {
                    setAssignLabId('')
                  }
                }}
              >
                <option value="">Select department</option>
                {departments.map((dept) => (
                  <option key={dept.dept_id} value={dept.dept_id}>
                    {dept.dept_code || dept.dept_name}
                  </option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">Lab</label>
              <select
                className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                value={assignLabId}
                onChange={(e) => setAssignLabId(Number(e.target.value) || '')}
                disabled={!assignDeptId}
              >
                <option value="">Select lab</option>
                {assignDeptLabs.map((lab) => (
                  <option key={lab.lab_id} value={lab.lab_id}>
                    Lab {lab.lab_number}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex justify-end gap-3 pt-2">
              <button className="btn-secondary" onClick={() => setAssignTarget(null)}>
                Cancel
              </button>
              <button className="btn-primary" onClick={handleAssign} disabled={assignLoading || !assignLabId}>
                {assignLoading ? 'Assigning...' : 'Assign To Lab'}
              </button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}

function DetailRow({ label, value, mono, capitalize }: { label: string; value: string; mono?: boolean; capitalize?: boolean }) {
  return (
    <div>
      <label className="text-sm font-medium text-gray-500">{label}</label>
      <p className={`text-lg font-semibold text-gray-900 mt-1 ${mono ? 'font-mono text-base' : ''} ${capitalize ? 'capitalize' : ''}`}>{value}</p>
    </div>
  )
}

function SystemCard({
  system,
  lab,
  department,
  onViewDetails,
  onAssignToLab,
}: {
  system: SystemRow
  lab: string
  department: string
  onViewDetails: () => void
  onAssignToLab: () => void
}) {
  const statusConfig = {
    active: { bg: 'bg-green-50', border: 'border-green-200', dot: 'bg-green-500', label: 'Active' },
    discovered: { bg: 'bg-blue-50', border: 'border-blue-200', dot: 'bg-blue-500', label: 'Discovered' },
    maintenance: { bg: 'bg-yellow-50', border: 'border-yellow-200', dot: 'bg-yellow-500', label: 'Maintenance' },
    offline: { bg: 'bg-gray-50', border: 'border-gray-200', dot: 'bg-gray-500', label: 'Offline' },
  }[system.status as 'active' | 'discovered' | 'maintenance' | 'offline']

  return (
    <div className="card p-6 hover:shadow-lg transition-all duration-200">
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-gradient-to-br from-primary-500 to-primary-600 rounded-lg flex items-center justify-center">
            <Server className="w-5 h-5 text-white" />
          </div>
          <div>
            <h3 className="font-semibold text-gray-900">{system.hostname}</h3>
            <p className="text-sm text-gray-500">{department}</p>
          </div>
        </div>
        <div className="flex items-center space-x-2">
          <div className={`${statusConfig?.dot || 'bg-gray-400'} w-2 h-2 rounded-full`}></div>
        </div>
      </div>

      <div className={`${statusConfig?.bg || 'bg-gray-50'} ${statusConfig?.border || 'border-gray-200'} border rounded-lg px-3 py-2 mb-4`}> 
        <div className="flex items-center justify-between text-sm">
          <span className="text-gray-600">Status</span>
          <span className="font-semibold capitalize">{statusConfig?.label || system.status}</span>
        </div>
      </div>

      <div className="space-y-2 text-sm mb-4">
        <div className="flex justify-between gap-3">
          <span className="text-gray-500">Lab</span>
          <span className="font-medium text-gray-900 text-right">{lab}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-gray-500">IP</span>
          <span className="font-mono text-gray-900 text-right">{system.ip_address}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-gray-500">MAC</span>
          <span className="font-mono text-gray-900 text-right">{system.mac_address || 'N/A'}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-gray-500">CPU</span>
          <span className="font-medium text-gray-900 text-right">{system.cpu_model || 'N/A'}</span>
        </div>
        <div className="flex justify-between gap-3">
          <span className="text-gray-500">GPU</span>
          <span className="font-medium text-gray-900 text-right">{system.gpu_model || 'N/A'}</span>
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-end gap-3 pt-4 border-t border-gray-100">
        <button onClick={onAssignToLab} className="text-sm font-medium text-gray-700 hover:text-gray-900 transition-colors">
          Assign To Lab
        </button>
        <button onClick={onViewDetails} className="text-sm font-medium text-primary-600 hover:text-primary-700 transition-colors">
          View Details {`->`}
        </button>
      </div>
    </div>
  )
}
