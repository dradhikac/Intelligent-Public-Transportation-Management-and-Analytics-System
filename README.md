# TransitIQ – Intelligent Public Transportation Management and Analytics System

An enterprise platform designed for public transportation fleet management, intelligent scheduling, real-time dispatch, route analytics, and performance monitoring built over PostgreSQL 18.

---

## Quick Start (Run the Complete System)

TransitIQ includes a unified server that serves both the **FastAPI REST API** and the **Interactive Frontend Single-Page Application (SPA)** simultaneously on port 8000.

### 1. Install Dependencies
```bash
pip install -r backend/requirements.txt
```

### 2. Configure Environment (Optional)
If your PostgreSQL credentials differ from default `postgres / postgres`, copy `.env.example` to `.env` and set your credentials:
```bash
# Windows PowerShell
Copy-Item .env.example .env
```

### 3. Launch the Server
```bash
python backend/run.py
```
*Or via npm:*
```bash
cd frontend && npm start
```

### 4. Open in Your Browser
- **Interactive Transit Dashboard**: [http://localhost:8000/](http://localhost:8000/)
- **Interactive Swagger REST API Docs**: [http://localhost:8000/docs](http://localhost:8000/docs)
- **Technical ReDoc Specifications**: [http://localhost:8000/redoc](http://localhost:8000/redoc)
- **System Diagnostic Health Check**: [http://localhost:8000/api/system/health](http://localhost:8000/api/system/health)

For an in-depth walkthrough of the system architecture and features, see the [Full-Stack System Guide](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/documentation/fullstack_guide.md).

---

## Project Structure

```text
Intelligent-Public-Transportation-Management-and-Analytics-System/
├── backend/                  # FastAPI Application Tier
│   ├── config.py             # Environment & database settings (.env support)
│   ├── database.py           # Threaded connection pool & query managers
│   ├── main.py               # FastAPI application, CORS, static SPA hosting
│   ├── run.py                # Standalone startup runner script
│   ├── requirements.txt      # Python dependencies (FastAPI, psycopg2, uvicorn)
│   └── routers/              # Domain-driven REST API routers:
│       ├── analytics.py      # Executive KPIs & 5 production views
│       ├── audit.py          # Compliance & audit log viewer
│       ├── delays.py         # Delay tracking & sp_record_delay
│       ├── drivers.py        # Driver safety, license checks, performance
│       ├── fleet.py          # Bus inventory, types, sp_complete_maintenance
│       ├── passengers.py     # Passenger telemetry & sp_record_passenger_count
│       ├── routes.py         # Route catalog & GPS stop coordinates
│       ├── system.py         # Live health & DB connection diagnostics
│       └── trips.py          # Trip monitoring & sp_create_trip dispatch
├── frontend/                 # Client-Side Dashboard Application
│   ├── index.html            # 8-tab SPA (Executive, Fleet, Map, Trips, Delays, etc.)
│   ├── package.json          # Node scripts ("npm start", "npm run serve")
│   └── static/
│       ├── style.css         # Dark theme UI, badges, cards, responsive layout
│       └── app.js            # Chart.js charts, Leaflet.js map, API integration
├── database/                 # PostgreSQL 18 Database Engine
│   ├── 01_create_tables.sql  # 17 3NF operational tables
│   ├── 02_constraints.sql    # Relational integrity, foreign keys & checks
│   ├── 03_indexes.sql        # High-performance B-tree & composite indexes
│   ├── 04_seed_data.sql      # Realistic metropolitan transit seed dataset
│   ├── 06_analytics_views.sql# 5 Analytical views (Fleet, Route, Driver, Delay, Demand)
│   ├── 07_functions.sql      # 9 PL/pgSQL business logic functions
│   ├── 08_procedures.sql     # 3 Atomic stored procedures
│   ├── 10_triggers.sql       # 8 Audit & automation triggers
│   ├── 13-18_transactions/   # Concurrency & transaction management demos
│   ├── 19-24_security/       # RBAC roles, grants & row-level security policies
│   ├── 25-30_optimization/   # Query plans, indexes & performance benchmarks
│   └── 31-32_backup/         # Disaster recovery, logical backups & restore
├── scripts/                  # Administrative & backup PowerShell scripts
├── documentation/            # Technical architecture, schemas & guides
└── README.md                 # System overview and quick start instructions
```

---

## Key Features

1. **Integrated Geospatial Visualization**: Interactive Leaflet.js map rendering active routes and stop coordinates.
2. **Real-Time Fleet & Trip Monitoring**: Live status tracking for buses (`IN_SERVICE`, `MAINTENANCE`) and scheduled trips.
3. **Database Stored Procedure Execution**: UI modal dialogs to trigger PostgreSQL stored procedures:
   - `sp_create_trip`: Dispatches new trips with automated driver and bus availability checks.
   - `sp_record_delay`: Logs delay events with automated severity computation.
   - `sp_record_passenger_count`: Ingests stop-level boardings and alightings.
4. **Comprehensive SQL Analytics**: Visualized charts powered directly by PostgreSQL views (`vw_passenger_demand`, `vw_route_performance`, `vw_fleet_utilization`, `vw_delay_analysis`, `vw_driver_performance`).
5. **Auditing & Governance**: Real-time display of tamper-evident audit logs generated by database triggers.
