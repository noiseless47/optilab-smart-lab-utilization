const express = require('express');
const router = express.Router();
const MetricsModel = require('../models/metrics_models');
const DepartmentModel = require('../models/department_models');
const metricsModel = new MetricsModel();
const departmentModel = new DepartmentModel();

// GET all systems across all departments
router.get("/all", async (req, res) => {
    try {
        const systems = await departmentModel.getAllSystems();
        res.status(200).json(systems);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET latest metrics for a system
router.get("/:systemId/metrics/latest", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const metrics = await metricsModel.getLatestMetrics(systemId);
        res.status(200).json(metrics || {});
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET system metrics by system ID
router.get("/:systemId/metrics", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const limit = parseInt(req.query.limit) || 100;
        const hours = parseInt(req.query.hours) || 24;
        const metrics = await metricsModel.getMetricsBySystem(systemId, limit, hours);
        res.status(200).json(metrics);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET system details by system ID
router.get("/:systemId", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const system = await departmentModel.getSystemByID(systemId);
        if (!system) {
            return res.status(404).json({ error: 'System not found' });
        }
        res.status(200).json(system);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

module.exports = router;
