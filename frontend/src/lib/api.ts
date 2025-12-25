import axios from 'axios'

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:8000'

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
})

export interface System {
  id: number
  hostname: string
  ip_address: string
  lab_id: number
  department: string
  status: 'online' | 'offline' | 'critical' | 'warning'
  last_seen: string
}

export interface Metric {
  system_id: number
  timestamp: string
  cpu_usage: number
  memory_usage: number
  disk_usage: number
  network_rx: number
  network_tx: number
}

export interface Alert {
  id: number
  system_id: number
  severity: 'critical' | 'warning' | 'info'
  message: string
  created_at: string
  resolved_at: string | null
}

// System APIs
export const getSystems = async () => {
  const response = await api.get<System[]>('/api/systems')
  return response.data
}

export const getSystemStatus = async () => {
  const response = await api.get('/api/systems/status')
  return response.data
}

export const getSystemMetrics = async (systemId: number) => {
  const response = await api.get<Metric[]>(`/api/systems/${systemId}/metrics`)
  return response.data
}

// Analytics APIs
export const getTopConsumers = async (type: 'cpu' | 'memory' | 'disk') => {
  const response = await api.get(`/api/analytics/top-consumers/${type}`)
  return response.data
}

export const getUnderutilized = async () => {
  const response = await api.get('/api/analytics/underutilized')
  return response.data
}

// Alert APIs
export const getActiveAlerts = async () => {
  const response = await api.get<Alert[]>('/api/alerts/active')
  return response.data
}

export default api
