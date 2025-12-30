import { ArrowRight, Zap, Shield, TrendingUp } from 'lucide-react'
import { useNavigate } from 'react-router-dom'

export default function Hero() {
  const navigate = useNavigate()

  const handleGetStarted = () => {
    navigate('/departments')
  }

  const handleViewDocs = () => {
    window.open('https://github.com/yourusername/optilab/blob/main/README.md', '_blank')
  }

  return (
    <div className="relative overflow-hidden bg-gradient-to-br from-primary-50 via-white to-primary-50">
      {/* Animated background elements */}
      <div className="absolute inset-0 overflow-hidden">
        <div className="absolute -top-40 -right-40 w-80 h-80 bg-primary-200 rounded-full mix-blend-multiply filter blur-3xl opacity-30 animate-blob"></div>
        <div className="absolute -bottom-40 -left-40 w-80 h-80 bg-primary-300 rounded-full mix-blend-multiply filter blur-3xl opacity-30 animate-blob animation-delay-2000"></div>
        <div className="absolute top-1/2 left-1/2 transform -translate-x-1/2 -translate-y-1/2 w-80 h-80 bg-primary-100 rounded-full mix-blend-multiply filter blur-3xl opacity-30 animate-blob animation-delay-4000"></div>
      </div>

      <div className="relative max-w-7xl mx-auto px-6 py-24">
        <div className="text-center max-w-4xl mx-auto">
          <div className="inline-flex items-center space-x-2 px-4 py-2 bg-white/80 backdrop-blur-sm rounded-full border border-primary-200 mb-8">
            <Zap className="w-4 h-4 text-primary-600" />
            <span className="text-sm font-medium text-primary-700">Agentless Network-Based Monitoring</span>
          </div>
          
          <h1 className="text-5xl md:text-6xl lg:text-7xl font-bold text-gray-900 mb-6 leading-tight">
            Smart Lab Resource
            <br />
            <span className="bg-gradient-to-r from-primary-600 to-primary-500 bg-clip-text text-transparent">
              Monitoring System
            </span>
          </h1>
          
          <p className="text-xl text-gray-600 mb-12 leading-relaxed max-w-3xl mx-auto">
            Production-grade, scalable monitoring platform for agentless lab resource tracking. 
            Zero friction deployment – just provide an IP range and watch your infrastructure come alive.
          </p>
          
          <div className="flex items-center justify-center space-x-4 mb-16">
            <button onClick={handleGetStarted} className="btn-primary flex items-center space-x-2">
              <span>Get Started</span>
              <ArrowRight className="w-5 h-5" />
            </button>
            <button onClick={handleViewDocs} className="btn-secondary">
              View Documentation
            </button>
          </div>

          {/* Feature cards */}
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mt-16">
            <FeatureCard
              icon={<Shield className="w-6 h-6 text-primary-600" />}
              title="Zero Agent Install"
              description="No software on target machines. Uses standard protocols (SNMP, WMI, SSH)."
            />
            <FeatureCard
              icon={<Zap className="w-6 h-6 text-primary-600" />}
              title="Real-Time Analytics"
              description="Granular metrics every 5 minutes with advanced SQL analytics."
            />
            <FeatureCard
              icon={<TrendingUp className="w-6 h-6 text-primary-600" />}
              title="Smart Insights"
              description="Automated bottleneck detection and optimization recommendations."
            />
          </div>
        </div>
      </div>
    </div>
  )
}

function FeatureCard({ icon, title, description }: { icon: React.ReactNode, title: string, description: string }) {
  return (
    <div className="card p-6 text-left">
      <div className="w-12 h-12 bg-primary-50 rounded-lg flex items-center justify-center mb-4">
        {icon}
      </div>
      <h3 className="text-lg font-semibold text-gray-900 mb-2">{title}</h3>
      <p className="text-gray-600 text-sm">{description}</p>
    </div>
  )
}
