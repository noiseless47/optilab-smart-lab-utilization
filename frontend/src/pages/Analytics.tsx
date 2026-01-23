import { useEffect, useState } from 'react'
import Loading from '../components/Loading'
import api from '../lib/api'

interface SystemWithMetrics {
  system_id: number
  hostname: string
  lab_id: number
  cpu: number
  memory: number
  disk: number
  gpu?: number
  p95_cpu?: number
  p95_ram?: number
}

interface AggregatedMetrics {
  timestamp: string
  avg_cpu_percent: number
  max_cpu_percent: number
  p95_cpu_percent: number
  avg_ram_percent: number
  max_ram_percent: number
  p95_ram_percent: number
  avg_gpu_percent: number
  max_gpu_percent: number
  metric_count: number
}

export default function Analytics() {
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [systems, setSystems] = useState<SystemWithMetrics[]>([])
  const [avgCpu, setAvgCpu] = useState(0)
  const [avgMemory, setAvgMemory] = useState(0)
  const [aggregatedData, setAggregatedData] = useState<AggregatedMetrics[]>([])

  useEffect(() => {
    fetchAnalytics()
  }, [])

  const fetchAnalytics = async () => {
    try {
      setLoading(true)
      setError(null)
      const systemsRes = await api.get('/systems/all')
      const systemsData = systemsRes.data

      // Fetch aggregated data for all systems (last 24 hours)
      const aggregatedPromises = systemsData.map(async (system: any) => {
        try {
          const metricsRes = await api.get(`/systems/${system.system_id}/metrics/hourly?hours=24`)
          return {
            system_id: system.system_id,
            hostname: system.hostname,
            lab_id: system.lab_id,
            data: metricsRes.data
          }
        } catch {
          return {
            system_id: system.system_id,
            hostname: system.hostname,
            lab_id: system.lab_id,
            data: []
          }
        }
      })

      const aggregatedResults = await Promise.all(aggregatedPromises)
      
      // Process aggregated data
      const systemsWithMetrics: SystemWithMetrics[] = []
      let allAggregatedData: AggregatedMetrics[] = []
      
      aggregatedResults.forEach(result => {
        const latestData = result.data[0] // Most recent hour
        if (latestData) {
          systemsWithMetrics.push({
            system_id: result.system_id,
            hostname: result.hostname,
            lab_id: result.lab_id,
            cpu: parseFloat(latestData.avg_cpu_percent) || 0,
            memory: parseFloat(latestData.avg_ram_percent) || 0,
            disk: parseFloat(latestData.avg_disk_io_wait) || 0,
            gpu: parseFloat(latestData.avg_gpu_percent) || 0,
            p95_cpu: parseFloat(latestData.p95_cpu_percent) || 0,
            p95_ram: parseFloat(latestData.p95_ram_percent) || 0
          })
          
          // Add to global aggregated data
          allAggregatedData = allAggregatedData.concat(
            result.data.map((item: any) => ({
              ...item,
              system_id: result.system_id,
              hostname: result.hostname
            }))
          )
        } else {
          systemsWithMetrics.push({
            system_id: result.system_id,
            hostname: result.hostname,
            lab_id: result.lab_id,
            cpu: 0,
            memory: 0,
            disk: 0,
            gpu: 0,
            p95_cpu: 0,
            p95_ram: 0
          })
        }
      })

      setSystems(systemsWithMetrics)
      setAggregatedData(allAggregatedData)
      
      // Calculate averages from latest data
      const totalCpu = systemsWithMetrics.reduce((acc, s) => acc + s.cpu, 0)
      const totalMemory = systemsWithMetrics.reduce((acc, s) => acc + s.memory, 0)
      setAvgCpu(systemsWithMetrics.length > 0 ? Math.round(totalCpu / systemsWithMetrics.length) : 0)
      setAvgMemory(systemsWithMetrics.length > 0 ? Math.round(totalMemory / systemsWithMetrics.length) : 0)
    } catch (err: any) {
      console.error('Failed to fetch analytics:', err)
      setError(err.response?.data?.error || 'Failed to load analytics')
    } finally {
      setLoading(false)
    }
  }

  if (loading) {
    return (
      <div className="max-w-7xl mx-auto px-6 py-12">
        <div className="mb-8">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">Analytics</h1>
          <p className="text-gray-600">Advanced insights and resource optimization</p>
        </div>
        <Loading text="Loading analytics..." />
      </div>
    )
  }

  // Get top consumers by 95th percentile CPU
  const topCpuConsumers = [...systems]
    .sort((a, b) => (b.p95_cpu || 0) - (a.p95_cpu || 0))
    .slice(0, 5)

  // Calculate additional averages
  const avgGpu = systems.length > 0 ? Math.round(systems.reduce((acc, s) => acc + (s.gpu || 0), 0) / systems.length) : 0
  const avgP95Cpu = systems.length > 0 ? Math.round(systems.reduce((acc, s) => acc + (s.p95_cpu || 0), 0) / systems.length) : 0
  const avgP95Ram = systems.length > 0 ? Math.round(systems.reduce((acc, s) => acc + (s.p95_ram || 0), 0) / systems.length) : 0

  // Count high usage systems (using 95th percentile)
  const highCpuCount = systems.filter(s => (s.p95_cpu || 0) > 80).length
  const highMemoryCount = systems.filter(s => (s.p95_ram || 0) > 80).length
  const highDiskCount = systems.filter(s => s.disk > 80).length
  const highGpuCount = systems.filter(s => (s.gpu || 0) > 80).length

  return (
    <div className="max-w-7xl mx-auto px-6 py-12">
      <div className="mb-12">
        <h1 className="text-4xl font-bold text-gray-900 mb-2">System Analytics</h1>
        <p className="text-gray-600">Average resource utilization across all monitored systems</p>
      </div>

      {error && (
        <div className="card p-6 mb-8 bg-red-50 border-red-200">
          <p className="text-red-700">{error}</p>
        </div>
      )}

      {/* Key Metrics - Clean and Minimal */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6">
        <MetricCard
          title="Average CPU Utilization"
          value={`${avgCpu}%`}
          subtitle={`95th percentile: ${avgP95Cpu}%`}
          status={avgP95Cpu > 80 ? 'critical' : avgCpu > 70 ? 'warning' : 'normal'}
        />
        <MetricCard
          title="Average Memory Utilization"
          value={`${avgMemory}%`}
          subtitle={`95th percentile: ${avgP95Ram}%`}
          status={avgP95Ram > 80 ? 'critical' : avgMemory > 70 ? 'warning' : 'normal'}
        />
        <MetricCard
          title="Average GPU Utilization"
          value={`${avgGpu}%`}
          subtitle={`${systems.length} systems monitored`}
          status={avgGpu > 80 ? 'critical' : avgGpu > 70 ? 'warning' : 'normal'}
        />
        <MetricCard
          title="Average Disk I/O"
          value={`${Math.round(systems.reduce((acc, s) => acc + s.disk, 0) / (systems.length || 1))}%`}
          subtitle={`Across ${systems.length} systems`}
          status="normal"
        />
      </div>
    </div>
  )
}

function MetricCard({ title, value, subtitle, status }: {
  title: string
  value: string
  subtitle: string
  status: 'normal' | 'warning' | 'critical'
}) {
  const statusColors = {
    normal: 'border-green-200 bg-green-50',
    warning: 'border-yellow-200 bg-yellow-50',
    critical: 'border-red-200 bg-red-50'
  }

  const valueColors = {
    normal: 'text-green-700',
    warning: 'text-yellow-700',
    critical: 'text-red-700'
  }

  return (
    <div className={`card p-6 ${statusColors[status]}`}>
      <h3 className="text-sm font-medium text-gray-600 mb-2">{title}</h3>
      <div className={`text-4xl font-bold ${valueColors[status]} mb-1`}>{value}</div>
      <p className="text-sm text-gray-500">{subtitle}</p>
    </div>
  )
}
