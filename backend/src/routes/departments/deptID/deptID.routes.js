const express = require('express');
const router = express.Router({ mergeParams: true });
const DepartmentModel = require('../../../models/department_models');
const departmentModel = new DepartmentModel();

// Middleware to validate department exists
router.use(async (req, res, next) => {
    try {
        const deptID = req.params.deptID;
        const department = await departmentModel.getDepartmentbyID(deptID);
        if (!department) {
            return res.status(404).json({ error: 'Department not found' });
        }
        req.department = department; // Attach to request for later use
        next();
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// GET department by ID
router.get("/", (req, res) => {
    res.status(200).json(req.department);
});


// DELETE department by ID
router.delete("/", (req, res) => {
    const deptID = req.params.deptID;
    departmentModel.deleteDepartment(deptID)
        .then(() => {
            console.log("\x1b[32m%s\x1b[0m", "Operation Successful.");
            res.status(200).json({ message: 'Department deleted successfully' });
        })
        .catch((err) => {
            res.status(500).json({ error: err.message });
            console.error("Error:", err.message);
        });
});

//
router.use('/labs', require('./labs/labs.routes'));
router.use('/faculty', require('./faculty/faculty.routes'));
router.use('/lab-assistants', require('./faculty/faculty.routes'));

// GET all maintenance logs for a department
router.get('/maintenance', async (req, res) => {
    try {
        const deptID = req.params.deptID;
        const maintenanceLogs = await departmentModel.getAllMaintenanceByDeptID(deptID);
        res.status(200).json(maintenanceLogs);
    } catch (err) {
        res.status(500).json({ error: err.message });
        console.error("Error:", err.message);
    }
});

module.exports = router;
