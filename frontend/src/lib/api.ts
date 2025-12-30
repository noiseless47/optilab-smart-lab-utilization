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

export interface Department {
  dept_id: number
  dept_name: string
  dept_code: string
  vlan_id?: string
  subnet_cidr?: string
  description?: string
  hod_id?: number
}

export interface Lab {
  lab_id: number
  lab_dept: number
  lab_number: number
}

export interface LabAssistant {
  lab_assistant_id: number
  lab_assistant_name: string
  lab_assistant_email: string
  lab_assistant_dept: number
  lab_assigned?: number
}

// Department APIs
export const getDepartments = async () => {
  const response = await api.get<Department[]>('/api/departments')
  return response.data
}

export const getDepartmentById = async (deptId: number) => {
  const response = await api.get<Department>(`/api/departments/${deptId}`)
  return response.data
}

export const createDepartment = async (data: any) => {
  const response = await api.post('/api/departments', data)
  return response.data
}

export const deleteDepartment = async (deptId: number) => {
  const response = await api.delete(`/api/departments/${deptId}`)
  return response.data
}

// Lab APIs
export const getLabsByDepartment = async (deptId: number) => {
  const response = await api.get<Lab[]>(`/api/departments/${deptId}/labs`)
  return response.data
}

export const createLab = async (deptId: number, data: any) => {
  const response = await api.post(`/api/departments/${deptId}/labs`, data)
  return response.data
}

export const deleteLab = async (deptId: number, labId: number) => {
  const response = await api.delete(`/api/departments/${deptId}/labs/${labId}`)
  return response.data
}

// Lab Assistant APIs
export const getLabAssistantsByDept = async (deptId: number) => {
  const response = await api.get<LabAssistant[]>(`/api/departments/${deptId}/lab-assistants`)
  return response.data
}

export const createLabAssistant = async (deptId: number, data: any) => {
  const response = await api.post(`/api/departments/${deptId}/lab-assistants`, data)
  return response.data
}

export const deleteLabAssistant = async (deptId: number, assistantId: number) => {
  const response = await api.delete(`/api/departments/${deptId}/lab-assistants/${assistantId}`)
  return response.data
}

// System APIs
export const getSystems = async () => {
  const response = await api.get<System[]>('/api/systems')
  return response.data
}

export const getSystemById = async (systemId: number) => {
  const response = await api.get(`/api/systems/${systemId}`)
  return response.data
}

export const getSystemStatus = async () => {
  const response = await api.get('/api/systems/status')
  return response.data
}

export const getSystemMetrics = async (systemId: number, params?: { hours?: number; limit?: number }) => {
  const response = await api.get<Metric[]>(`/api/systems/${systemId}/metrics`, { params })
  return response.data
}

// Maintenance APIs
export const getMaintenanceLogs = async (deptId: number, labId: number) => {
  const response = await api.get(`/api/departments/${deptId}/labs/${labId}/maintenance`)
  return response.data
}

export const createMaintenanceLog = async (deptId: number, labId: number, data: any) => {
  const response = await api.post(`/api/departments/${deptId}/labs/${labId}/maintenance`, data)
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
