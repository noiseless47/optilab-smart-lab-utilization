const express = require('express');
const router = express.Router({ mergeParams: true });
const DepartmentModel = require('../../../../../models/department_models');
const departmentModel = new DepartmentModel();

router.get("/", (req, res) => {
    const labID = req.params.labID;
    departmentModel.getLabByID(labID)
    .then((lab) => {
        if (!lab) {
            return res.status(404).json({ error: 'Lab not found' });
        }
        res.status(200).json(lab);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.get("/systems", (req, res) => {
    const labID = req.params.labID;
    departmentModel.getSystemsByLab(labID)
    .then((system) => {
        res.status(200).json(system);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.get("/systems", (req, res) => {
    const labID = req.params.labID;
    departmentModel.getSystemsByLab(labID)
    .then((system) => {
        res.status(200).json(system);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.get("/:sysID", (req, res) => {
    const sysID = req.params.sysID;
    departmentModel.getSystemByID(sysID)
    .then((system) => {
        if (!system) {
            return res.status(404).json({ error: 'System not found' });
        }
        res.status(200).json(system);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.get("/assistants", (req, res) => {
    const labID = req.params.labID;
    departmentModel.getLabAssistantsByLab(labID)
    .then((lab_assistant) => {
        res.status(200).json(lab_assistant);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.post("/", (req, res) => {
    const labID = req.params.labID;
    const {system_number, dept_id, hostname, ip_address, mac_address, cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory, ssh_port, status} = req.body;
    departmentModel.addSystem(system_number, labID, dept_id, hostname, ip_address, mac_address, cpu_model, cpu_cores, ram_total_gb, disk_total_gb, gpu_model, gpu_memory, ssh_port, status)
    .then(system => {
        res.status(201).json(system);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.use('/:sysID', require('./sysID/sysID.routes'))
router.use('/maintenance', require('./maintenance/maintenance.routes'))

module.exports = router;
