import { useState } from 'react'
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom'
import Navbar from './components/Navbar'
import Hero from './components/Hero'
import Dashboard from './components/Dashboard'
import Systems from './pages/Systems'
import Analytics from './pages/Analytics'
import Alerts from './pages/Alerts'
import Departments from './pages/Departments'
import DepartmentDetail from './pages/DepartmentDetail'
import Lab from './pages/Lab'
import SystemDetail from './pages/SystemDetail'
import MaintenanceLogs from './pages/MaintenanceLogs'

function App() {
  return (
    <Router>
      <div className="min-h-screen bg-gradient-to-br from-gray-50 via-white to-gray-50">
        <Navbar />
        <Routes>
          <Route path="/" element={
            <>
              <Hero />
              <Dashboard />
            </>
          } />
          <Route path="/departments" element={<Departments />} />
          <Route path="/departments/:deptId" element={<DepartmentDetail />} />
          <Route path="/departments/:deptId/maintenance" element={<MaintenanceLogs />} />
          <Route path="/departments/:deptId/labs/:labId" element={<Lab />} />
          <Route path="/departments/:deptId/labs/:labId/systems/:systemId" element={<SystemDetail />} />
          <Route path="/systems" element={<Systems />} />
          <Route path="/analytics" element={<Analytics />} />
          <Route path="/alerts" element={<Alerts />} />
        </Routes>
      </div>
    </Router>
  )
}

export default App
