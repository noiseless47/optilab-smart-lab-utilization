const sql = require('./db.js')

class DepartmentModel {
    constructor() {
        this.sql = sql
    }


    // Basic validation
    validateRequired(value, fieldName) {
        if (!value || value === '') throw new Error(`${fieldName} required`)
        return value
    }

    validateID(id) {
        if (!id || id <= 0) throw new Error('Invalid ID')
        return id
    }

    // Safe query wrapper
    async query(sqlQuery, errorMsg = 'Database operation failed') {
        try {
            const result = await sqlQuery
            return Array.isArray(result) ? result : [result]
        } catch (error) {
            console.error(errorMsg, error.message)
            console.error('Full error:', error)
            throw new Error(`${errorMsg}: ${error.message}`)
        }
    }

    // HOD MODELS -----------------------------------------------------------------
    async addHOD(name, email) {
        this.validateRequired(name, 'name')
        this.validateRequired(email, 'email')
        return await this.query(
            this.sql`INSERT INTO hods(hod_name, hod_email) VALUES(${name}, ${email}) RETURNING *`,
        )
    }

    async getAllHODs() {
        return await this.query(
            this.sql`SELECT * FROM hods ORDER BY hod_name`,
            'Failed to get HODs'
        )
    }

    async getHODByID(id) {
        this.validateID(id)
        const result = await this.query(
            this.sql`SELECT * FROM hods WHERE hod_id = ${id}`,
            'Failed to get HOD'
        )
        return result[0] || null
    }

    async updateHOD(id, name, email) {
        this.validateID(id)
        this.validateRequired(name, 'name')
        this.validateRequired(email, 'email')
        return await this.query(
            this.sql`UPDATE hods SET hod_name = ${name}, hod_email = ${email} WHERE hod_id = ${id} RETURNING *`,
            'Failed to update HOD'
        )
    }

    async deleteHOD(id) {
        this.validateID(id)
        return await this.query(
            this.sql`DELETE FROM hods WHERE hod_id = ${id}`,
            'Failed to delete HOD'
        )
    }

    // DEPARTMENT MODELS -----------------------------------------------------------------
    async getAllDepartments() {
        return await this.query(
            this.sql`SELECT * FROM departments ORDER BY dept_name`,
            'Failed to get departments'
        )
    }

    async getDepartmentbyID(id) {
        this.validateID(id)
        const result = await this.query(
            this.sql`SELECT * FROM departments WHERE dept_id = ${id}`,
            'Failed to get department'
        )
        return result[0] || null
    }

    async addDepartment(name, code, vlan, subnet, description, hodID) {
        this.validateRequired(name, 'name')
        this.validateRequired(code, 'code')
        return await this.query(
            this.sql`INSERT INTO departments(dept_name, dept_code, vlan_id, subnet_cidr, description, hod_id) VALUES(${name}, ${code}, ${vlan}, ${subnet}, ${description}, ${hodID}) RETURNING *`,
            'Failed to add department'
        )
    }

    async updateDepartment(id, name, code, vlan, subnet, description, hodID) {
        this.validateID(id)
        this.validateRequired(name, 'name')
        this.validateRequired(code, 'code')
        return await this.query(
            this.sql`UPDATE departments SET dept_name = ${name}, dept_code = ${code}, vlan_id = ${vlan}, subnet_cidr = ${subnet}, description = ${description}, hod_id = ${hodID} WHERE dept_id = ${id} RETURNING *`,
            'Failed to update department'
        )
    }

    async deleteDepartment(id) {
        this.validateID(id)
        return await this.query(
            this.sql`DELETE FROM departments WHERE dept_id = ${id}`,
            'Failed to delete department'
        )
    }

    // LAB MODELS -----------------------------------------------------------------
    async getLabsByDepartment(deptID) {
        this.validateID(deptID)
        return await this.query(
            this.sql`SELECT * FROM labs WHERE lab_dept = ${deptID} ORDER BY lab_number`,
            'Failed to get labs'
        )
    }

    async getLabByID(id) {
        this.validateID(id)
        const result = await this.query(
            this.sql`SELECT * FROM labs WHERE lab_id = ${id}`,
            'Failed to get lab'
        )
        return result[0] || null
    }

    async addLab(deptID, number) {
        this.validateID(deptID)
        this.validateID(number)
        return await this.query(
            this.sql`INSERT INTO labs(lab_dept, lab_number) VALUES(${deptID}, ${number}) RETURNING *`,
            'Failed to add lab'
        )
    }

