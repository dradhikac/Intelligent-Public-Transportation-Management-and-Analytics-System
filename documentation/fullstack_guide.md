# TransitIQ – Full-Stack System Guide

Welcome to **TransitIQ** (Intelligent Public Transportation Management and Analytics System).

This document provides complete instructions for configuring, launching, and operating both the **Backend REST API** and the **Interactive Frontend Dashboard**.

---

## 1. System Architecture

TransitIQ is built with a high-performance, three-tier architecture:

```text
┌────────────────────────────────────────────────────────────────────────┐
│                      FRONTEND PRESENTATION LAYER                       │
│  - Modern Single-Page Application (HTML5, Vanilla CSS3, ES6 JavaScript) │
│  - Real-time KPI dashboards, Chart.js metrics & trends                 │
│  - Interactive Leaflet.js Geospatial Transit Route & Stop Map          │
│  - Action Modals (Dispatch Trips, Log Delays, Record Passenger Flow)   │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ HTTP / REST / JSON
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        BACKEND APPLICATION TIER                        │
│  - FastAPI asynchronous Python web framework (localhost:8000)          │
│  - Auto-generated OpenAPI / Swagger UI interactive documentation      │
│  - Connection Pooling with psycopg2.pool.ThreadedConnectionPool        │
│  - 9 domain-driven routers (Fleet, Routes, Trips, Delays, Audit, etc.) │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ Native PostgreSQL Wire Protocol
                                    ▼
┌────────────────────────────────────────────────────────────────────────┐
│                   ENTERPRISE POSTGRESQL 18 DATABASE                    │
│  - 17 3NF Operational Tables (Buses, Drivers, Routes, Schedules, etc.) │
│  - 5 Analytical Materialized / Production Views                        │
│  - 9 Stored Functions (Metrics, license checks, delay severity)        │
│  - 3 Atomic Stored Procedures (Trip dispatch, delays, maintenance)     │
│  - 8 Audit & Business Rule Automation Triggers                         │
│  - RBAC Security (5 Groups, RLS Policies, Audit Trail)                 │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Prerequisites

1. **PostgreSQL 18** installed and running on `localhost:5432`.
   - Database name: `transitiq_db`
   - Operational schema and tables populated via scripts `01_create_tables.sql` through `10_triggers.sql`.
2. **Python 3.10+** (tested on Python 3.11).
3. **Node.js v18+** (optional, for frontend package manager scripts).

---

## 3. Installation & Configuration

### Step 1: Install Python Dependencies

From the project root directory, install required backend packages:

```bash
pip install -r backend/requirements.txt
```

### Step 2: Configure Environment Variables

Create a `.env` file in the project root directory or inside `backend/` by copying `.env.example`:

```bash
# Windows PowerShell
Copy-Item .env.example .env
```

Edit `.env` with your PostgreSQL password:

```ini
DB_HOST=localhost
DB_PORT=5432
DB_NAME=transitiq_db
DB_USER=postgres
DB_PASSWORD=your_actual_postgres_password

