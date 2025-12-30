import axios from 'axios'

const API_BASE_URL = import.meta.env.VITE_API_URL || 'http://localhost:3000/api'

const api = axios.create({
  baseURL: API_BASE_URL,
  headers: {
    'Content-Type': 'application/json',
  },
})

export interface HOD {
  hod_id: number
  hod_name: string
  hod_email: string
}

export interface System {
  system_id: number
  system_number?: number
  hostname: string
  ip_address: string
  mac_address?: string
  lab_id: number
  dept_id: number
  status: 'active' | 'offline' | 'maintenance' | 'discovered'
  cpu_model?: string
  cpu_cores?: number
  ram_total_gb?: number
  disk_total_gb?: number
  gpu_model?: string
  gpu_memory?: number
  ssh_port?: number
  created_at?: string
  updated_at?: string
}

export interface Metric {
  metric_id?: number
  system_id: number
  timestamp: string
  cpu_percent?: number
  cpu_temperature?: number
  ram_percent?: number
  disk_percent?: number
  disk_read_mbps?: number
  disk_write_mbps?: number
  network_sent_mbps?: number
  network_recv_mbps?: number
  gpu_percent?: number
  gpu_memory_used_gb?: number
  gpu_temperature?: number
  uptime_seconds?: number
  logged_in_users?: number
}

export interface MaintenanceLog {
  maintainence_id: number
  system_id: number
  date_at: string
  severity: 'info' | 'warning' | 'critical'
  message: string
  is_acknowledged: boolean
  acknowledged_at?: string
  acknowledged_by?: string
  resolved_at?: string
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
  assistant_ids?: number[]
}

export interface LabAssistant {
  lab_assistant_id: number
  lab_assistant_name: string
  lab_assistant_email: string
  lab_assistant_dept: number
  lab_assigned?: number
}

// ============================================================================
// HOD APIs
// ============================================================================
export const getAllHODs = async () => {
  const response = await api.get<HOD[]>('/hod')
  return response.data
}

export const createHOD = async (data: { hod_name: string; hod_email: string }) => {
  const response = await api.post<HOD[]>('/hod', data)
  return response.data
}

// ============================================================================
// Department APIs
// ============================================================================
export const getDepartments = async () => {
  const response = await api.get<Department[]>('/departments')
  return response.data
}

export const getDepartmentById = async (deptId: number) => {
  const response = await api.get<Department>(`/departments/${deptId}`)
  return response.data
}

export const createDepartment = async (data: any) => {
  const response = await api.post('/departments', {
    name: data.dept_name || data.name,
    code: data.dept_code || data.code,
    vlan: data.vlan_id || data.vlan,
    subnet: data.subnet_cidr || data.subnet,
    description: data.description,
    hodID: data.hod_id || data.hodID,
  })
  return response.data
}

export const updateDepartment = async (deptId: number, data: any) => {
  const response = await api.put(`/departments/${deptId}`, {
    name: data.dept_name || data.name,
    code: data.dept_code || data.code,
    vlan: data.vlan_id || data.vlan,
    subnet: data.subnet_cidr || data.subnet,
    description: data.description,
    hodID: data.hod_id || data.hodID,
  })
  return response.data
}

export const deleteDepartment = async (deptId: number) => {
  const response = await api.delete(`/departments/${deptId}`)
  return response.data
}

// ============================================================================
// Lab APIs (under departments)
// ============================================================================
export const getLabsByDepartment = async (deptId: number) => {
  const response = await api.get<Lab[]>(`/departments/${deptId}/labs`)
  return response.data
}

export const getLabById = async (deptId: number, labId: number) => {
  const response = await api.get<Lab>(`/departments/${deptId}/labs/${labId}`)
  return response.data
}

export const createLab = async (deptId: number, data: { number: number }) => {
  const response = await api.post(`/departments/${deptId}/labs`, data)
  return response.data
}

export const updateLab = async (deptId: number, labId: number, data: any) => {
  const response = await api.put(`/departments/${deptId}/labs/${labId}`, data)
  return response.data
}

export const deleteLab = async (deptId: number, labId: number) => {
  const response = await api.delete(`/departments/${deptId}/labs/${labId}`)
  return response.data
}

// ============================================================================
// Lab Assistant APIs (under departments as faculty)
// ============================================================================
export const getLabAssistantsByDept = async (deptId: number) => {
  const response = await api.get<LabAssistant[]>(`/departments/${deptId}/faculty`)
  return response.data
}

export const createLabAssistant = async (deptId: number, data: { name: string; email: string; labID?: number }) => {
  const response = await api.post(`/departments/${deptId}/faculty`, {
    name: data.name,
    email: data.email,
    labID: data.labID,
  })
  return response.data
}

export const deleteLabAssistant = async (deptId: number, assistantId: number) => {
  const response = await api.delete(`/departments/${deptId}/faculty/${assistantId}`)
  return response.data
}

