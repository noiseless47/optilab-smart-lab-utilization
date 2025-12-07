const express = require('express');
const router = express.Router();
const DepartmentModel = require('../models/department_models');
const departmentModel = new DepartmentModel();

router.get("/", (req,res) => {
    departmentModel.getAllHODs()
    .then((hod) => {
        res.status(200).json(hod);
    })
    .catch((err) => {
        res.status(500).json({error:err.message});
    });
})
router.post("/", (req,res) => {
    const {hod_name, hod_email} = req.body;
    departmentModel.addHOD(hod_name, hod_email)
    .then((hod) => {
        res.status(201).json(hod);
    })
    .catch((err) => {
        res.status(500).json({error:err.message});
    });
})

module.exports = router;