# OptiLab Backend API

REST API for managing lab resources, systems, and metrics data.

## Base URL
```
http://localhost:3000
```

## Authentication
No authentication required for development.

## Response Format
All responses are in JSON format.

## Error Responses
```json
{
  "error": "Error message"
}
```

---

## HOD (Head of Department) Management

### Get All HODs
- **GET** `/hod`
- **Response:** Array of HOD objects

### Add New HOD
- **POST** `/hod`
- **Request Body:**
  ```json
  {
    "hod_name": "Dr. John Smith",
    "hod_email": "smith@rvce.edu"
  }
  ```
- **Response:** Created HOD object

---

## Department Management

### Get All Departments
- **GET** `/departments`
- **Response:** Array of department objects

### Add New Department
- **POST** `/departments`
- **Request Body:**
  ```json
  {
    "name": "Computer Science",
    "code": "CSE",
    "vlan": 100,
    "subnet": "192.168.1.0/24",
    "description": "Computer Science Department",
    "hodID": 1
  }
  ```
- **Response:** Created department object

### Get Department by ID
- **GET** `/departments/:deptID`
- **Parameters:** `deptID` (integer)
- **Response:** Department object

### Update Department
- **PUT** `/departments/:deptID`
- **Parameters:** `deptID` (integer)
- **Request Body:** Same as POST
- **Response:** Updated department object

### Delete Department
- **DELETE** `/departments/:deptID`
- **Parameters:** `deptID` (integer)
- **Response:** Success message

---

## Lab Management

### Get Labs by Department
- **GET** `/departments/:deptID/labs`
- **Parameters:** `deptID` (integer)
- **Response:** Array of lab objects

### Add New Lab
- **POST** `/departments/:deptID/labs`
- **Parameters:** `deptID` (integer)
- **Request Body:**
  ```json
  {
    "number": 101
  }
  ```
- **Response:** Created lab object

---

## Faculty (Lab Assistant) Management

### Get Lab Assistants by Department
- **GET** `/departments/:deptID/faculty`
- **Parameters:** `deptID` (integer)
- **Response:** Array of lab assistant objects

### Add New Lab Assistant
- **POST** `/departments/:deptID/faculty`
- **Parameters:** `deptID` (integer)
- **Request Body:**
  ```json
  {
    "name": "Jane Doe",
    "email": "jane@rvce.edu",
    "labID": 1
  }
  ```
- **Response:** Created lab assistant object

---

## System Metrics

### Get Latest Metrics
- **GET** `/departments/:deptID/labs/:labID/sysID/:sysID`
- **Parameters:** `deptID`, `labID`, `sysID` (integers)
- **Response:** Latest metrics object

### Get Raw Metrics History
- **GET** `/departments/:deptID/labs/:labID/sysID/:sysID/metrics`
- **Parameters:** `deptID`, `labID`, `sysID` (integers)
- **Query Parameters:**
  - `limit` (integer, default: 100)
  - `hours` (integer, default: 24)
- **Response:** Array of metrics objects

### Get Hourly Aggregated Stats
- **GET** `/departments/:deptID/labs/:labID/sysID/:sysID/hourly`
- **Parameters:** `deptID`, `labID`, `sysID` (integers)
- **Query Parameters:**
  - `hours` (integer, default: 24)
- **Response:** Hourly statistics

### Get Daily Aggregated Stats
- **GET** `/departments/:deptID/labs/:labID/sysID/:sysID/daily`
- **Parameters:** `deptID`, `labID`, `sysID` (integers)
- **Query Parameters:**
  - `days` (integer, default: 30)
- **Response:** Daily statistics

### Get Performance Summary
- **GET** `/departments/:deptID/labs/:labID/sysID/:sysID/summary`
- **Parameters:** `deptID`, `labID`, `sysID` (integers)
- **Query Parameters:**
  - `days` (integer, default: 7)
- **Response:** Performance summary

---

## Maintenance Logs

### Get Maintenance Logs by Lab
- **GET** `/departments/:deptID/labs/:labID/maintenance`
- **Parameters:** `deptID`, `labID` (integers)
- **Response:** Array of maintenance log objects

### Add Maintenance Log
- **POST** `/departments/:deptID/labs/:labID/maintenance`
- **Parameters:** `deptID`, `labID` (integers)
- **Request Body:**
  ```json
  {
    "system_id": 1,
    "date_at": "2023-12-07T10:00:00Z",
    "isACK": false,
    "ACKat": null,
    "ACKby": null,
    "resolved_at": null,
    "severity": "high",
    "message": "System overheating"
  }
  ```
- **Response:** Created maintenance log object

---

## Data Types

### HOD Object
```json
{
  "hod_id": 1,
  "hod_name": "Dr. John Smith",
  "hod_email": "smith@rvce.edu"
}
```

### Department Object
```json
{
  "dept_id": 1,
  "dept_name": "Computer Science",
  "dept_code": "CSE",
  "vlan_id": 100,
  "subnet_cidr": "192.168.1.0/24",
  "description": "Computer Science Department",
  "hod_id": 1
}
```

### Lab Object
```json
{
  "lab_id": 1,
  "lab_dept": 1,
  "lab_number": 101
}
```

### Lab Assistant Object
```json
{
  "lab_assistant_id": 1,
  "lab_assistant_name": "Jane Doe",
  "lab_assistant_email": "jane@rvce.edu",
  "lab_assistant_dept": 1,
  "lab_assigned": 1
}
```

### Metrics Object
```json
{
  "metric_id": 1,
  "system_id": 1,
  "timestamp": "2023-12-07T10:00:00Z",
  "cpu_percent": 45.5,
  "ram_percent": 60.2,
  "disk_percent": 30.1,
  "gpu_percent": 20.0
}
```

### Maintenance Log Object
```json
{
  "maintainence_id": 1,
  "system_id": 1,
  "lab_id": 1,
  "date_at": "2023-12-07T10:00:00Z",
  "is_acknowledged": false,
  "acknowledged_at": null,
  "acknowledged_by": null,
  "resolved_at": null,
  "severity": "high",
  "message": "System overheating"
}
```

---

## Running the Backend

```bash
cd backend
npm install
npm run dev
```

Server will start on `http://localhost:3000`

## Testing with Thunder Client

Use Thunder Client extension in VS Code to test the API endpoints. Set the base URL to `http://localhost:3000` and use the endpoints listed above.