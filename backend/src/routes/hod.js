const express = require('express');
const router = express.Router();
const departmentModel = require('../models/department_models');

router.get("/hod", (req,res) => {
    departmentModel.getAllHODs()
    .then((hod) => {
        res.status(200).json(hod);
    })
    .catch((err) => {
        res.status(500).json({error:err.message});
    });
})
router.post("/hod", (req,res) => {
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