    async updateLab(id, deptID, number) {
        this.validateID(id)
        this.validateID(deptID)
        this.validateID(number)
        return await this.query(
            this.sql`UPDATE labs SET lab_dept = ${deptID}, lab_number = ${number} WHERE lab_id = ${id} RETURNING *`,
            'Failed to update lab'
        )
    }

    async deleteLab(id) {
        this.validateID(id)
        return await this.query(
            this.sql`DELETE FROM labs WHERE lab_id = ${id}`,
            'Failed to delete lab'
        )
    }

    // LAB ASSISTANT MODELS ----------------------------------------------------------------
    async addLabAssistant(name, email, deptID, labID) {
        this.validateRequired(name, 'name')
        this.validateRequired(email, 'email')
        this.validateID(deptID)
        return await this.query(
            this.sql`INSERT INTO lab_assistants(lab_assistant_name, lab_assistant_email, lab_assistant_dept, lab_assigned) VALUES(${name}, ${email}, ${deptID}, ${labID}) RETURNING *`,
            'Failed to add lab assistant'
        )
    }

    async getAssistantByID(id) {
        this.validateID(id)
        const result = await this.query(
            this.sql`SELECT * FROM lab_assistants WHERE lab_assistant_id = ${id}`,
            'Failed to get lab assistant'
        )
        return result[0] || null
    }

    async getLabAssistantsByDept(deptID){
        const query = this.sql`SELECT * FROM lab_assistants WHERE lab_assistant_dept = ${deptID} ORDER BY lab_assistant_name`
        return await this.query(query, 'Failed to get lab assistants')

    }

    async getAllLabAssistantsByLab(labID) {
        const query = this.sql`SELECT * FROM lab_assistants WHERE lab_assigned = ${labID} ORDER BY lab_assistant_name`
        return await this.query(query, 'Failed to get lab assistants')
    }

    async updateLabAssistant(id, name, email, deptID, labID) {
        this.validateID(id)
        this.validateRequired(name, 'name')
        this.validateRequired(email, 'email')
        this.validateID(deptID)
        return await this.query(
            this.sql`UPDATE lab_assistants SET lab_assistant_name = ${name}, lab_assistant_email = ${email}, lab_assistant_dept = ${deptID}, lab_assigned = ${labID} WHERE lab_assistant_id = ${id} RETURNING *`,
            'Failed to update lab assistant'
        )
    }

    async deleteLabAssistant(id) {
        this.validateID(id)
        return await this.query(
            this.sql`DELETE FROM lab_assistants WHERE lab_assistant_id = ${id}`,
            'Failed to delete lab assistant'
        )
    }

    // SYSTEM MODELS -----------------------------------------------------------------
    async addSystem(system_number, lab_id, dept_id, hostname, ip_address, mac_address, cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory, ssh_port, status) {
        this.validateID(system_number)
        this.validateRequired(hostname, 'hostname')
        this.validateRequired(ip_address, 'ip_address')
        this.validateRequired(mac_address, 'mac_address')
        return await this.query(
            this.sql`INSERT INTO systems(system_number, lab_id, dept_id, hostname, ip_address, mac_address, cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory, ssh_port, status) VALUES(${system_number}, ${lab_id}, ${dept_id}, ${hostname}, ${ip_address}::inet, ${mac_address}::macaddr, ${cpu_model}, ${cpu_cores}, ${ram_total_gb}, ${disk_total_gb}, ${gpu_model}, ${gpu_memory}, ${ssh_port}, ${status}) RETURNING *`,
            'Failed to add system'
        )
    }

    async getSystemByID(id) {
        this.validateID(id)
        const result = await this.query(
            this.sql`SELECT * FROM systems WHERE system_id = ${id}`,
            'Failed to get system'
        )
        return result[0] || null
    }

    async getSystemsByLab(labID) {
        this.validateID(labID)
        return await this.query(
            this.sql`SELECT * FROM systems WHERE lab_id = ${labID} ORDER BY system_number`,
            'Failed to get systems'
        )
    }

    async updateSystem(id, updates) {
        this.validateID(id)
        const fields = Object.keys(updates).filter(key => updates[key] !== undefined)
        if (fields.length === 0) throw new Error('No fields to update')

        const setClause = fields.map(field => `${field} = ${updates[field]}`).join(', ')
        return await this.query(
            this.sql`UPDATE systems SET ${setClause} WHERE system_id = ${id} RETURNING *`,
            'Failed to update system'
        )
    }

