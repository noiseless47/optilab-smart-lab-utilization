import { useQuery } from '@tanstack/react-query'
import api from '../lib/api'

export function useCFRSScore(systemId: string) {
  return useQuery({
    queryKey: ['cfrsScore', systemId],
    queryFn: async () => {
      const res = await api.get(`/systems/${systemId}/cfrs/score`)
      return res.data
    },
    enabled: !!systemId,
    refetchInterval: 10000, // Poll every 10 seconds
    retry: false
  })
}

export function useCFRSBaselines(systemId: string) {
  return useQuery({
    queryKey: ['cfrsBaselines', systemId],
    queryFn: async () => {
      const res = await api.get(`/systems/${systemId}/cfrs/baselines`)
      return res.data || []
    },
    enabled: !!systemId,
  })
}

export function useCFRSMetrics(systemId: string, hours: number = 24) {
  return useQuery({
    queryKey: ['cfrsMetrics', systemId, hours],
    queryFn: async () => {
      const [metricsRes, latestRes] = await Promise.all([
        api.get(`/systems/${systemId}/metrics/cfrs`, { params: { hours } }),
        api.get(`/systems/${systemId}/metrics/cfrs/latest`)
      ])
      
      return {
        metrics: metricsRes.data || [],
        latest: latestRes.data || null
      }
    },
    enabled: !!systemId,
    refetchInterval: 5000, // Poll every 5 seconds for live CFRS updates
  })
}