// ============================================================================
// System APIs (under labs)
// ============================================================================
export const getSystemsByLab = async (deptId: number, labId: number) => {
  const response = await api.get<System[]>(`/departments/${deptId}/labs/${labId}`)
  return response.data
}

export const getSystemById = async (deptId: number, labId: number, systemId: number) => {
  const response = await api.get<System>(`/departments/${deptId}/labs/${labId}/${systemId}`)
  return response.data
}

export const createSystem = async (deptId: number, labId: number, data: any) => {
  const response = await api.post(`/departments/${deptId}/labs/${labId}`, data)
  return response.data
}

export const deleteSystem = async (deptId: number, labId: number, systemId: number) => {
  const response = await api.delete(`/departments/${deptId}/labs/${labId}/${systemId}`)
  return response.data
}

// ============================================================================
// Metrics APIs (under systems)
// ============================================================================
export const getLatestMetrics = async (deptId: number, labId: number, systemId: number) => {
  const response = await api.get<Metric>(`/departments/${deptId}/labs/${labId}/${systemId}`)
  return response.data
}

export const getMetricsHistory = async (
  deptId: number,
  labId: number,
  systemId: number,
  params?: { limit?: number; hours?: number }
) => {
  const response = await api.get<Metric[]>(`/departments/${deptId}/labs/${labId}/${systemId}/metrics`, { params })
  return response.data
}

export const getHourlyStats = async (
  deptId: number,
  labId: number,
  systemId: number,
  params?: { hours?: number }
) => {
  const response = await api.get(`/departments/${deptId}/labs/${labId}/${systemId}/hourly`, { params })
  return response.data
}

export const getDailyStats = async (
  deptId: number,
  labId: number,
  systemId: number,
  params?: { days?: number }
) => {
  const response = await api.get(`/departments/${deptId}/labs/${labId}/${systemId}/daily`, { params })
  return response.data
}

export const getPerformanceSummary = async (
  deptId: number,
  labId: number,
  systemId: number,
  params?: { days?: number }
) => {
  const response = await api.get(`/departments/${deptId}/labs/${labId}/${systemId}/summary`, { params })
  return response.data
}

// ============================================================================
// Maintenance Log APIs (under systems)
// ============================================================================
export const getMaintenanceLogsForSystem = async (deptId: number, labId: number, systemId: number) => {
  const response = await api.get<MaintenanceLog[]>(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs`
  )
  return response.data
}

export const getUnresolvedMaintenanceLogs = async (deptId: number, labId: number, systemId: number) => {
  const response = await api.get<MaintenanceLog[]>(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs/unresolved`
  )
  return response.data
}

export const getMaintenanceLogsBySeverity = async (
  deptId: number,
  labId: number,
  systemId: number,
  severity: string
) => {
  const response = await api.get<MaintenanceLog[]>(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs/severity/${severity}`
  )
  return response.data
}

export const createMaintenanceLog = async (
  deptId: number,
  labId: number,
  systemId: number,
  data: { severity: string; message: string; date_at?: string }
) => {
  const response = await api.post(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs`,
    data
  )
  return response.data
}

export const acknowledgeMaintenanceLog = async (
  deptId: number,
  labId: number,
  systemId: number,
  logId: number,
  acknowledgedBy: string
) => {
  const response = await api.patch(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs/${logId}/acknowledge`,
    { acknowledged_by: acknowledgedBy }
  )
  return response.data
}

export const resolveMaintenanceLog = async (
  deptId: number,
  labId: number,
  systemId: number,
  logId: number
) => {
  const response = await api.patch(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs/${logId}/resolve`
  )
  return response.data
}

export const updateMaintenanceLog = async (
  deptId: number,
  labId: number,
  systemId: number,
  logId: number,
  data: { severity?: string; message?: string }
) => {
  const response = await api.put(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs/${logId}`,
    data
  )
  return response.data
}

export const deleteMaintenanceLog = async (
  deptId: number,
  labId: number,
  systemId: number,
  logId: number
) => {
  const response = await api.delete(
    `/departments/${deptId}/labs/${labId}/${systemId}/maintenance-logs/${logId}`
  )
  return response.data
}

// ============================================================================
// Lab-level Maintenance APIs (for backward compatibility)
// ============================================================================
export const getMaintenanceLogsByLab = async (deptId: number, labId: number) => {
  const response = await api.get<MaintenanceLog[]>(`/departments/${deptId}/labs/${labId}/maintenance`)
  return response.data
}

export const createLabMaintenanceLog = async (
  deptId: number,
  labId: number,
  data: { system_id: number; severity: string; message: string; date_at?: string }
) => {
  const response = await api.post(`/departments/${deptId}/labs/${labId}/maintenance`, data)
  return response.data
}

export const updateLabMaintenanceLog = async (
  deptId: number,
  labId: number,
  logId: number,
  data: {
    is_acknowledged?: boolean
    acknowledged_at?: string
    acknowledged_by?: string
    resolved_at?: string
  }
) => {
  const response = await api.put(`/departments/${deptId}/labs/${labId}/maintenance/${logId}`, data)
  return response.data
}

export default api

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