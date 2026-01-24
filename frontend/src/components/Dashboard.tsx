import { Activity, Server, BarChart3, Bell } from 'lucide-react'

export default function Dashboard() {
  return (
    <div className="max-w-7xl mx-auto px-6 py-16">
      <div className="text-center mb-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-4">
          OptiLab - Smart Lab Resource Monitoring
        </h1>
        <p className="text-xl text-gray-600">
          Real-time monitoring and analytics for computer lab resources
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <FeatureCard
          title="Systems"
          description="Monitor all lab computers"
          icon={<Server className="w-8 h-8" />}
          color="blue"
        />
        <FeatureCard
          title="Departments"
          description="View by department"
          icon={<Activity className="w-8 h-8" />}
          color="green"
        />
        <FeatureCard
          title="Analytics"
          description="Performance insights"
          icon={<BarChart3 className="w-8 h-8" />}
          color="purple"
        />
        <FeatureCard
          title="Alerts"
          description="Real-time notifications"
          icon={<Bell className="w-8 h-8" />}
          color="orange"
        />
      </div>
    </div>
  )
}

function FeatureCard({ title, description, icon, color }: { 
  title: string
  description: string
  icon: React.ReactNode
  color: string 
}) {
  const colorClasses = {
    blue: 'from-blue-500 to-blue-600',
    green: 'from-green-500 to-green-600',
    purple: 'from-purple-500 to-purple-600',
    orange: 'from-orange-500 to-orange-600',
  }[color]

  return (
    <div className="card p-6 text-center">
      <div className={`w-16 h-16 bg-gradient-to-br ${colorClasses} rounded-lg flex items-center justify-center text-white shadow-lg mx-auto mb-4`}>
        {icon}
      </div>
      <h3 className="text-lg font-semibold text-gray-900 mb-2">{title}</h3>
      <p className="text-sm text-gray-600">{description}</p>
    </div>
  )
}
