const express = require('express');
const router = express.Router({ mergeParams: true });
const DepartmentModel = require('../../../../models/department_models');
const departmentModel = new DepartmentModel();

router.get("/", (req, res) => {
    const deptID = req.params.deptID;
    departmentModel.getLabAssistantsByDept(deptID)
    .then((assistant) => {
        res.status(200).json(assistant);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.post("/", (req, res) => {
    const deptID = req.params.deptID;
    const {name, email, labID} = req.body;
    departmentModel.addLabAssistant(name, email, deptID, labID)
    .then((assistant) => {
        res.status(201).json(assistant);
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

router.delete("/:assistantID", (req, res) => {
    const assistantID = req.params.assistantID;
    departmentModel.deleteLabAssistant(assistantID)
    .then(() => {
        res.status(200).json({ message: 'Lab assistant deleted successfully' });
    })
    .catch((err)=>{
        res.status(500).json({error:err.message});
        console.error("Error:", err.message);
    })
})

module.exports = router;