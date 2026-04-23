import { useQuery } from '@tanstack/react-query'
import api from '../lib/api'

export function useSystemData(deptId: string, labId: string, systemId: string) {
  return useQuery({
    queryKey: ['system', deptId, labId, systemId],
    queryFn: async () => {
      const res = await api.get(`/departments/${deptId}/labs/${labId}/systems`)
      const system = res.data.find((s: any) => s.system_id === parseInt(systemId || '0'))
      if (!system) {
        throw new Error('System not found')
      }
      return system
    },
    enabled: !!deptId && !!labId && !!systemId,
  })
}

export function useSystemMetrics(deptId: string, labId: string, systemId: string, hours: number = 24, live: boolean = false) {
  return useQuery({
    queryKey: ['systemMetrics', deptId, labId, systemId, hours],
    queryFn: async () => {
      const res = await api.get(`/departments/${deptId}/labs/${labId}/${systemId}/metrics`, {
        params: { hours, limit: 100 }
      })
      // Reverse to chronological order for charts
      return res.data.reverse()
    },
    enabled: !!deptId && !!labId && !!systemId,
    refetchInterval: live ? 5000 : false, // Poll every 5 seconds if live
  })
}

export function useAggregateMetrics(deptId: string, labId: string, systemId: string, type: string = 'hourly') {
  return useQuery({
    queryKey: ['aggregateMetrics', deptId, labId, systemId, type],
    queryFn: async () => {
      try {
        const res = await api.get(`/departments/${deptId}/labs/${labId}/${systemId}/metrics/aggregate`, {
          params: { type }
        })
        return res.data || []
      } catch (e) {
        return []
      }
    },
    enabled: !!deptId && !!labId && !!systemId,
  })
}
