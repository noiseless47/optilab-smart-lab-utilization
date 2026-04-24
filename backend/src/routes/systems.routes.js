const express = require('express');
const router = express.Router();
const MetricsModel = require('../models/metrics_models');
const DepartmentModel = require('../models/department_models');
const CFRSModel = require('../models/cfrs_models');
const metricsModel = new MetricsModel();
const departmentModel = new DepartmentModel();
const cfrsModel = new CFRSModel();

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

// GET hourly aggregated metrics for a system
router.get("/:systemId/metrics/hourly", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const hours = parseInt(req.query.hours) || 24;
        const metrics = await metricsModel.getHourlyStats(systemId, hours);
        res.status(200).json(metrics);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET daily aggregated metrics for a system
router.get("/:systemId/metrics/daily", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const days = parseInt(req.query.days) || 30;
        const metrics = await metricsModel.getDailyStats(systemId, days);
        res.status(200).json(metrics);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET CFRS metrics for a system (raw time-series)
router.get("/:systemId/metrics/cfrs", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const hours = parseInt(req.query.hours) || 24;
        const metrics = await metricsModel.getCFRSMetrics(systemId, hours);
        res.status(200).json(metrics);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET CFRS hourly aggregated stats
router.get("/:systemId/metrics/cfrs/hourly", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const hours = parseInt(req.query.hours) || 24;
        const stats = await metricsModel.getCFRSHourlyStats(systemId, hours);
        res.status(200).json(stats);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET latest CFRS metrics
router.get("/:systemId/metrics/cfrs/latest", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const metrics = await metricsModel.getLatestCFRSMetrics(systemId);
        res.status(200).json(metrics || {});
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET CFRS metrics summary (latest + historical)
router.get("/:systemId/metrics/cfrs/summary", async (req, res) => {
    try {
        const systemId = req.params.systemId;
        const hours = parseInt(req.query.hours) || 24;
        const summary = await metricsModel.getCFRSMetricsSummary(systemId, hours);
        res.status(200).json(summary);
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

// ============================================================================
// CFRS SCORE ENDPOINTS
// ============================================================================

// POST - Compute and store baseline for a system and metric
router.post("/:systemId/cfrs/baseline/:metricName", async (req, res) => {
    try {
        const systemId = parseInt(req.params.systemId);
        const metricName = req.params.metricName;
        const windowDays = parseInt(req.body.windowDays) || null;
        const notes = req.body.notes || null;
        
        // Compute baseline
        const baseline = await cfrsModel.computeBaseline(systemId, metricName, windowDays);
        
        // Store baseline
        const stored = await cfrsModel.storeBaseline(baseline, notes);
        
        res.status(201).json({
            message: 'Baseline computed and stored successfully',
            baseline: stored
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// POST - Compute and store all baselines for a system
router.post("/:systemId/cfrs/baselines/compute", async (req, res) => {
    try {
        const systemId = parseInt(req.params.systemId);
        const windowDays = parseInt(req.body.windowDays) || null;
        
        const result = await cfrsModel.computeAllBaselines(systemId, windowDays);
        
        res.status(201).json({
            message: 'Baselines computation completed',
            ...result
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET - Get baseline for a system and metric
router.get("/:systemId/cfrs/baseline/:metricName", async (req, res) => {
    try {
        const systemId = parseInt(req.params.systemId);
        const metricName = req.params.metricName;
        
        const baseline = await cfrsModel.getBaseline(systemId, metricName);
        
        if (!baseline) {
            return res.status(404).json({ error: 'Baseline not found' });
        }
        
        res.status(200).json(baseline);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET - Get all baselines for a system
router.get("/:systemId/cfrs/baselines", async (req, res) => {
    try {
        const systemId = parseInt(req.params.systemId);
        const baselines = await cfrsModel.getAllBaselines(systemId);
        res.status(200).json(baselines);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET - Compute CFRS score for a system
router.get("/:systemId/cfrs/score", async (req, res) => {
    try {
        const systemId = parseInt(req.params.systemId);
        
        // Parse options
        const options = {
            useMAD: req.query.useMAD === 'true',
            trendWindow: req.query.trendWindow ? parseInt(req.query.trendWindow) : null,
            customWeights: req.query.weights ? JSON.parse(req.query.weights) : null
        };
        
        const cfrs = await cfrsModel.computeCFRS(systemId, options);
        res.status(200).json(cfrs);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// POST - Compute CFRS scores for multiple systems
router.post("/cfrs/batch", async (req, res) => {
    try {
        const systemIds = req.body.systemIds;
        
        if (!Array.isArray(systemIds) || systemIds.length === 0) {
            return res.status(400).json({ error: 'systemIds array required' });
        }
        
        const options = {
            useMAD: req.body.useMAD || false,
            trendWindow: req.body.trendWindow || null,
            customWeights: req.body.customWeights || null
        };
        
        const results = await cfrsModel.computeBatchCFRS(systemIds, options);
        res.status(200).json(results);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET - Get CFRS configuration
router.get("/cfrs/config", async (req, res) => {
    try {
        const config = cfrsModel.getConfig();
        res.status(200).json(config);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// PUT - Update CFRS configuration
router.put("/cfrs/config", async (req, res) => {
    try {
        const updates = req.body;
        const config = cfrsModel.updateConfig(updates);
        res.status(200).json({
            message: 'Configuration updated successfully',
            config
        });
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

module.exports = router;