HOST=0.0.0.0
PORT=8000
DEBUG=False
```

*(Note: If `DB_PASSWORD` or `PGPASSWORD` is already set in your Windows environment, TransitIQ automatically detects and uses it).*

---

## 4. Running the Project

You can start the unified application with a single command:

### Option A: Using Python (Recommended)

```bash
python backend/run.py
```

### Option B: Using npm

```bash
cd frontend
npm start
```

### Option C: Using Uvicorn CLI

```bash
uvicorn backend.main:app --host 0.0.0.0 --port 8000 --reload
```

---

## 5. Accessing the Applications

Once started, the server exposes the following interfaces:

| Interface | URL | Description |
| :--- | :--- | :--- |
| **Interactive Dashboard** | [http://localhost:8000/](http://localhost:8000/) | Full-featured operator and analytics SPA dashboard |
| **Alternative Dashboard Route** | [http://localhost:8000/dashboard](http://localhost:8000/dashboard) | Alias routing to the dashboard SPA |
| **Swagger / OpenAPI Documentation** | [http://localhost:8000/docs](http://localhost:8000/docs) | Interactive API exploration and testing interface |
| **ReDoc API Documentation** | [http://localhost:8000/redoc](http://localhost:8000/redoc) | Clean, searchable technical API specifications |
| **System Health Check** | [http://localhost:8000/api/system/health](http://localhost:8000/api/system/health) | Live PostgreSQL connection and table count diagnostic |

---

## 6. Frontend Features & Capabilities

The TransitIQ dashboard delivers:

1. **Executive Overview Tab**:
   - Live KPI cards: Active Buses, In-Transit Trips, Completed Trips, On-Time Performance Rate, and Peak Passengers.
   - Interactive Chart.js charts: Daily trip status distributions and hourly passenger demand patterns.
2. **Fleet Management Tab**:
   - Real-time bus roster with dynamic badges for operational status (`IN_SERVICE`, `MAINTENANCE`, `OUT_OF_SERVICE`).
   - Modal action to trigger `sp_complete_maintenance` and inspect vehicle utilization rates.
3. **Interactive Route & Geospatial Map Tab**:
   - Leaflet.js interactive map plotting operational bus stops with real-time GPS coordinates.
   - Route details including distance, estimated duration, and stop sequence ordering.
4. **Trip Operations Tab**:
   - Live trip monitoring with timestamps and driver assignments.
   - Modal form enabling dispatchers to execute `sp_create_trip` with automated constraint checking and schedule validation.
5. **Passenger Analytics Tab**:
   - Visual inspection of `vw_passenger_demand` across high-volume transit corridors.
   - Modal action to execute `sp_record_passenger_count` recording boardings and alightings.
6. **Delay Analysis Tab**:
   - Breakdown of delay causes, affected routes, and severity ratings computed via `fn_calculate_delay_severity`.
   - Dispatcher modal to execute `sp_record_delay`.
7. **Driver Performance & Safety Tab**:
   - Driver credential audits displaying license expiration alerts via `fn_check_license_expiry`.
   - Driver performance score calculations via `fn_get_driver_performance`.
8. **Compliance & Audit Log Tab**:
   - Real-time viewer querying `audit_logs` populated by database security and audit triggers.

---

## 7. Backend API Endpoint Catalog

All API endpoints are prefixed with `/api` and return standardized JSON responses:

- **System**:
  - `GET /api/system/health`: PostgreSQL connection status, database version, and operational table metrics.
- **Analytics**:
  - `GET /api/analytics/kpis`: Summary metrics (buses, drivers, trips, passenger totals).
  - `GET /api/analytics/views/fleet-utilization`: Results from `vw_fleet_utilization`.
  - `GET /api/analytics/views/route-performance`: Results from `vw_route_performance`.
  - `GET /api/analytics/views/driver-performance`: Results from `vw_driver_performance`.
  - `GET /api/analytics/views/delay-analysis`: Results from `vw_delay_analysis`.
  - `GET /api/analytics/views/passenger-demand`: Results from `vw_passenger_demand`.
- **Fleet**:
  - `GET /api/fleet/buses`: Bus list with optional status filtering.
  - `GET /api/fleet/bus-types`: Vehicle specifications and fuel types.
  - `GET /api/fleet/maintenance`: Active and completed maintenance logs.
  - `POST /api/fleet/maintenance/complete`: Triggers maintenance resolution.
- **Routes**:
  - `GET /api/routes`: Route catalog.
  - `GET /api/routes/{id}/stops`: Sequential stop sequence with GPS coordinates.
- **Trips**:
  - `GET /api/trips`: Filterable trip roster.
  - `POST /api/trips/dispatch`: Invokes stored procedure `sp_create_trip`.
  - `PATCH /api/trips/{id}/status`: Updates trip lifecycle status.
- **Passengers**:
  - `GET /api/passengers/summary`: Aggregated boarding and alighting stats.
  - `POST /api/passengers/record`: Invokes stored procedure `sp_record_passenger_count`.
- **Delays**:
  - `GET /api/delays`: Historical delay records.
  - `POST /api/delays/record`: Invokes stored procedure `sp_record_delay`.
- **Drivers**:
  - `GET /api/drivers`: Driver records, license verification, and safety scores.
- **Audit**:
  - `GET /api/audit/logs`: Filterable tamper-evident database audit trail.
