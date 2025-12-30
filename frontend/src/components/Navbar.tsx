import { Link, useLocation } from 'react-router-dom'
import { Server, Activity, AlertCircle, BarChart3, Building2 } from 'lucide-react'

export default function Navbar() {
  const location = useLocation()
  
  const isActive = (path: string) => location.pathname === path || location.pathname.startsWith(path + '/')
  
  return (
    <nav className="sticky top-0 z-50 bg-white/80 backdrop-blur-md border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-6 py-4">
        <div className="flex items-center justify-between">
          <Link to="/" className="flex items-center space-x-3 group">
            <div className="w-10 h-10 bg-gradient-to-br from-primary-500 to-primary-600 rounded-lg flex items-center justify-center shadow-lg group-hover:shadow-xl transition-shadow">
              <Server className="w-6 h-6 text-white" />
            </div>
            <div>
              <div className="text-xl font-bold text-gray-900">OptiLab</div>
              <div className="text-xs text-gray-500 font-medium">Smart Lab Monitoring</div>
            </div>
          </Link>
          
          <div className="flex items-center space-x-1">
            <NavLink to="/" active={isActive('/')} icon={<Activity className="w-4 h-4" />}>
              Dashboard
            </NavLink>
            <NavLink to="/departments" active={isActive('/departments')} icon={<Building2 className="w-4 h-4" />}>
              Departments
            </NavLink>
            <NavLink to="/systems" active={isActive('/systems')} icon={<Server className="w-4 h-4" />}>
              Systems
            </NavLink>
            <NavLink to="/analytics" active={isActive('/analytics')} icon={<BarChart3 className="w-4 h-4" />}>
              Analytics
            </NavLink>
            <NavLink to="/alerts" active={isActive('/alerts')} icon={<AlertCircle className="w-4 h-4" />}>
              Alerts
            </NavLink>
          </div>
        </div>
      </div>
    </nav>
  )
}

function NavLink({ to, active, icon, children }: { to: string, active: boolean, icon: React.ReactNode, children: React.ReactNode }) {
  return (
    <Link
      to={to}
      className={`flex items-center space-x-2 px-4 py-2 rounded-lg text-sm font-medium transition-all duration-200 ${
        active 
          ? 'bg-primary-50 text-primary-700' 
          : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'
      }`}
    >
      {icon}
      <span>{children}</span>
    </Link>
  )
}
