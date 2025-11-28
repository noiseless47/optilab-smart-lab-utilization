const express = require('express');
const router = express.Router({ mergeParams: true });
const MetricsModel = require('../../../../../../../models/metrics_models').default;
const metricsModel = new MetricsModel();

// GET latest metrics for the system (dashboard overview)
router.get("/", async (req, res) => {
    try {
        const sysID = req.params.sysID;
        const latest = await metricsModel.getLatestMetrics(sysID);
        if (!latest) {
            return res.status(404).json({ error: 'No metrics found for this system' });
        }
        res.status(200).json(latest);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET raw metrics history
router.get("/metrics", async (req, res) => {
    try {
        const sysID = req.params.sysID;
        const limit = parseInt(req.query.limit) || 100;
        const hours = parseInt(req.query.hours) || 24;
        const metrics = await metricsModel.getMetricsBySystem(sysID, limit, hours);
        res.status(200).json(metrics);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET hourly aggregated stats
router.get("/hourly", async (req, res) => {
    try {
        const sysID = req.params.sysID;
        const hours = parseInt(req.query.hours) || 24;
        const stats = await metricsModel.getHourlyStats(sysID, hours);
        res.status(200).json(stats);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET daily aggregated stats
router.get("/daily", async (req, res) => {
    try {
        const sysID = req.params.sysID;
        const days = parseInt(req.query.days) || 30;
        const stats = await metricsModel.getDailyStats(sysID, days);
        res.status(200).json(stats);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

// GET performance summary
router.get("/summary", async (req, res) => {
    try {
        const sysID = req.params.sysID;
        const days = parseInt(req.query.days) || 7;
        const summary = await metricsModel.getSystemPerformanceSummary(sysID, days);
        res.status(200).json(summary);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

module.exports = router;