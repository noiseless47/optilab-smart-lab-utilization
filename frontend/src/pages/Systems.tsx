import { useState, useMemo, useEffect } from 'react'
import { Search, Filter, Server, Clock, X, ChevronDown, ArrowUpDown, Check } from 'lucide-react'
import Modal from '../components/Modal'
import Loading from '../components/Loading'
import api from '../lib/api'

type SortOption = 'name' | 'status' | 'cpu-high' | 'cpu-low' | 'memory-high' | 'memory-low' | 'uptime'

export default function Systems() {
  const [searchQuery, setSearchQuery] = useState('')
  const [showFilters, setShowFilters] = useState(false)
  const [showSort, setShowSort] = useState(false)
  const [sortBy, setSortBy] = useState<SortOption>('name')
  const [selectedSystem, setSelectedSystem] = useState<{
    name: string
    lab: string
    ip: string
    status: string
    cpu: number
    memory: number
    uptime: string
  } | null>(null)
  
  // Filter states
  const [statusFilters, setStatusFilters] = useState<string[]>([])
  const [labFilters, setLabFilters] = useState<string[]>([])
  const [cpuRange, setCpuRange] = useState<[number, number]>([0, 100])
  const [memoryRange, setMemoryRange] = useState<[number, number]>([0, 100])

  const handleFilterClick = () => {
    setShowFilters(!showFilters)
  }

  const toggleStatusFilter = (status: string) => {
    setStatusFilters(prev =>
      prev.includes(status) ? prev.filter(s => s !== status) : [...prev, status]
    )
  }

  const toggleLabFilter = (lab: string) => {
    setLabFilters(prev =>
      prev.includes(lab) ? prev.filter(l => l !== lab) : [...prev, lab]
    )
  }

  const clearAllFilters = () => {
    setStatusFilters([])
    setLabFilters([])
    setCpuRange([0, 100])
    setMemoryRange([0, 100])
  }

  const applyFilters = () => {
    setShowFilters(false)
  }

  const activeFilterCount = statusFilters.length + labFilters.length

  const [allSystems, setAllSystems] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [systemsWithMetrics, setSystemsWithMetrics] = useState<any[]>([])

  useEffect(() => {
    fetchSystems()
  }, [])

  const fetchSystems = async () => {
    try {
      setLoading(true)
      setError(null)
      // Fetch all systems
      const systemsRes = await api.get('/api/systems/all')
      const systems = systemsRes.data
      
      // Fetch latest metrics for each system
      const systemsWithMetricsPromises = systems.map(async (system: any) => {
        try {
          const metricsRes = await api.get(`/api/systems/${system.system_id}/metrics/latest`)
          const metrics = metricsRes.data
          return {
            ...system,
            cpu: metrics?.cpu_percent || 0,
            memory: metrics?.ram_percent || 0,
            uptimeSeconds: metrics?.uptime_seconds || 0,
            uptime: formatUptime(metrics?.uptime_seconds || 0),
            uptimeMinutes: Math.floor((metrics?.uptime_seconds || 0) / 60)
          }
        } catch {
          return {
            ...system,
            cpu: 0,
            memory: 0,
            uptimeSeconds: 0,
            uptime: 'N/A',
            uptimeMinutes: 0
          }
        }
      })
      
      const systemsData = await Promise.all(systemsWithMetricsPromises)
      setSystemsWithMetrics(systemsData)
      setAllSystems(systemsData)
    } catch (error: any) {
      console.error('Failed to fetch systems:', error)
      setError(error.response?.data?.error || 'Failed to load systems')
    } finally {
      setLoading(false)
    }
  }

  const formatUptime = (seconds: number) => {
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    return `${hours}h ${minutes}m`
  }

  // Sort systems
  const sortedSystems = useMemo(() => {
    const systems = [...systemsWithMetrics]
    const statusOrder = { critical: 0, warning: 1, offline: 2, online: 3, active: 3, discovered: 4 }

    switch (sortBy) {
      case 'name':
        return systems.sort((a, b) => a.hostname.localeCompare(b.hostname))
      case 'status':
        return systems.sort((a, b) => statusOrder[a.status as keyof typeof statusOrder] - statusOrder[b.status as keyof typeof statusOrder])
      case 'cpu-high':
        return systems.sort((a, b) => b.cpu - a.cpu)
      case 'cpu-low':
        return systems.sort((a, b) => a.cpu - b.cpu)
      case 'memory-high':
        return systems.sort((a, b) => b.memory - a.memory)
      case 'memory-low':
        return systems.sort((a, b) => a.memory - b.memory)
      case 'uptime':
        return systems.sort((a, b) => b.uptimeMinutes - a.uptimeMinutes)
      default:
        return systems
    }
  }, [sortBy, systemsWithMetrics])

  const handleSortChange = (option: SortOption) => {
    setSortBy(option)
    setShowSort(false)
  }

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Systems</h1>
        <p className="text-gray-600">Monitor and manage all lab systems</p>
      </div>

      {error && (
        <div className="card p-8 text-center mb-8">
          <p className="text-red-600 mb-4">{error}</p>
          <button onClick={fetchSystems} className="btn btn-primary">Try Again</button>
        </div>
      )}

      {/* Search and Filter */}
      <div className="flex items-center space-x-4 mb-8">
        <div className="flex-1 relative">
          <Search className="absolute left-4 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input
            type="text"
            placeholder="Search systems by name, lab, or IP..."
            className="w-full pl-12 pr-4 py-3.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 placeholder:text-gray-400 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300 shadow-sm"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
        <button onClick={handleFilterClick} className="btn-secondary flex items-center space-x-2 relative">
          <Filter className="w-4 h-4" />
          <span>Filters</span>
          {activeFilterCount > 0 && (
            <span className="absolute -top-2 -right-2 bg-primary-500 text-white text-xs font-bold rounded-full w-5 h-5 flex items-center justify-center">
              {activeFilterCount}
            </span>
          )}
        </button>
        <div className="relative">
          <button
            onClick={() => setShowSort(!showSort)}
            className="btn-secondary flex items-center space-x-2"
          >
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
                { value: 'status' as SortOption, label: 'Status (Priority)' },
                { value: 'cpu-high' as SortOption, label: 'CPU Usage (High to Low)' },
                { value: 'cpu-low' as SortOption, label: 'CPU Usage (Low to High)' },
                { value: 'memory-high' as SortOption, label: 'Memory Usage (High to Low)' },
                { value: 'memory-low' as SortOption, label: 'Memory Usage (Low to High)' },
                { value: 'uptime' as SortOption, label: 'Uptime (Longest First)' },
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

      {/* Advanced Filter Panel */}
      {showFilters && (
        <div className="card mb-6 overflow-hidden">
          <div className="bg-gray-50 px-6 py-4 border-b border-gray-200 flex items-center justify-between">
            <h3 className="font-semibold text-gray-900">Filter Systems</h3>
            <button onClick={() => setShowFilters(false)} className="text-gray-400 hover:text-gray-600">
              <X className="w-5 h-5" />
            </button>
          </div>
          
          <div className="p-6 space-y-6">
            {/* Status Filter */}
            <div>
              <h4 className="font-medium text-gray-900 mb-3 flex items-center justify-between">
                System Status
                <ChevronDown className="w-4 h-4 text-gray-400" />
              </h4>
              <div className="space-y-2.5">
                {['critical', 'warning', 'online', 'offline'].map((status) => (
                  <label key={status} className="flex items-center space-x-3 cursor-pointer group p-2 rounded-lg hover:bg-gray-50 transition-all">
                    <div className="relative">
                      <input
                        type="checkbox"
                        checked={statusFilters.includes(status)}
                        onChange={() => toggleStatusFilter(status)}
                        className="sr-only peer"
                      />
                      <div className="w-5 h-5 border-2 border-gray-300 rounded peer-checked:border-primary-500 peer-checked:bg-primary-500 transition-all duration-200 flex items-center justify-center group-hover:border-primary-400">
                        {statusFilters.includes(status) && (
                          <Check className="w-3.5 h-3.5 text-white" strokeWidth={3} />
                        )}
                      </div>
                    </div>
                    <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900 capitalize flex-1">{status}</span>
                    <span className="text-xs font-semibold text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">
                      {status === 'critical' ? '1' : status === 'warning' ? '1' : status === 'online' ? '3' : '1'}
                    </span>
                  </label>
                ))}
              </div>
            </div>

            <div className="border-t border-gray-200"></div>

            {/* Lab Filter */}
            <div>
              <h4 className="font-medium text-gray-900 mb-3 flex items-center justify-between">
                Lab Location
                <ChevronDown className="w-4 h-4 text-gray-400" />
              </h4>
              <div className="space-y-2.5">
                {['ISE Lab 1', 'ISE Lab 3', 'CSE Lab 1', 'CSE Lab 4', 'ECE Lab 2', 'ECE Lab 3'].map((lab) => (
                  <label key={lab} className="flex items-center space-x-3 cursor-pointer group p-2 rounded-lg hover:bg-gray-50 transition-all">
                    <div className="relative">
                      <input
                        type="checkbox"
                        checked={labFilters.includes(lab)}
                        onChange={() => toggleLabFilter(lab)}
                        className="sr-only peer"
                      />
                      <div className="w-5 h-5 border-2 border-gray-300 rounded peer-checked:border-primary-500 peer-checked:bg-primary-500 transition-all duration-200 flex items-center justify-center group-hover:border-primary-400">
                        {labFilters.includes(lab) && (
                          <Check className="w-3.5 h-3.5 text-white" strokeWidth={3} />
                        )}
                      </div>
                    </div>
                    <span className="text-sm font-medium text-gray-700 group-hover:text-gray-900 flex-1">{lab}</span>
                    <span className="text-xs font-semibold text-gray-500 bg-gray-100 px-2 py-0.5 rounded-full">1</span>
                  </label>
                ))}
              </div>
            </div>

            <div className="border-t border-gray-200"></div>

            {/* CPU Usage Range */}
            <div>
              <h4 className="font-medium text-gray-900 mb-3">CPU Usage Range</h4>
              <div className="space-y-3">
                <div className="flex items-center space-x-3">
                  <div className="flex-1 flex items-center space-x-2">
                    <input
                      type="number"
                      value={cpuRange[0]}
                      onChange={(e) => setCpuRange([parseInt(e.target.value) || 0, cpuRange[1]])}
                      className="w-full px-4 py-2.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      placeholder="Min"
                      min="0"
                      max="100"
                    />
                    <span className="text-sm font-semibold text-gray-500">%</span>
                  </div>
                  <div className="text-gray-400 font-medium">to</div>
                  <div className="flex-1 flex items-center space-x-2">
                    <input
                      type="number"
                      value={cpuRange[1]}
                      onChange={(e) => setCpuRange([cpuRange[0], parseInt(e.target.value) || 100])}
                      className="w-full px-4 py-2.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      placeholder="Max"
                      min="0"
                      max="100"
                    />
                    <span className="text-sm font-semibold text-gray-500">%</span>
                  </div>
                </div>
              </div>
            </div>

            <div className="border-t border-gray-200"></div>

            {/* Memory Usage Range */}
            <div>
              <h4 className="font-medium text-gray-900 mb-3">Memory Usage Range</h4>
              <div className="space-y-3">
                <div className="flex items-center space-x-3">
                  <div className="flex-1 flex items-center space-x-2">
                    <input
                      type="number"
                      value={memoryRange[0]}
                      onChange={(e) => setMemoryRange([parseInt(e.target.value) || 0, memoryRange[1]])}
                      className="w-full px-4 py-2.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      placeholder="Min"
                      min="0"
                      max="100"
                    />
                    <span className="text-sm font-semibold text-gray-500">%</span>
                  </div>
                  <div className="text-gray-400 font-medium">to</div>
                  <div className="flex-1 flex items-center space-x-2">
                    <input
                      type="number"
                      value={memoryRange[1]}
                      onChange={(e) => setMemoryRange([memoryRange[0], parseInt(e.target.value) || 100])}
                      className="w-full px-4 py-2.5 bg-white border-2 border-gray-200 rounded-lg text-sm font-medium text-gray-900 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-100 transition-all hover:border-gray-300 [appearance:textfield] [&::-webkit-outer-spin-button]:appearance-none [&::-webkit-inner-spin-button]:appearance-none"
                      placeholder="Max"
                      min="0"
                      max="100"
                    />
                    <span className="text-sm font-semibold text-gray-500">%</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          {/* Filter Actions */}
          <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex items-center justify-between">
            <button
              onClick={clearAllFilters}
              className="text-sm font-medium text-gray-600 hover:text-gray-900 transition-colors"
            >
              Clear All
            </button>
            <div className="flex items-center space-x-3">
              <button
                onClick={() => setShowFilters(false)}
                className="px-4 py-2 text-sm font-medium text-gray-700 hover:text-gray-900 transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={applyFilters}
                className="px-6 py-2 bg-gradient-to-r from-primary-500 to-primary-600 text-white text-sm font-semibold rounded-lg hover:from-primary-600 hover:to-primary-700 transition-all duration-200 shadow-md"
              >
                Apply Filters
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Systems Grid */}
      {loading ? (
        <Loading text="Loading systems..." />
      ) : sortedSystems.length === 0 ? (
        <div className="card p-12 text-center">
          <Server className="w-16 h-16 text-gray-300 mx-auto mb-4" />
          <h3 className="text-xl font-semibold text-gray-900 mb-2">No Systems Found</h3>
          <p className="text-gray-600">No systems have been discovered yet.</p>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {sortedSystems.map((system) => (
            <SystemCard
              key={system.system_id}
              name={system.hostname}
              lab={`Lab ${system.lab_id || 'N/A'}`}
              ip={system.ip_address}
              status={system.status}
              cpu={system.cpu}
              memory={system.memory}
              uptime={system.uptime}
              onViewDetails={() => setSelectedSystem({
                name: system.hostname,
                lab: `Lab ${system.lab_id || 'N/A'}`,
                ip: system.ip_address,
                status: system.status,
                cpu: system.cpu,
                memory: system.memory,
                uptime: system.uptime
              })}
            />
          ))}
        </div>
      )}

      {/* System Details Modal */}
      <Modal
        isOpen={selectedSystem !== null}
        onClose={() => setSelectedSystem(null)}
        title="System Details"
        size="lg"
      >
        {selectedSystem && (
          <div className="space-y-6">
            {/* System Info */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="text-sm font-medium text-gray-500">System Name</label>
                <p className="text-lg font-semibold text-gray-900 mt-1">{selectedSystem.name}</p>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-500">Lab Location</label>
                <p className="text-lg font-semibold text-gray-900 mt-1">{selectedSystem.lab}</p>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-500">IP Address</label>
                <p className="text-lg font-mono font-semibold text-gray-900 mt-1">{selectedSystem.ip}</p>
              </div>
              <div>
                <label className="text-sm font-medium text-gray-500">Status</label>
                <p className="text-lg font-semibold text-gray-900 mt-1 capitalize">{selectedSystem.status}</p>
              </div>
            </div>

            {/* Resource Usage */}
            <div className="space-y-4">
              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-sm font-medium text-gray-500">CPU Usage</label>
                  <span className="text-lg font-bold text-gray-900">{selectedSystem.cpu}%</span>
                </div>
                <div className="w-full bg-gray-100 rounded-full h-3">
                  <div
                    className={`h-3 rounded-full transition-all ${
                      selectedSystem.cpu > 80 ? 'bg-red-500' : selectedSystem.cpu > 60 ? 'bg-yellow-500' : 'bg-green-500'
                    }`}
                    style={{ width: `${selectedSystem.cpu}%` }}
                  ></div>
                </div>
              </div>

              <div>
                <div className="flex items-center justify-between mb-2">
                  <label className="text-sm font-medium text-gray-500">Memory Usage</label>
                  <span className="text-lg font-bold text-gray-900">{selectedSystem.memory}%</span>
                </div>
                <div className="w-full bg-gray-100 rounded-full h-3">
                  <div
                    className={`h-3 rounded-full transition-all ${
                      selectedSystem.memory > 80 ? 'bg-red-500' : selectedSystem.memory > 60 ? 'bg-yellow-500' : 'bg-green-500'
                    }`}
                    style={{ width: `${selectedSystem.memory}%` }}
                  ></div>
                </div>
              </div>
            </div>

            {/* Uptime */}
            <div>
              <label className="text-sm font-medium text-gray-500">Uptime</label>
              <p className="text-lg font-semibold text-gray-900 mt-1">{selectedSystem.uptime}</p>
            </div>

            {/* Action Buttons */}
            <div className="flex justify-end pt-4 border-t border-gray-200">
              <button
                onClick={() => {
                  console.log('SSH to system:', selectedSystem.name)
                  setSelectedSystem(null)
                  // Implement SSH connection logic
                }}
                className="px-6 py-3 bg-gradient-to-r from-primary-500 to-primary-600 text-white font-semibold rounded-lg hover:from-primary-600 hover:to-primary-700 transition-all duration-200 shadow-lg hover:shadow-xl transform hover:-translate-y-0.5"
              >
                Connect via SSH
              </button>
            </div>
          </div>
        )}
      </Modal>
    </div>
  )
}

function SystemCard({ name, lab, ip, status, cpu, memory, uptime, onViewDetails }: {
  name: string
  lab: string
  ip: string
  status: string
  cpu: number
  memory: number
  uptime: string
  onViewDetails: (system: { name: string; lab: string; ip: string; status: string; cpu: number; memory: number; uptime: string }) => void
}) {
  const statusConfig = {
    critical: { bg: 'bg-red-50', border: 'border-red-200', dot: 'bg-red-500', text: 'text-red-700', label: 'Critical' },
    warning: { bg: 'bg-yellow-50', border: 'border-yellow-200', dot: 'bg-yellow-500', text: 'text-yellow-700', label: 'Warning' },
    online: { bg: 'bg-green-50', border: 'border-green-200', dot: 'bg-green-500', text: 'text-green-700', label: 'Online' },
    offline: { bg: 'bg-gray-50', border: 'border-gray-200', dot: 'bg-gray-500', text: 'text-gray-700', label: 'Offline' },
  }[status]

  return (
    <div className="card p-6 hover:shadow-lg transition-all duration-200">
      {/* Header */}
      <div className="flex items-start justify-between mb-4">
        <div className="flex items-center space-x-3">
          <div className="w-10 h-10 bg-gradient-to-br from-primary-500 to-primary-600 rounded-lg flex items-center justify-center">
            <Server className="w-5 h-5 text-white" />
          </div>
          <div>
            <h3 className="font-semibold text-gray-900">{name}</h3>
            <p className="text-sm text-gray-500">{lab}</p>
          </div>
        </div>
        <div className="flex items-center space-x-2">
          <div className={`${statusConfig?.dot} w-2 h-2 rounded-full`}></div>
        </div>
      </div>

      {/* IP and Status */}
      <div className={`${statusConfig?.bg} ${statusConfig?.border} border rounded-lg px-3 py-2 mb-4`}>
        <div className="flex items-center justify-between">
          <span className="text-xs text-gray-600">IP Address</span>
          <span className="text-sm font-mono font-medium text-gray-900">{ip}</span>
        </div>
      </div>

      {/* Metrics */}
      <div className="space-y-3 mb-4">
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-gray-600">CPU</span>
            <span className="text-xs font-semibold text-gray-900">{cpu}%</span>
          </div>
          <div className="w-full bg-gray-100 rounded-full h-1.5">
            <div
              className={`h-1.5 rounded-full transition-all ${
                cpu > 80 ? 'bg-red-500' : cpu > 60 ? 'bg-yellow-500' : 'bg-green-500'
              }`}
              style={{ width: `${cpu}%` }}
            ></div>
          </div>
        </div>
        <div>
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs text-gray-600">Memory</span>
            <span className="text-xs font-semibold text-gray-900">{memory}%</span>
          </div>
          <div className="w-full bg-gray-100 rounded-full h-1.5">
            <div
              className={`h-1.5 rounded-full transition-all ${
                memory > 80 ? 'bg-red-500' : memory > 60 ? 'bg-yellow-500' : 'bg-green-500'
              }`}
              style={{ width: `${memory}%` }}
            ></div>
          </div>
        </div>
      </div>

      {/* Footer */}
      <div className="flex items-center justify-between pt-4 border-t border-gray-100">
        <div className="flex items-center space-x-2 text-gray-500">
          <Clock className="w-4 h-4" />
          <span className="text-xs">{uptime}</span>
        </div>
        <button 
          onClick={() => {
            onViewDetails({ name, lab, ip, status, cpu, memory, uptime })
          }}
          className="text-sm font-medium text-primary-600 hover:text-primary-700 transition-colors"
        >
          View Details →
        </button>
      </div>
    </div>
  )
}
