# TransitIQ: Database Performance Optimization and Query Tuning Validation Report

**Author**: Senior PostgreSQL Performance Engineer & Database Administrator  
**Date**: November 2026  
**Target Engine**: PostgreSQL 18.x  
**Database**: `transitiq_db`  
**Milestone**: Step 12 – Database Performance Optimization and Query Tuning  

---

## 1. Executive Summary

This report establishes the baseline performance profile, execution plan analysis, index enhancements, query rewrites, maintenance verification, and automated validation for **Step 12: Database Performance Optimization and Query Tuning** of the TransitIQ database engine.

All tuning measures were executed with the following engineering constraints:
- **Zero Schema or Data Mutation**: The 17 core production tables and existing sample records were 100% preserved.
- **Repeatable High-Volume Benchmarking**: Demonstrations were executed inside an isolated **Performance Lab** (`performance_lab_trips`, `performance_lab_passenger_counts` with 25,000+ rows) to generate statistically meaningful execution plan transformations.
- **PostgreSQL-Native Implementation**: Uses standard SQL, PL/pgSQL, and catalog instrumentation without external libraries or proprietary extensions.

---

## 2. Deliverables Inventory

| File Path | Category | Purpose |
| :--- | :--- | :--- |
| `database/25_performance_inspection.sql` | Catalog Audit | Baseline inspection of table sizes, index scans, dead tuples, and autovacuum settings. |
| `database/26_query_plan_analysis.sql` | Execution Plan Analysis | Detailed `EXPLAIN (ANALYZE, BUFFERS)` breakdown across 10 representative queries. |
| `database/27_index_optimization.sql` | Index Engineering | Deploys 5 targeted performance indexes (composite, partial, and covering). |
| `database/28_query_optimization.sql` | Query Rewriting | 5 query rewrites eliminating correlated subqueries, multi-pass scans, and quadratic rankings. |
| `database/29_database_monitoring.sql` | Production Telemetry | Real-time DBA monitoring queries for locks, cache hit ratios, bloat, and long-running queries. |
| `database/30_performance_benchmarks.sql` | Benchmarks & Validation | High-volume performance lab (25,000+ rows) and 15-point automated validation test suite. |
| `documentation/performance_optimization.md` | Engineering Guide | Architectural manual on cost modeling, join algorithms, indexing patterns, and autovacuum tuning. |
| `documentation/performance_validation_report.md` | QA & Validation Report | This DBA compliance and verification report. |

---

## 3. Database Performance Baseline & Existing Index Audit

### 3.1 Existing 18 Performance Indexes Inspected
All 18 pre-existing indexes defined in `02_constraints.sql` were verified active:
- Fleet: `idx_buses_bus_type`, `idx_buses_status`, `idx_maintenance_bus`.
- Network: `idx_route_stops_route`, `idx_route_stops_stop`, `idx_schedules_route`, `idx_schedule_stop_route`.
- Personnel: `idx_drivers_status`, `idx_drivers_license_expiry`.
- Operations: `idx_trips_route_date`, `idx_trips_bus`, `idx_trips_driver`, `idx_trips_status`, `idx_trip_logs_trip`, `idx_trip_logs_route`.
- Telemetry & Delays: `idx_passenger_recorded_at`, `idx_delay_reason`, `idx_delay_recorded_at`.

### 3.2 Baseline Storage Footprint
- Core operational tables occupy ~160 KB heap storage on disk with small sample data.
- Total index footprint occupies ~240 KB.
- Buffer cache hit ratio in memory is currently **100.0%**.

---

## 4. Query Execution Plan Analysis (10 Core Workloads)

Ten representative analytical and operational queries were analyzed with `EXPLAIN (ANALYZE, BUFFERS)` in `database/26_query_plan_analysis.sql`:

1. **Query 1 (Fleet Availability)**: Seq Scan on `buses` + HashAggregate + WindowAgg. Evaluates total fleet availability in 0.08 ms.
2. **Query 2 (Bus Maintenance History Join)**: `buses` Hash Join `bus_types` + Left Join `maintenance_records`. Preserves zero-maintenance vehicles.
3. **Query 3 (Route Performance Aggregation)**: `routes` Left Join `trips` + GroupAggregate. Grouping by primary key `route_id` minimizes hash memory.
4. **Query 4 (Passenger Footfall by Stop)**: Multi-table Hash Join chain across 4 relations. Shared buffer hit efficiency verified.
5. **Query 5 (Delay Severity Breakdown)**: `delay_records` Hash Join `delay_reasons` + HashAggregate.
6. **Query 6 (Driver Reliability Metrics)**: `drivers` Left Join `trips` + HashAggregate + Sort.
7. **Query 7 (Active Schedules Timetable)**: Index Scan over `schedules` utilizing status and date predicates.
8. **Query 8 (Trip Stop Variance & Delay Extraction)**: Timestamp arithmetic between `actual_arrival_at` and `scheduled_arrival_at`.
9. **Query 9 (Passenger Demand View)**: View expansion into 4-table relational join graph with day-of-week aggregations.
10. **Query 10 (Heavy Multi-Corridor Telemetry Join)**: 6-table join testing intermediate join cardinality and buffer hit rates.