    async deleteSystem(id) {
        this.validateID(id)
        return await this.query(
            this.sql`DELETE FROM systems WHERE system_id = ${id}`,
            'Failed to delete system'
        )
    }

    // MAINTAINENCE MODELS -----------------------------------------------------------------
    
    async addMaintainence(system_id, lab_id, date_at, isACK, ACKat, ACKby, resolved_at, severity, message) {
        this.validateID(system_id);
        this.validateID(lab_id);
        this.validateRequired(severity, 'severity');
        this.validateRequired(message, 'message');
        this.validateRequired(date_at, 'date_at');

        const query = this.sql`INSERT INTO maintainence_logs(system_id, lab_id, date_at, is_acknowledged, acknowledged_at, acknowledged_by, resolved_at, severity, message) VALUES(${system_id}, ${lab_id}, ${date_at}, ${isACK}, ${ACKat}, ${ACKby}, ${resolved_at}, ${severity}, ${message}) RETURNING *`

        return await this.query(query, 'Failed to add maintainence log')
    }
    
    async getMaintainenceByLabID(lab_id) {
        this.validateID(lab_id)
        const query = this.sql`SELECT * FROM maintainence_logs WHERE lab_id = ${lab_id}`
        const result = await this.query(
            query,
            'Failed to get maintainence logs'
        )
        return result
    }

    async getMaintainenceByID(maintainence_id) {
        this.validateID(maintainence_id)
        const query = this.sql`SELECT * FROM maintainence_logs WHERE maintainence_id = ${maintainence_id}`
        const result = await this.query(
            query,
            'Failed to get maintainence log'
        )
        return result
    }

    async updateMaintainence(maintainence_id, updates) {
        this.validateID(maintainence_id)
        const fields = Object.keys(updates).filter(key => updates[key] !== undefined)
        if (fields.length === 0) throw new Error('No fields to update')

        const setClause = fields.map(field => `${field} = ${updates[field]}`).join(', ')
        return await this.query(
            this.sql`UPDATE maintainence_logs SET ${setClause} WHERE maintainence_id = ${maintainence_id} RETURNING *`,
            'Failed to update maintainence log'
        )
    }

    async getMaintainenceBySystemID(system_id) {
        this.validateID(system_id)
        const query = this.sql`SELECT * FROM maintainence_logs WHERE system_id = ${system_id} ORDER BY date_at DESC`
        return await this.query(
            query,
            'Failed to get maintainence logs for system'
        )
    }

    async getMaintainenceUnresolved() {
        const query = this.sql`SELECT * FROM maintainence_logs WHERE resolved_at IS NULL ORDER BY date_at DESC`
        return await this.query(
            query,
            'Failed to get unresolved maintainence logs'
        )
    }

    async getMaintainenceBySeverity(severity) {
        this.validateRequired(severity, 'severity')
        const query = this.sql`SELECT * FROM maintainence_logs WHERE severity = ${severity} ORDER BY date_at DESC`
        return await this.query(
            query,
            'Failed to get maintainence logs by severity'
        )
    }

    async acknowledgeMaintainence(maintainence_id, acknowledged_by) {
        this.validateID(maintainence_id)
        this.validateRequired(acknowledged_by, 'acknowledged_by')
        const query = this.sql`UPDATE maintainence_logs SET is_acknowledged = true, acknowledged_at = NOW(), acknowledged_by = ${acknowledged_by} WHERE maintainence_id = ${maintainence_id} RETURNING *`
        return await this.query(
            query,
            'Failed to acknowledge maintainence log'
        )
    }

    async resolveMaintainence(maintainence_id) {
        this.validateID(maintainence_id)
        const query = this.sql`UPDATE maintainence_logs SET resolved_at = NOW() WHERE maintainence_id = ${maintainence_id} RETURNING *`
        return await this.query(
            query,
            'Failed to resolve maintainence log'
        )
    }

    async deleteMaintainence(maintainence_id) {
        this.validateID(maintainence_id)
        return await this.query(
            this.sql`DELETE FROM maintainence_logs WHERE maintainence_id = ${maintainence_id}`,
            'Failed to delete maintainence log'
        )
    }
}

module.exports = DepartmentModel