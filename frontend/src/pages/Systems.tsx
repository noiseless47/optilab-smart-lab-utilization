import { useState } from 'react'
import { Search, Filter, Server, Clock } from 'lucide-react'

export default function Systems() {
  const [searchQuery, setSearchQuery] = useState('')

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Systems</h1>
        <p className="text-gray-600">Monitor and manage all lab systems</p>
      </div>

      {/* Search and Filter */}
      <div className="flex items-center space-x-4 mb-8">
        <div className="flex-1 relative">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input
            type="text"
            placeholder="Search systems by name, lab, or IP..."
            className="w-full pl-10 pr-4 py-3 border border-gray-200 rounded-lg focus:outline-none focus:ring-2 focus:ring-primary-500 focus:border-transparent"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
          />
        </div>
        <button className="btn-secondary flex items-center space-x-2">
          <Filter className="w-4 h-4" />
          <span>Filter</span>
        </button>
      </div>

      {/* Systems Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        <SystemCard
          name="Lab-3-PC-15"
          lab="ISE Lab 3"
          ip="10.30.3.15"
          status="critical"
          cpu={95}
          memory={88}
          uptime="48h 23m"
        />
        <SystemCard
          name="Lab-1-PC-08"
          lab="CSE Lab 1"
          ip="10.31.1.08"
          status="warning"
          cpu={87}
          memory={92}
          uptime="156h 45m"
        />
        <SystemCard
          name="Lab-2-PC-22"
          lab="ECE Lab 2"
          ip="10.32.2.22"
          status="online"
          cpu={45}
          memory={62}
          uptime="312h 15m"
        />
        <SystemCard
          name="Lab-1-PC-14"
          lab="ISE Lab 1"
          ip="10.30.1.14"
          status="online"
          cpu={38}
          memory={54}
          uptime="267h 33m"
        />
        <SystemCard
          name="Lab-4-PC-09"
          lab="CSE Lab 4"
          ip="10.31.4.09"
          status="offline"
          cpu={0}
          memory={0}
          uptime="0h 0m"
        />
        <SystemCard
          name="Lab-3-PC-11"
          lab="ECE Lab 3"
          ip="10.32.3.11"
          status="online"
          cpu={52}
          memory={68}
          uptime="89h 12m"
        />
      </div>
    </div>
  )
}

function SystemCard({ name, lab, ip, status, cpu, memory, uptime }: {
  name: string
  lab: string
  ip: string
  status: string
  cpu: number
  memory: number
  uptime: string
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
        <button className="text-sm font-medium text-primary-600 hover:text-primary-700">
          View Details →
        </button>
      </div>
    </div>
  )
}