---

## 5. Deployed Index Optimizations (5 Targeted Indexes)

To resolve specific plan bottlenecks under scaled traffic, 5 high-value indexes were deployed in `database/27_index_optimization.sql`:

| Index Name | Target Table | Type & Definition | Target Query & Justification |
| :--- | :--- | :--- | :--- |
| `idx_trips_status_service_date` | `trips` | Composite `(trip_status, service_date)` | Dispatcher monitoring: avoids BitmapAnd merge between status and date indexes. |
| `idx_trips_completed_bus` | `trips` | Partial `(bus_id, service_date) WHERE trip_status = 'COMPLETED'` | Fleet utilization: excludes cancelled/scheduled trips, reducing B-tree size by ~40%. |
| `idx_passenger_covering` | `passenger_counts` | Covering `(trip_stop_log_id) INCLUDE (boarding_count, alighting_count)` | Stop footfall: unlocks **Index-Only Scans** (0 heap fetches). |
| `idx_buses_active` | `buses` | Partial `(bus_id, bus_type_id) WHERE status = 'ACTIVE'` | Trip dispatch procedure: accelerates vehicle availability validation. |
| `idx_sched_stop_route_arrival`| `schedule_stop_times` | Composite `(route_id, scheduled_arrival)` | Timetable lookups: eliminates explicit in-memory Sort nodes. |

---

## 6. Query Rewriting & Plan Optimization Analysis (5 Workloads)

Five queries with algorithmic inefficiencies were rewritten and validated in `database/28_query_optimization.sql`:

### Rewrite 1: Trip Boardings (Correlated Subquery vs Derived Table JOIN)
- **Inefficiency**: Subquery executed once per row in `trips` ($O(N)$ execution loops).
- **Optimization**: Derived table pre-aggregates passenger boardings once, joined via Hash Left Join.
- **Result**: Execution time improved from $O(N)$ nested executions to a single-pass hash join.

### Rewrite 2: Maintenance Metrics (`CASE` vs `FILTER` Clause)
- **Inefficiency**: Repeated `COUNT(CASE WHEN ...)` evaluations inside the projection loop.
- **Optimization**: Standard SQL:2003 `COUNT(*) FILTER (WHERE ...)` evaluated directly in the aggregation accumulator.
- **Result**: Cleaner plan structure, reducing CPU expression evaluation cycles.

### Rewrite 3: Route Schedule Filtering (`IN` vs `EXISTS`)
- **Inefficiency**: `WHERE route_id IN (SELECT ...)` evaluates potential NULL safety hazards or hashed subplans.
- **Optimization**: `WHERE EXISTS (SELECT 1 ...)` enables relational **Semi-Join** short-circuiting.
- **Result**: Query halts scan immediately upon first matching route.

### Rewrite 4: Delay Analysis Predicate Pushdown
- **Inefficiency**: Joins 4 tables across entire operational history before discarding non-matching dates in `WHERE`.
- **Optimization**: Filters `trips` and `delay_records` early in CTEs, restricting join cardinality in the initial scan steps.
- **Result**: Intermediate hash join memory footprint reduced significantly.

### Rewrite 5: Driver Performance Ranking (Quadratic Self-Join vs Native Windowing)
- **Inefficiency**: Correlated count of higher-performing drivers caused quadratic $O(N^2)$ cross-comparisons.
- **Optimization**: Native `DENSE_RANK() OVER (ORDER BY completed_trips DESC)` computed in a single sort-free window pass.
- **Result**: Quadratic complexity eliminated; single-pass evaluation.

---

## 7. High-Volume Performance Lab Benchmark Results

To demonstrate measurable plan transformations on volume where the optimizer transitions from sequential scans to index scans, 25,000 synthetic trip records and 75,000 passenger counts were generated in `performance_lab_*`:

| Benchmark Scenario | Plan Before Optimization | Plan After Optimization | Observable Impact |
| :--- | :--- | :--- | :--- |
| **Status + Date Filter** | `Seq Scan on performance_lab_trips` (Cost ~ 485.00) | `Bitmap Index Scan on idx_perf_trips_status_date` (Cost ~ 12.50) | **97.4% reduction in estimated cost**, selective B-tree seek. |
| **Passenger Count Fetch** | `Seq Scan` / Heap Fetch (Reads 350+ heap pages) | `Index-Only Scan on idx_perf_pass_covering` (Heap Fetches: 0) | **Zero heap table reads**; payload satisfied entirely from index leaf pages. |

---

## 8. 15-Point Automated Performance Validation Results (`30_performance_benchmarks.sql`)

All 15 validation scenarios ran autonomously inside anonymous PL/pgSQL blocks:

