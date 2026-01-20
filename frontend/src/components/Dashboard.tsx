import { useEffect, useState } from 'react'
import { Activity, Cpu, HardDrive, Wifi, AlertTriangle, TrendingUp, Server } from 'lucide-react'

interface SystemStatus {
  total: number
  online: number
  offline: number
  critical: number
}

export default function Dashboard() {
  const [stats, setStats] = useState<SystemStatus>({
    total: 0,
    online: 0,
    offline: 0,
    critical: 0
  })

  useEffect(() => {
    // Fetch data from API
    // For now, using mock data
    setStats({
      total: 145,
      online: 132,
      offline: 13,
      critical: 3
    })
  }, [])

  return (
    <div className="max-w-7xl mx-auto px-6 py-16">
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

      {/* Resource Overview */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 mb-12">
        <div className="card p-6 lg:col-span-2">
          <h2 className="text-xl font-semibold text-gray-900 mb-6">Resource Utilization</h2>
          <div className="space-y-6">
            <ResourceBar label="CPU Usage" value={67} color="blue" icon={<Cpu className="w-5 h-5" />} />
            <ResourceBar label="Memory Usage" value={82} color="purple" icon={<HardDrive className="w-5 h-5" />} />
            <ResourceBar label="Disk I/O" value={45} color="green" icon={<HardDrive className="w-5 h-5" />} />
            <ResourceBar label="Network" value={34} color="orange" icon={<Wifi className="w-5 h-5" />} />
          </div>
        </div>

        <div className="card p-6">
          <h2 className="text-xl font-semibold text-gray-900 mb-6">Recent Alerts</h2>
          <div className="space-y-4">
            <AlertItem severity="critical" message="High CPU usage on Lab-3-PC-15" time="2 min ago" />
            <AlertItem severity="warning" message="Memory threshold reached Lab-1-PC-08" time="15 min ago" />
            <AlertItem severity="info" message="System Lab-2-PC-22 came online" time="1 hour ago" />
          </div>
        </div>
      </div>

      {/* Top Systems */}
      <div className="card p-6">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Top Resource Consumers</h2>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">System</th>
                <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">Lab</th>
                <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">CPU</th>
                <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">Memory</th>
                <th className="text-left py-3 px-4 text-sm font-semibold text-gray-700">Status</th>
              </tr>
            </thead>
            <tbody>
              <SystemRow name="Lab-3-PC-15" lab="ISE Lab 3" cpu={95} memory={88} status="critical" />
              <SystemRow name="Lab-1-PC-08" lab="CSE Lab 1" cpu={87} memory={92} status="warning" />
              <SystemRow name="Lab-2-PC-22" lab="ECE Lab 2" cpu={78} memory={76} status="normal" />
              <SystemRow name="Lab-1-PC-14" lab="ISE Lab 1" cpu={72} memory={68} status="normal" />
            </tbody>
          </table>
        </div>
      </div>
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

function ResourceBar({ label, value, color, icon }: { label: string, value: number, color: string, icon: React.ReactNode }) {
  const colorClasses = {
    blue: 'bg-blue-500',
    purple: 'bg-purple-500',
    green: 'bg-green-500',
    orange: 'bg-orange-500',
  }[color]

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center space-x-2">
          <div className="text-gray-600">{icon}</div>
          <span className="text-sm font-medium text-gray-700">{label}</span>
        </div>
        <span className="text-sm font-semibold text-gray-900">{value}%</span>
      </div>
      <div className="w-full bg-gray-100 rounded-full h-2">
        <div className={`${colorClasses} h-2 rounded-full transition-all duration-300`} style={{ width: `${value}%` }}></div>
      </div>
    </div>
  )
}

function AlertItem({ severity, message, time }: { severity: string, message: string, time: string }) {
  const severityConfig = {
    critical: { bg: 'bg-red-50', border: 'border-red-200', text: 'text-red-700', dot: 'bg-red-500' },
    warning: { bg: 'bg-yellow-50', border: 'border-yellow-200', text: 'text-yellow-700', dot: 'bg-yellow-500' },
    info: { bg: 'bg-blue-50', border: 'border-blue-200', text: 'text-blue-700', dot: 'bg-blue-500' },
  }[severity]

  return (
    <div className={`${severityConfig?.bg} ${severityConfig?.border} border rounded-lg p-3`}>
      <div className="flex items-start space-x-3">
        <div className={`${severityConfig?.dot} w-2 h-2 rounded-full mt-1.5`}></div>
        <div className="flex-1">
          <p className={`text-sm font-medium ${severityConfig?.text}`}>{message}</p>
          <p className="text-xs text-gray-500 mt-1">{time}</p>
        </div>
      </div>
    </div>
  )
}

function SystemRow({ name, lab, cpu, memory, status }: { name: string, lab: string, cpu: number, memory: number, status: string }) {
  const statusConfig = {
    critical: { bg: 'bg-red-100', text: 'text-red-700', label: 'Critical' },
    warning: { bg: 'bg-yellow-100', text: 'text-yellow-700', label: 'Warning' },
    normal: { bg: 'bg-green-100', text: 'text-green-700', label: 'Normal' },
  }[status]

  return (
    <tr className="border-b border-gray-100 hover:bg-gray-50 transition-colors">
      <td className="py-4 px-4">
        <div className="font-medium text-gray-900">{name}</div>
      </td>
      <td className="py-4 px-4 text-gray-600">{lab}</td>
      <td className="py-4 px-4">
        <div className="text-sm font-medium text-gray-900">{cpu}%</div>
      </td>
      <td className="py-4 px-4">
        <div className="text-sm font-medium text-gray-900">{memory}%</div>
      </td>
      <td className="py-4 px-4">
        <span className={`inline-flex px-2 py-1 rounded-full text-xs font-medium ${statusConfig?.bg} ${statusConfig?.text}`}>
          {statusConfig?.label}
        </span>
      </td>
    </tr>
  )
}
