const express = require('express');
const router = express.Router({ mergeParams: true });
const DepartmentModel = require('../../../../../../models/department_models');
const departmentModel = new DepartmentModel();

router.get("/", (req, res) => {
    const labID = req.params.labID;
    departmentModel.getMaintainenceByLabID(labID)
    .then((maint) => {
        res.status(200).json(maint);
    })
    .catch((err) => {
        res.status(500).json({ error: err.message });
    });
})

router.post("/", (req, res) => {
    const labID = req.params.labID;
    const {system_id, date_at, isACK, ACKat, ACKby, resolved_at, severity, message} = req.body;

    departmentModel.addMaintainence(system_id, date_at, isACK, ACKat, ACKby, resolved_at, severity, message)
    .then((maint) => {
        res.status(200).json(maint);
    })
    .catch((err) => {
        res.status(500).json({ error: err.message });
    });
})

module.exports = router;