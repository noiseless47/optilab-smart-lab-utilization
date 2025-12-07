const express = require('express');
const router = express.Router();
const DepartmentModel = require('../../models/department_models');
const departmentModel = new DepartmentModel();


router.get("/",(req,res)=>{
    departmentModel.getAllDepartments()
    .then((dep)=>{
        console.log("\x1b[32m%s\x1b[0m", "Operation Successful.")
        res.status(200).json(dep);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})


router.post("/", (req,res)=>{
    const {name, code, vlan, subnet, description, hodID} = req.body;
    departmentModel.addDepartment(name, code, vlan, subnet, description, hodID)
    .then((dep) => {
        console.log("\x1b[32m%s\x1b[0m", "Operation Successful.")
        res.status(200).json(dep);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.put("/:deptID", (req, res) => {
    const deptID = req.params.deptID;
    const {name, code, vlan, subnet, description, hodID} = req.body;
    departmentModel.updateDepartment(name, code, vlan, subnet, description, hodID)
    .then((dep) =>{
        console.log("\x1b[32m%s\x1b[0m", "Operation Successful.")
        res.status(200).json(dep);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.delete("/:deptID", (req, res) => {
    const deptID = req.params.deptID;
    departmentModel.deleteDepartment(deptID)
    .then((dep) =>{
        console.log("\x1b[32m%s\x1b[0m", "Operation Successful.")
        res.status(200).json(dep);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.use('/:deptID', require('./deptID/deptID.routes'));

module.exports = router;