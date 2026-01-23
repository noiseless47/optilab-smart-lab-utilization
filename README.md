# 🏫 OptiLab - Smart Lab Resource Monitoring System

### Agentless Network-Based Monitoring for Academic Computer Labs

> **Production-grade, scalable monitoring platform for agentless lab resource tracking**

[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-18-316192.svg)](https://www.postgresql.org/)
[![Python](https://img.shields.io/badge/Python-3.8%2B-green.svg)](https://www.python.org/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115+-009688.svg)](https://fastapi.tiangolo.com/)
[![TimescaleDB](https://img.shields.io/badge/TimescaleDB-2.0%2B-orange.svg)](https://www.timescale.com/)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## 📋 Overview

A comprehensive **Database Management System (DBMS) project** that monitors computer lab resources in real-time using **agentless network-based collection**. Simply provide an IP range or VLAN address (e.g., `10.30.0.0/16` for ISE department) and the system automatically discovers all computers, collects metrics remotely, and generates data-backed optimization recommendations using advanced SQL analytics.

**🎯 Key Innovation**: Zero Friction Deployment - No agent installation on target machines! Just provide network range → automatic discovery

---

## ✨ Features

### 🌐 Network Auto-Discovery (Agentless!)
- **Zero Friction**: Provide IP range → Auto-discover all systems
- **No Agent Install**: Uses standard protocols (SNMP, WMI, SSH) - no software on target machines
- **Department Organization**: Systems automatically grouped by VLAN
- **Nmap Integration**: Fast, accurate network scanning

### 🔍 Real-Time Monitoring
- **Granular Metrics**: CPU, RAM, GPU, Disk I/O, Network every 5 minutes
- **Multi-Protocol**: WMI (Windows), SSH (Linux), SNMP (Universal)
- **Multi-Platform**: Windows, Linux, macOS support
- **Automated Collection**: Scheduled jobs handle everything

### 📊 Advanced Analytics
- **Utilization Scoring**: Composite efficiency metrics (0-100)
- **Bottleneck Detection**: Automated CPU/RAM/Disk identification
- **Trend Analysis**: Time-series pattern recognition
- **Percentile Queries**: P95, P99 for capacity planning

### 🚨 Intelligent Alerting
- **Trigger-Based**: Real-time alerts via database triggers
- **Smart Thresholds**: Configurable rules with duration logic
- **Auto-Resolution**: Alerts close automatically when conditions normalize
- **Severity Levels**: Info, Warning, Critical

### ⚡ Performance Optimized
- **TimescaleDB**: Automatic time-series partitioning
- **Compression**: 90% space savings after 7 days
- **Continuous Aggregates**: Pre-computed summaries (50-100x faster)
- **Smart Indexing**: Partial, GIN, composite indexes

---

## 🚀 How It Works (Agentless Approach)

```
1️⃣  Admin Input: "Monitor ISE department (10.30.0.0/16)"
                ↓
2️⃣  Network Scan: nmap discovers all active computers
                ↓
3️⃣  Auto-Detect: Identifies OS type (Windows/Linux)
                ↓
4️⃣  Remote Collection: WMI/SSH/SNMP collects metrics
                ↓
5️⃣  Database Storage: PostgreSQL with department tags
                ↓
6️⃣  Analytics: SQL procedures generate insights
```

**Key Advantage**: Deploy once on central server → Monitor 100+ computers automatically!

---

## 🏗️ Architecture

[docs/architecture_diagram.png](Architecture_Diagram)

---

## 📊 Database Schema
[docs/schema_diagram.png](Schema_Diagram)

---

## 🎓 DBMS Concepts Demonstrated

### ✅ Core Database Concepts
- Schema design & normalization (3NF)
- Primary/Foreign keys & constraints
- Indexes (B-tree, GIN, Partial)
- Views & Materialized Views
- Transactions & ACID properties

### ✅ Advanced SQL Features
- **Triggers**: BEFORE/AFTER, FOR EACH ROW
- **Stored Procedures**: PL/pgSQL programming
- **Window Functions**: PERCENTILE_CONT, RANK, LAG
- **CTEs**: Common Table Expressions
- **JSONB**: Flexible data storage & GIN indexing

### ✅ Time-Series Optimization
- **Hypertables**: Automatic partitioning by time
- **Compression**: 90% space reduction
- **Continuous Aggregates**: Materialized views on steroids
- **Retention Policies**: Auto-delete old data

---

## 📈 Sample Results

### Real-World Impact (Hypothetical 50-System Lab)

**Resource Waste Identified:**
- 15 systems with <25% avg CPU+RAM → **Consolidation candidates**
- Potential savings: **$20K** avoided hardware purchases

**Performance Bottlenecks:**
- 8 systems with P95 RAM > 85% → **RAM upgrade needed**
- 3 systems with high I/O wait → **SSD upgrade recommended**

**Efficiency Gains:**
- **30%** better resource utilization
- **40%** faster issue identification
- **100%** data-backed decisions

---

## 🛠️ Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Database | PostgreSQL 14+ | Core RDBMS with INET/MACADDR types |
| Time-Series | TimescaleDB 2.0+ | Hypertables & compression |
| Backend | Python 3.8+ | Network collector service |
| Network Discovery | nmap / python-nmap | Auto-discover systems by IP range |
| Windows Collection | WMI (pywin32) | Remote Windows metrics |
| Linux Collection | SSH (paramiko) | Remote Linux metrics |
| Universal Collection | SNMP (pysnmp) | Cross-platform device monitoring |
| API Framework | FastAPI | REST endpoints (optional) |
| DB Driver | psycopg2 | PostgreSQL connection |
| Security | pgcrypto | Credential encryption |

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [docs/QUICKSTART.md](QUICKSTART.md) | 15-minute quick start 
| [docs/SETUP.md](docs/SETUP.md) | Detailed installation 
| [docs/DATABASE_DESIGN.md](docs/DATABASE_DESIGN.md) | Schema & design patterns 


---

## 🎯 Use Cases

### 1. Academic Computer Labs (Primary!)
- **Zero Friction**: Provide VLAN/IP range → Instant monitoring
- Monitor all lab machines without touching them
- Department-wise organization (ISE, CSE, ECE)
- Identify upgrade needs across 100+ systems
- Justify hardware budgets with data

### 2. Multi-Department IT Management
- Single database for entire institution
- Subnet-based queries: "Show me all CSE department systems"
- Track resource usage by VLAN/department
- Network-aware analytics with INET types

### 3. Research Computing
- Monitor shared clusters without agent installation
- Track GPU/CPU utilization remotely
- SNMP support for network devices
- Capacity planning with historical trends

---

## 🔒 Security

### Bastion Host Support 🆕
- **Jump Host Architecture**: All SSH connections route through bastion host
- **Centralized Access Control**: Single entry point for all target systems
- **Enhanced Security**: Target systems only accept connections from bastion
- **Complete Audit Trail**: All access logged through bastion
- **Easy Configuration**: Enable/disable with single flag
- **Documentation**: See [BASTION_HOST_SETUP.md](docs/BASTION_HOST_SETUP.md)

### Network Security
- **Collector Isolation**: Single collector machine with network access
- **Firewall Rules**: Limit WMI (135, 445), SSH (22), SNMP (161) to collector IP
- **No Inbound Connections**: Target systems never accept connections
- **VLAN Segmentation**: Leverage existing network security boundaries

---

## 🔮 Future Enhancements

### Phase 2: Machine Learning
- Predictive failure detection
- Anomaly detection (ML-based)
- Workload forecasting
- Automated resource scheduling

### Phase 3: Advanced Features
- Multi-campus federation
- Real-time streaming (Kafka)
- Mobile app (React Native)
- Energy efficiency tracking

---

## 🤝 Contributing

This is an academic project, but contributions are welcome!

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

---

## 📜 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file for details.

---

## 👨‍💻 Author

**Aayush Pandey and Asish Kumar Yeleti**  
Academic Year: 2025-2026  
Information Science Department

---

## 🙏 Acknowledgments

- **Network Administrator** - For agentless architecture requirements
- PostgreSQL Development Group - Native network type support
- TimescaleDB Team - Time-series optimization
- nmap Project - Network discovery foundation
- Academic advisors and instructors


**Version**: 1.0

---

<div align="center">

**Built with ❤️ using PostgreSQL, TimescaleDB, Python, and FastAPI**

[Documentation](docs/) • [Setup Guide](docs/SETUP.md)

</div>
