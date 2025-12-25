import { AlertTriangle, AlertCircle, Info, CheckCircle, Clock, X } from 'lucide-react'

export default function Alerts() {
  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Alerts</h1>
        <p className="text-gray-600">Real-time system alerts and notifications</p>
      </div>

      {/* Alert Summary */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        <AlertSummaryCard
          title="Critical"
          count={3}
          icon={<AlertTriangle className="w-6 h-6" />}
          color="red"
        />
        <AlertSummaryCard
          title="Warning"
          count={8}
          icon={<AlertCircle className="w-6 h-6" />}
          color="yellow"
        />
        <AlertSummaryCard
          title="Info"
          count={15}
          icon={<Info className="w-6 h-6" />}
          color="blue"
        />
        <AlertSummaryCard
          title="Resolved"
          count={42}
          icon={<CheckCircle className="w-6 h-6" />}
          color="green"
        />
      </div>

      {/* Active Alerts */}
      <div className="card p-6 mb-8">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Active Alerts</h2>
        <div className="space-y-4">
          <AlertItem
            severity="critical"
            title="High CPU Usage Detected"
            message="Lab-3-PC-15 CPU usage has exceeded 95% for the last 15 minutes"
            system="Lab-3-PC-15"
            lab="ISE Lab 3"
            time="2 minutes ago"
            duration="15m"
          />
          <AlertItem
            severity="critical"
            title="Memory Threshold Exceeded"
            message="Lab-1-PC-08 memory usage at 92%, approaching critical levels"
            system="Lab-1-PC-08"
            lab="CSE Lab 1"
            time="15 minutes ago"
            duration="28m"
          />
          <AlertItem
            severity="warning"
            title="Disk Space Running Low"
            message="Lab-2-PC-18 disk usage at 85%, cleanup recommended"
            system="Lab-2-PC-18"
            lab="ECE Lab 2"
            time="45 minutes ago"
            duration="2h 15m"
          />
          <AlertItem
            severity="warning"
            title="Network Latency High"
            message="Lab-4-PC-12 experiencing elevated network latency (>100ms)"
            system="Lab-4-PC-12"
            lab="ISE Lab 4"
            time="1 hour ago"
            duration="1h 32m"
          />
        </div>
      </div>

      {/* Recent Activity */}
      <div className="card p-6">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Recent Activity</h2>
        <div className="space-y-3">
          <ActivityItem
            type="resolved"
            message="CPU alert resolved for Lab-1-PC-14"
            time="2 hours ago"
          />
          <ActivityItem
            type="new"
            message="New warning alert for Lab-3-PC-11"
            time="3 hours ago"
          />
          <ActivityItem
            type="resolved"
            message="Disk space alert resolved for Lab-2-PC-05"
            time="5 hours ago"
          />
          <ActivityItem
            type="new"
            message="System Lab-5-PC-20 came online"
            time="6 hours ago"
          />
        </div>
      </div>
    </div>
  )
}

function AlertSummaryCard({ title, count, icon, color }: {
  title: string
  count: number
  icon: React.ReactNode
  color: string
}) {
  const colorClasses = {
    red: 'from-red-500 to-red-600',
    yellow: 'from-yellow-500 to-yellow-600',
    blue: 'from-blue-500 to-blue-600',
    green: 'from-green-500 to-green-600',
  }[color]

  return (
    <div className="card p-6">
      <div className={`w-12 h-12 bg-gradient-to-br ${colorClasses} rounded-lg flex items-center justify-center text-white mb-4`}>
        {icon}
      </div>
      <div className="text-3xl font-bold text-gray-900 mb-1">{count}</div>
      <div className="text-sm text-gray-500">{title}</div>
    </div>
  )
}

function AlertItem({ severity, title, message, system, lab, time, duration }: {
  severity: string
  title: string
  message: string
  system: string
  lab: string
  time: string
  duration: string
}) {
  const severityConfig = {
    critical: {
      bg: 'bg-red-50',
      border: 'border-red-200',
      iconBg: 'bg-red-100',
      iconColor: 'text-red-600',
      icon: AlertTriangle,
      badgeBg: 'bg-red-100',
      badgeText: 'text-red-700',
    },
    warning: {
      bg: 'bg-yellow-50',
      border: 'border-yellow-200',
      iconBg: 'bg-yellow-100',
      iconColor: 'text-yellow-600',
      icon: AlertCircle,
      badgeBg: 'bg-yellow-100',
      badgeText: 'text-yellow-700',
    },
    info: {
      bg: 'bg-blue-50',
      border: 'border-blue-200',
      iconBg: 'bg-blue-100',
      iconColor: 'text-blue-600',
      icon: Info,
      badgeBg: 'bg-blue-100',
      badgeText: 'text-blue-700',
    },
  }[severity]

  const Icon = severityConfig?.icon || Info

  return (
    <div className={`${severityConfig?.bg} ${severityConfig?.border} border rounded-lg p-4`}>
      <div className="flex items-start space-x-4">
        <div className={`${severityConfig?.iconBg} w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0`}>
          <Icon className={`w-5 h-5 ${severityConfig?.iconColor}`} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between mb-2">
            <h3 className="font-semibold text-gray-900">{title}</h3>
            <button className="text-gray-400 hover:text-gray-600 transition-colors">
              <X className="w-5 h-5" />
            </button>
          </div>
          <p className="text-sm text-gray-600 mb-3">{message}</p>
          <div className="flex items-center flex-wrap gap-3">
            <span className={`px-2 py-1 rounded-full text-xs font-medium ${severityConfig?.badgeBg} ${severityConfig?.badgeText}`}>
              {severity.toUpperCase()}
            </span>
            <div className="flex items-center space-x-1 text-gray-500 text-xs">
              <span className="font-medium">{system}</span>
              <span>•</span>
              <span>{lab}</span>
            </div>
            <div className="flex items-center space-x-1 text-gray-500 text-xs">
              <Clock className="w-3 h-3" />
              <span>{time}</span>
              <span>•</span>
              <span>Duration: {duration}</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function ActivityItem({ type, message, time }: { type: string, message: string, time: string }) {
  const typeConfig = {
    resolved: { icon: CheckCircle, color: 'text-green-600', bg: 'bg-green-50' },
    new: { icon: Info, color: 'text-blue-600', bg: 'bg-blue-50' },
  }[type]

  const Icon = typeConfig?.icon || Info

  return (
    <div className="flex items-center space-x-3 py-3 border-b border-gray-100 last:border-0">
      <div className={`${typeConfig?.bg} w-8 h-8 rounded-full flex items-center justify-center`}>
        <Icon className={`w-4 h-4 ${typeConfig?.color}`} />
      </div>
      <div className="flex-1">
        <p className="text-sm text-gray-900">{message}</p>
        <p className="text-xs text-gray-500 mt-1">{time}</p>
      </div>
    </div>
  )
}
