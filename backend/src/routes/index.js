const express = require('express');
const router = express.Router();

// HOD routes
router.use('/hod', require('./hod'));

// Department routes
router.use('/departments', require('./departments/dept.routes'));

// Systems routes (for global system access)
router.use('/systems', require('./systems.routes'));

module.exports = router;