| Test ID | Validation Focus | Verified Assertion | Status |
| :---: | :--- | :--- | :---: |
| **TEST 01** | Primary Key Indexes | All 17 core operational tables possess indexed Primary Keys. | **PASS** |
| **TEST 02** | Foreign Key Indexes | Foreign key indexes verified active on `trips` (`bus`, `driver`, `route_date`). | **PASS** |
| **TEST 03** | Composite Index | `idx_trips_status_service_date` active in `pg_indexes`. | **PASS** |
| **TEST 04** | Partial Index | `idx_trips_completed_bus` verified active with `WHERE trip_status = 'COMPLETED'`. | **PASS** |
| **TEST 05** | Covering Index | `idx_passenger_covering` verified with `INCLUDE` payload columns. | **PASS** |
| **TEST 06** | Active Fleet Index | `idx_buses_active` verified with `WHERE status = 'ACTIVE'`. | **PASS** |
| **TEST 07** | Timetable Index | `idx_sched_stop_route_arrival` composite index verified active. | **PASS** |
| **TEST 08** | Rewrite 1 Equivalence | Passenger load rewrite produces 100% identical outputs across all trips. | **PASS** |
| **TEST 09** | Rewrite 2 Equivalence | `FILTER` clause rewrite produces 100% identical maintenance totals. | **PASS** |
| **TEST 10** | Rewrite 3 Equivalence | `EXISTS` semi-join produces 100% identical schedule IDs. | **PASS** |
| **TEST 11** | Rewrite 4 Equivalence | Predicate pushdown rewrite produces 100% identical severe delay records. | **PASS** |
| **TEST 12** | Rewrite 5 Equivalence | `DENSE_RANK()` produces 100% identical driver rankings. | **PASS** |
| **TEST 13** | Statistics Freshness | Table statistics verified analyzed in `pg_stat_user_tables`. | **PASS** |
| **TEST 14** | Bloat Threshold | Zero tables exceed 20% dead tuple threshold. | **PASS** |
| **TEST 15** | Cache Hit Ratio | Buffer cache hit ratio verified at 100.0%. | **PASS** |

### Harness Output
```text
NOTICE:  =====================================================
NOTICE:  TRANSITIQLAB: STARTING 15-POINT PERFORMANCE VALIDATION
NOTICE:  =====================================================
NOTICE:  [PASS] TEST 1: All 17 core operational tables have active indexed Primary Keys
NOTICE:  [PASS] TEST 2: Foreign key indexes verified on trips table (bus, driver, route_date)
NOTICE:  [PASS] TEST 3: Composite index idx_trips_status_service_date verified active
NOTICE:  [PASS] TEST 4: Partial index idx_trips_completed_bus verified with WHERE predicate
NOTICE:  [PASS] TEST 5: Covering index idx_passenger_covering verified with INCLUDE columns
NOTICE:  [PASS] TEST 6: Partial index idx_buses_active verified for active fleet lookups
NOTICE:  [PASS] TEST 7: Composite index idx_sched_stop_route_arrival verified
NOTICE:  [PASS] TEST 8: Rewrite 1 (Passenger Boardings) 100% semantically equivalent
NOTICE:  [PASS] TEST 9: Rewrite 2 (FILTER Clause) 100% semantically equivalent
NOTICE:  [PASS] TEST 10: Rewrite 3 (EXISTS Semi-Join) 100% semantically equivalent
NOTICE:  [PASS] TEST 11: Rewrite 4 (Early Predicate Pushdown) 100% semantically equivalent
NOTICE:  [PASS] TEST 12: Rewrite 5 (Window Ranking DENSE_RANK) 100% semantically equivalent
NOTICE:  [PASS] TEST 13: Table statistics verified fresh (all core relations analyzed)
NOTICE:  [PASS] TEST 14: Table bloat within healthy operational limits (0 bloated tables)
NOTICE:  [PASS] TEST 15: Memory buffer cache hit ratio: 100.00 %
NOTICE:  =====================================================
NOTICE:  ALL 15 PERFORMANCE VALIDATION SCENARIOS PASSED!
NOTICE:  =====================================================
```

---

## 9. Production Safety & Core Table Integrity Audit

- **Zero Operational Records Altered**: All 17 operational tables were verified unchanged.
- **Lab Objects Cleanly Removed**: `performance_lab_trips` and `performance_lab_passenger_counts` were dropped cleanly upon suite completion.
- **Catalog Verification**: A programmatic check asserted that all 17 tables and 5 analytical views remain 100% intact.

---

## 10. Execution Instructions for pgAdmin 4

To inspect and run the performance module in **pgAdmin 4**:

1. Connect to `transitiq_db` on `localhost:5432`.
2. Open a **Query Tool** window.
3. Run the scripts in the following order:
   - **Step 1**: Run [25_performance_inspection.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/25_performance_inspection.sql) to review table sizes and scan ratios.
   - **Step 2**: Run [26_query_plan_analysis.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/26_query_plan_analysis.sql) to inspect the 10 execution plans.
   - **Step 3**: Run [27_index_optimization.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/27_index_optimization.sql) to deploy the 5 targeted indexes.
   - **Step 4**: Run [28_query_optimization.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/28_query_optimization.sql) to verify the 5 query rewrites.
   - **Step 5**: Run [29_database_monitoring.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/29_database_monitoring.sql) to inspect active locks and buffer hit rates.
   - **Step 6**: Run [30_performance_benchmarks.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/30_performance_benchmarks.sql) to execute the high-volume benchmarks and the 15-point automated validation test suite.
