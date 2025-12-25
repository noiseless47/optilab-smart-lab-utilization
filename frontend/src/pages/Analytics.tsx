import { TrendingUp, TrendingDown, BarChart3, PieChart, Activity } from 'lucide-react'

export default function Analytics() {
  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-8">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">Analytics</h1>
        <p className="text-gray-600">Advanced insights and resource optimization</p>
      </div>

      {/* Key Metrics */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6 mb-12">
        <MetricCard
          title="Avg CPU Usage"
          value="67%"
          change="+5%"
          trend="up"
          icon={<Activity className="w-5 h-5" />}
        />
        <MetricCard
          title="Avg Memory"
          value="72%"
          change="-2%"
          trend="down"
          icon={<Activity className="w-5 h-5" />}
        />
        <MetricCard
          title="Efficiency Score"
          value="85/100"
          change="+3"
          trend="up"
          icon={<TrendingUp className="w-5 h-5" />}
        />
        <MetricCard
          title="Bottlenecks"
          value="12"
          change="-4"
          trend="down"
          icon={<TrendingDown className="w-5 h-5" />}
        />
      </div>

      {/* Charts Grid */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-12">
        <ChartCard
          title="Resource Utilization Trend"
          subtitle="Last 7 days"
          icon={<BarChart3 className="w-5 h-5" />}
        />
        <ChartCard
          title="Department Distribution"
          subtitle="By resource consumption"
          icon={<PieChart className="w-5 h-5" />}
        />
      </div>

      {/* Top Consumers */}
      <div className="card p-6 mb-12">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Top CPU Consumers</h2>
        <div className="space-y-4">
          <ConsumerBar system="Lab-3-PC-15" lab="ISE Lab 3" value={95} color="red" />
          <ConsumerBar system="Lab-1-PC-08" lab="CSE Lab 1" value={87} color="yellow" />
          <ConsumerBar system="Lab-2-PC-22" lab="ECE Lab 2" value={78} color="green" />
          <ConsumerBar system="Lab-1-PC-14" lab="ISE Lab 1" value={72} color="green" />
        </div>
      </div>

      {/* Recommendations */}
      <div className="card p-6">
        <h2 className="text-xl font-semibold text-gray-900 mb-6">Optimization Recommendations</h2>
        <div className="space-y-4">
          <Recommendation
            type="hardware"
            title="RAM Upgrade Recommended"
            description="Lab-1-PC-08 consistently exceeds 90% memory usage. Consider upgrading from 8GB to 16GB."
            priority="high"
          />
          <Recommendation
            type="optimization"
            title="Underutilized System Detected"
            description="Lab-5-PC-03 averages 15% CPU usage. Consider reallocation or workload balancing."
            priority="medium"
          />
          <Recommendation
            type="maintenance"
            title="Disk Cleanup Required"
            description="Lab-2-PC-18 disk usage at 92%. Schedule cleanup to prevent performance degradation."
            priority="high"
          />
        </div>
      </div>
    </div>
  )
}

function MetricCard({ title, value, change, trend, icon }: {
  title: string
  value: string
  change: string
  trend: string
  icon: React.ReactNode
}) {
  const trendColor = trend === 'up' ? 'text-green-600' : 'text-red-600'
  const TrendIcon = trend === 'up' ? TrendingUp : TrendingDown

  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="text-gray-600">{icon}</div>
        <div className={`flex items-center space-x-1 ${trendColor} text-sm font-medium`}>
          <TrendIcon className="w-4 h-4" />
          <span>{change}</span>
        </div>
      </div>
      <div className="text-3xl font-bold text-gray-900 mb-1">{value}</div>
      <div className="text-sm text-gray-500">{title}</div>
    </div>
  )
}

function ChartCard({ title, subtitle, icon }: { title: string, subtitle: string, icon: React.ReactNode }) {
  return (
    <div className="card p-6">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h3 className="text-lg font-semibold text-gray-900">{title}</h3>
          <p className="text-sm text-gray-500 mt-1">{subtitle}</p>
        </div>
        <div className="text-gray-600">{icon}</div>
      </div>
      <div className="h-64 bg-gradient-to-br from-gray-50 to-gray-100 rounded-lg flex items-center justify-center">
        <p className="text-gray-400 text-sm">Chart visualization placeholder</p>
      </div>
    </div>
  )
}

function ConsumerBar({ system, lab, value, color }: { system: string, lab: string, value: number, color: string }) {
  const colorClasses = {
    red: 'bg-red-500',
    yellow: 'bg-yellow-500',
    green: 'bg-green-500',
  }[color]

  return (
    <div>
      <div className="flex items-center justify-between mb-2">
        <div>
          <div className="font-medium text-gray-900">{system}</div>
          <div className="text-sm text-gray-500">{lab}</div>
        </div>
        <span className="text-sm font-semibold text-gray-900">{value}%</span>
      </div>
      <div className="w-full bg-gray-100 rounded-full h-2">
        <div className={`${colorClasses} h-2 rounded-full`} style={{ width: `${value}%` }}></div>
      </div>
    </div>
  )
}

function Recommendation({ type, title, description, priority }: {
  type: string
  title: string
  description: string
  priority: string
}) {
  const typeConfig = {
    hardware: { icon: '🔧', bg: 'bg-blue-50', border: 'border-blue-200' },
    optimization: { icon: '⚡', bg: 'bg-purple-50', border: 'border-purple-200' },
    maintenance: { icon: '🛠️', bg: 'bg-orange-50', border: 'border-orange-200' },
  }[type]

  const priorityConfig = {
    high: { bg: 'bg-red-100', text: 'text-red-700' },
    medium: { bg: 'bg-yellow-100', text: 'text-yellow-700' },
    low: { bg: 'bg-green-100', text: 'text-green-700' },
  }[priority]

  return (
    <div className={`${typeConfig?.bg} ${typeConfig?.border} border rounded-lg p-4`}>
      <div className="flex items-start space-x-3">
        <div className="text-2xl">{typeConfig?.icon}</div>
        <div className="flex-1">
          <div className="flex items-center justify-between mb-2">
            <h4 className="font-semibold text-gray-900">{title}</h4>
            <span className={`px-2 py-1 rounded-full text-xs font-medium ${priorityConfig?.bg} ${priorityConfig?.text}`}>
              {priority.toUpperCase()}
            </span>
          </div>
          <p className="text-sm text-gray-600">{description}</p>
        </div>
      </div>
    </div>
  )
}
