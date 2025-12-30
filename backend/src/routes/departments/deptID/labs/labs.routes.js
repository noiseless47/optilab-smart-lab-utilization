const express = require('express');
const router = express.Router({ mergeParams: true });
const DepartmentModel = require('../../../../models/department_models');
const departmentModel = new DepartmentModel();

router.get("/", (req, res) => {
    const deptID = req.params.deptID;
    departmentModel.getLabsByDepartment(deptID)
    .then((labs) => {
        res.status(200).json(labs);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.post("/", (req, res) => {
    const deptID = req.params.deptID;
    const {number} = req.body;
    departmentModel.addLab(deptID, number)
    .then((lab) => {
        res.status(200).json(lab);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.delete("/:labID", (req, res) => {
    const labID = req.params.labID;
    departmentModel.deleteLab(labID)
    .then(() => {
        res.status(200).json({ message: 'Lab deleted successfully' });
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.use('/:labID', require('./labID/labID.routes'))
module.exports = router;