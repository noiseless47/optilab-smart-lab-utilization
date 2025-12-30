import { useState, useEffect } from 'react'
import { AlertTriangle, AlertCircle, Info, CheckCircle, Clock, X } from 'lucide-react'
import Loading from '../components/Loading'
import api from '../lib/api'

interface Alert {
  id: string
  severity: 'critical' | 'warning' | 'info'
  title: string
  message: string
  system: string
  lab: string
  time: string
  duration: string
  cpu?: number
  memory?: number
  disk?: number
}

export default function Alerts() {
  const [dismissedAlerts, setDismissedAlerts] = useState<string[]>([])
  const [alerts, setAlerts] = useState<Alert[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    fetchAlerts()
  }, [])

  const fetchAlerts = async () => {
    try {
      setLoading(true)
      setError(null)
      const systemsRes = await api.get('/api/systems/all')
      const systemsData = systemsRes.data

      const generatedAlerts: Alert[] = []
      let alertId = 1

      for (const system of systemsData) {
        try {
          const metricsRes = await api.get(`/api/systems/${system.system_id}/metrics/latest`)
          const metrics = metricsRes.data

          if (metrics) {
            // Critical CPU alert
            if (metrics.cpu_percent > 90) {
              generatedAlerts.push({
                id: `alert-${alertId++}`,
                severity: 'critical',
                title: 'High CPU Usage Detected',
                message: `${system.hostname} CPU usage at ${Math.round(metrics.cpu_percent)}%, exceeding critical threshold`,
                system: system.hostname,
                lab: `Lab ${system.lab_id}`,
                time: 'Real-time',
                duration: 'Active',
                cpu: metrics.cpu_percent
              })
            }

            // Critical Memory alert
            if (metrics.ram_percent > 90) {
              generatedAlerts.push({
                id: `alert-${alertId++}`,
                severity: 'critical',
                title: 'Memory Threshold Exceeded',
                message: `${system.hostname} memory usage at ${Math.round(metrics.ram_percent)}%, approaching critical levels`,
                system: system.hostname,
                lab: `Lab ${system.lab_id}`,
                time: 'Real-time',
                duration: 'Active',
                memory: metrics.ram_percent
              })
            }

            // Warning Disk alert
            if (metrics.disk_percent > 85) {
              generatedAlerts.push({
                id: `alert-${alertId++}`,
                severity: 'warning',
                title: 'Disk Space Running Low',
                message: `${system.hostname} disk usage at ${Math.round(metrics.disk_percent)}%, cleanup recommended`,
                system: system.hostname,
                lab: `Lab ${system.lab_id}`,
                time: 'Real-time',
                duration: 'Active',
                disk: metrics.disk_percent
              })
            }

            // Warning CPU alert
            if (metrics.cpu_percent > 75 && metrics.cpu_percent <= 90) {
              generatedAlerts.push({
                id: `alert-${alertId++}`,
                severity: 'warning',
                title: 'Elevated CPU Usage',
                message: `${system.hostname} CPU at ${Math.round(metrics.cpu_percent)}%, monitor for potential issues`,
                system: system.hostname,
                lab: `Lab ${system.lab_id}`,
                time: 'Real-time',
                duration: 'Active',
                cpu: metrics.cpu_percent
              })
            }
          }
        } catch (err) {
          console.error(`Failed to fetch metrics for system ${system.system_id}:`, err)
        }
      }

      setAlerts(generatedAlerts)
    } catch (err: any) {
      console.error('Failed to fetch alerts:', err)
      setError(err.response?.data?.error || 'Failed to load alerts')
    } finally {
      setLoading(false)
    }
  }

  const handleDismissAlert = (alertId: string) => {
    setDismissedAlerts([...dismissedAlerts, alertId])
  }

  const isAlertDismissed = (alertId: string) => dismissedAlerts.includes(alertId)

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Alerts</h1>
          <p className="text-gray-600">Real-time system alerts and notifications</p>
        </div>
        <Loading text="Loading alerts..." />
      </div>
    )
  }

  if (error) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Alerts</h1>
          <p className="text-gray-600">Real-time system alerts and notifications</p>
        </div>
        <div className="card p-8 text-center">
          <p className="text-red-600 mb-4">{error}</p>
          <button onClick={fetchAlerts} className="btn btn-primary">Try Again</button>
        </div>
      </div>
    )
  }

  const activeAlerts = alerts.filter(a => !isAlertDismissed(a.id))
  const criticalCount = activeAlerts.filter(a => a.severity === 'critical').length
  const warningCount = activeAlerts.filter(a => a.severity === 'warning').length
  const infoCount = activeAlerts.filter(a => a.severity === 'info').length
  const resolvedCount = dismissedAlerts.length

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
          count={criticalCount}
          icon={<AlertTriangle className="w-6 h-6" />}
          color="red"
        />
        <AlertSummaryCard
          title="Warning"
          count={warningCount}
          icon={<AlertCircle className="w-6 h-6" />}
          color="yellow"
        />
        <AlertSummaryCard
          title="Info"
          count={infoCount}
          icon={<Info className="w-6 h-6" />}
          color="blue"
        />
        <AlertSummaryCard
          title="Resolved"
          count={resolvedCount}
          icon={<CheckCircle className="w-6 h-6" />}
          color="green"
        />
      </div>

      {/* Active Alerts */}
      <div className="card p-6 mb-8">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Active Alerts</h2>
        {activeAlerts.length === 0 ? (
          <div className="text-center py-12">
            <CheckCircle className="w-16 h-16 mx-auto mb-4 text-green-500" />
            <p className="text-xl font-semibold text-gray-900 mb-2">No Active Alerts</p>
            <p className="text-gray-600">All systems are operating normally</p>
          </div>
        ) : (
          <div className="space-y-4">
            {activeAlerts.map(alert => (
              <AlertItem
                key={alert.id}
                id={alert.id}
                severity={alert.severity}
                title={alert.title}
                message={alert.message}
                system={alert.system}
                lab={alert.lab}
                time={alert.time}
                duration={alert.duration}
                onDismiss={handleDismissAlert}
              />
            ))}
          </div>
        )}
      </div>

      {/* Recent Activity */}
      <div className="card p-6">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Recent Activity</h2>
        <div className="space-y-3">
          <ActivityItem
            type="resolved"
            message={`${resolvedCount} alerts resolved today`}
            time="Today"
          />
          <ActivityItem
            type="new"
            message={`${activeAlerts.length} active alerts being monitored`}
            time="Real-time"
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

  const handleClick = () => {
    console.log(`Filtering ${title.toLowerCase()} alerts`)
  }

  return (
    <div 
      onClick={handleClick}
      className="card p-6 cursor-pointer hover:shadow-lg transition-all duration-200"
    >
      <div className={`w-12 h-12 bg-gradient-to-br ${colorClasses} rounded-lg flex items-center justify-center text-white mb-4`}>
        {icon}
      </div>
      <div className="text-3xl font-bold text-gray-900 mb-1">{count}</div>
      <div className="text-sm text-gray-500">{title}</div>
    </div>
  )
}

function AlertItem({ id, severity, title, message, system, lab, time, duration, onDismiss }: {
  id: string
  severity: string
  title: string
  message: string
  system: string
  lab: string
  time: string
  duration: string
  onDismiss: (id: string) => void
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
            <button 
              onClick={() => onDismiss(id)} 
              className="text-gray-400 hover:text-gray-600 transition-colors"
              aria-label="Dismiss alert"
            >
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
