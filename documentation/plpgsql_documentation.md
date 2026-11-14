# TransitIQ – PL/pgSQL Stored Procedures & Functions Documentation

**Project**: TransitIQ – Intelligent Public Transportation Management and Analytics System  
**Engine**: PostgreSQL 18 (Compatible with PostgreSQL 14+)  
**Database**: `transitiq_db`  
**Module**: Stored Procedures & Functions Layer  
**Files**:
- `database/07_functions.sql` (9 Production Functions)
- `database/08_procedures.sql` (3 Production Procedures)
- `database/09_routine_tests.sql` (15 Automated Test Scenarios)

---

## Architectural Overview: PostgreSQL Functions vs Stored Procedures

In PostgreSQL (introduced fully in PostgreSQL 11+ and refined in 14–18), **Functions** and **Procedures** serve distinct architectural roles:

| Feature | PL/pgSQL Function (`CREATE FUNCTION`) | PL/pgSQL Stored Procedure (`CREATE PROCEDURE`) |
| :--- | :--- | :--- |
| **Invocation** | Invoked inside SQL expressions: `SELECT * FROM fn(...)` or `SELECT fn(...)` | Invoked as standalone commands: `CALL sp(...)` |
| **Transaction Control** | **Cannot** manage transactions. Cannot execute `COMMIT` or `ROLLBACK`. Runs within the caller's transaction context. | **Can** control transactions. Can issue `COMMIT` or `ROLLBACK` mid-execution (when not called inside an outer multi-statement transaction). |
| **Return Value** | Always returns a value (scalar, record, composite, or `TABLE(...)`). | Does not return a value by default; passes data back via `INOUT` / `OUT` parameters. |
| **Primary Use Case** | Data transformation, business logic calculations, filtering, and computed reporting. | Data mutation, transactional workflow orchestration, batch dispatching, and multi-step data pipelines. |
| **Immutability & Optimization** | Can be marked `VOLATILE`, `STABLE`, or `IMMUTABLE` for planner optimization. | Always executed imperatively without planner subquery folding. |

---

## Part 1: PL/pgSQL Functions Catalog (`database/07_functions.sql`)

### MODULE A: FLEET MANAGEMENT

#### 1. `fn_get_bus_status(p_bus_id BIGINT)`
- **Purpose**: Retrieve current operational status, registration, model category, and service date for a specific bus.
- **Parameters**: `p_bus_id BIGINT` (The primary key of the bus asset).
- **Return Type**: `TABLE(bus_id BIGINT, registration_number VARCHAR(20), bus_type VARCHAR(50), operational_status VARCHAR(20), last_service_date DATE)`
- **SQL Concepts Used**: Input NULL check, `EXISTS` validation, `JOIN` with `bus_types`, custom `RAISE EXCEPTION`.
- **Business Logic**: Validates that `p_bus_id` is not null and exists in `buses`. Returns the vehicle's registration number, associated bus type (e.g. AC, Electric), current operational status (`ACTIVE`, `MAINTENANCE`, `INACTIVE`, `RETIRED`), and date of last completed overhaul.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_get_bus_status(1);
  ```
- **Error Handling**: Raises `null_value_not_allowed` if parameter is NULL; raises `no_data_found` (SQLSTATE `P0002`) if the bus ID does not exist.
- **Transit Use Case**: Depot gate controllers and dispatchers verify vehicle eligibility before assigning buses to revenue routes.

---

#### 2. `fn_get_maintenance_status(p_bus_id BIGINT)`
- **Purpose**: Classify maintenance urgency for a vehicle based on scheduled service intervals.
- **Parameters**: `p_bus_id BIGINT`.
- **Return Type**: `TABLE(bus_id BIGINT, registration_number VARCHAR(20), last_service_date DATE, next_service_date DATE, maintenance_status TEXT)`
- **SQL Concepts Used**: `SELECT INTO`, Date comparisons, Multi-branch conditional `IF/ELSIF/ELSE`.
- **Business Logic**: Retrieves the most recent maintenance record for the bus and evaluates `next_service_date` against `CURRENT_DATE`:
  - `NO SERVICE DATE`: When `next_service_date` is null.
  - `OVERDUE`: When `next_service_date < CURRENT_DATE`.
  - `DUE TODAY`: When `next_service_date = CURRENT_DATE`.
  - `DUE SOON (within 30 days)`: When `next_service_date <= CURRENT_DATE + 30`.
  - `NOT DUE`: When `next_service_date > CURRENT_DATE + 30`.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_get_maintenance_status(15);
  ```
- **Error Handling**: Validates bus existence; raises `no_data_found` on unknown IDs.
- **Transit Use Case**: Fleet workshop managers prioritize daily mechanic workloads and schedule preventive servicing before component failures occur on the road.

---

#### 3. `fn_get_bus_utilization(p_bus_id BIGINT)`
- **Purpose**: Calculate operational trip fulfillment efficiency for an individual bus.
- **Parameters**: `p_bus_id BIGINT`.
- **Return Type**: `TABLE(bus_id BIGINT, total_assigned_trips BIGINT, completed_trips BIGINT, cancelled_trips BIGINT, completion_percentage NUMERIC(5,2))`
- **SQL Concepts Used**: Aggregate filtering (`COUNT(CASE WHEN ...)`), `ROUND()`, `NULLIF(..., 0)` division safety.
- **Business Logic**: Aggregates all assigned trips for the vehicle, counts successful completions vs cancellations, and calculates the completion ratio.
  > **Note**: This metric serves as a *trip-based schedule completion proxy*, reflecting operational reliability, rather than engine-hour physical utilization.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_get_bus_utilization(5);
  ```
- **Error Handling**: Raises `no_data_found` if the bus ID does not exist.
- **Transit Use Case**: Fleet lifecycle planning; identifies vehicles with chronically high cancellation rates due to mechanical breakdowns.

---

### MODULE B: TRIP AND ROUTE MANAGEMENT

#### 4. `fn_calculate_trip_delay(p_trip_stop_log_id BIGINT)`
- **Purpose**: Measure the schedule variance (delay in seconds and decimal minutes) at a designated bus stop log.
- **Parameters**: `p_trip_stop_log_id BIGINT`.
- **Return Type**: `TABLE(trip_stop_log_id BIGINT, scheduled_arrival TIMESTAMPTZ, actual_arrival TIMESTAMPTZ, delay_seconds INTEGER, delay_minutes NUMERIC(8,2))`
- **SQL Concepts Used**: Timestamp arithmetic, `EXTRACT(EPOCH FROM ...)`, `ROUND()`, `RAISE NOTICE`.
- **Business Logic**: Compares `actual_arrival_at` with `scheduled_arrival_at`. Positive values indicate delays; negative values indicate early arrivals.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_calculate_trip_delay(101);
  ```
- **Error Handling**: Raises `no_data_found` if the stop log does not exist. Emits a `NOTICE` and returns NULL metrics if either arrival timestamp is missing.
- **Transit Use Case**: Real-time commuter passenger information displays (PIDS) calculate arrival countdowns and timetable reliability KPIs.

---

#### 5. `fn_get_route_performance(p_route_id BIGINT)`
- **Purpose**: Generate a route-level operational performance report.
- **Parameters**: `p_route_id BIGINT`.
- **Return Type**: `TABLE(route_id BIGINT, route_number VARCHAR(20), total_trips BIGINT, completed_trips BIGINT, cancelled_trips BIGINT, total_passenger_boardings BIGINT, average_delay_minutes NUMERIC(8,2), completion_percentage NUMERIC(5,2))`
- **SQL Concepts Used**: Multi-query aggregation isolation, `COALESCE()`, `NULLIF()`, `ROUND()`.
- **Business Logic**: Uses three independent queries to compute (1) trip completion stats, (2) passenger boardings, and (3) average delay duration. Isolating these queries eliminates duplicate counting that would occur if joining `trips`, `passenger_counts`, and `delay_records` in a single query.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_get_route_performance(1);
  ```
- **Error Handling**: Raises `no_data_found` if `p_route_id` does not exist.
- **Transit Use Case**: Network schedule planners evaluate corridor punctuality and ridership before adjusting timetable headways.

---

### MODULE C: PASSENGER MANAGEMENT

#### 6. `fn_get_stop_demand(p_stop_id BIGINT)`
- **Purpose**: Calculate total passenger footfall, boardings, alightings, and vehicle visits for a specific bus stop.
- **Parameters**: `p_stop_id BIGINT`.
- **Return Type**: `TABLE(stop_id BIGINT, stop_name VARCHAR(100), total_boardings BIGINT, total_alightings BIGINT, total_footfall BIGINT, number_of_visits BIGINT)`
- **SQL Concepts Used**: Multi-table traversal (`stops` -> `route_stops` -> `trip_stop_logs` -> `passenger_counts`), composite foreign key join (`rs.route_stop_id = tsl.route_stop_id AND rs.route_id = tsl.route_id`).
- **Business Logic**: Aggregates all visits made to this stop across all routes serving it, accurately summing boardings and alightings without duplicating visits.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_get_stop_demand(12);
  ```
- **Error Handling**: Raises `no_data_found` if `p_stop_id` does not exist.
- **Transit Use Case**: Municipal infrastructure planning; determines whether a stop requires high-capacity shelters, benches, ticket kiosks, or CCTV coverage.

---

### MODULE D: DRIVER AND DELAY MANAGEMENT

#### 7. `fn_check_license_expiry(p_driver_id BIGINT)`
- **Purpose**: Audit commercial driving license compliance against regulatory warning windows.
- **Parameters**: `p_driver_id BIGINT`.
- **Return Type**: `TABLE(driver_id BIGINT, driver_name TEXT, license_number VARCHAR(30), expiry_date DATE, days_remaining INTEGER, license_status TEXT)`
- **SQL Concepts Used**: `CONCAT_WS()`, Date subtraction, Multi-tier `IF/ELSIF`.
- **Business Logic**: Computes `(license_expiry_date - CURRENT_DATE)`:
  - `EXPIRED`: When expiration date is in the past.
  - `CRITICAL (expires within 30 days)`: `<= 30 days` remaining.
  - `WARNING (expires within 90 days)`: `<= 90 days` remaining.
  - `VALID`: `> 90 days` remaining.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_check_license_expiry(3);
  ```
- **Error Handling**: Raises `no_data_found` if `p_driver_id` is invalid.
- **Transit Use Case**: HR and safety compliance officers prevent non-licensed operation and issue mandatory license renewal notices.

---

#### 8. `fn_calculate_delay_severity(p_delay_seconds INTEGER)`
- **Purpose**: Standardize delay duration into operational severity tiers.
- **Parameters**: `p_delay_seconds INTEGER`.
- **Return Type**: `VARCHAR(20)`
- **SQL Concepts Used**: `IMMUTABLE` function optimization, boundary checks, check constraint verification.
- **Business Logic**:
  - `0 to 300 seconds`: `'MINOR'`
  - `301 to 600 seconds`: `'MODERATE'`
  - `> 600 seconds`: `'SEVERE'`
- **Example Invocation**:
  ```sql
  SELECT fn_calculate_delay_severity(450); -- Returns 'MODERATE'
  ```
- **Error Handling**: Rejects negative delay values with SQLSTATE `check_violation` (`23514`).
- **Transit Use Case**: Automated incident classification in supervisory control and dispatch consoles.

---

#### 9. `fn_get_driver_performance(p_driver_id BIGINT)`
- **Purpose**: Generate a driver productivity and punctuality scorecard.
- **Parameters**: `p_driver_id BIGINT`.
- **Return Type**: `TABLE(driver_id BIGINT, driver_name TEXT, total_assigned_trips BIGINT, completed_trips BIGINT, cancelled_trips BIGINT, completion_percentage NUMERIC(5,2), average_recorded_delay_minutes NUMERIC(8,2))`
- **SQL Concepts Used**: Independent subqueries, `NULLIF()`, `ROUND()`, `CONCAT_WS()`.
- **Business Logic**: Evaluates driver assignment fulfillment (completion rate) and computes average delay across all trips operated by that driver without subjective scoring.
- **Example Invocation**:
  ```sql
  SELECT * FROM fn_get_driver_performance(2);
  ```
- **Error Handling**: Raises `no_data_found` if `p_driver_id` does not exist.
- **Transit Use Case**: Objective basis for monthly driver recognition, safety bonuses, and refresher training selection.

---

## Part 2: Stored Procedures Catalog (`database/08_procedures.sql`)

### PROCEDURE 1: `sp_create_trip(...)`

```sql
CALL sp_create_trip(
    p_schedule_id      => 1,
    p_route_id         => 1,
    p_bus_id           => 1,
    p_driver_id        => 1,
    p_service_date     => CURRENT_DATE,
    p_scheduled_start  => (CURRENT_DATE + TIME '05:00')::TIMESTAMPTZ,
    p_trip_id          => v_new_trip_id
);
```

#### Parameters:
- `p_schedule_id BIGINT` (Input)
- `p_route_id BIGINT` (Input)
- `p_bus_id BIGINT` (Input)
- `p_driver_id BIGINT` (Input)
- `p_service_date DATE` (Input)
- `p_scheduled_start TIMESTAMPTZ` (Input)
- `INOUT p_trip_id BIGINT DEFAULT NULL` (Output: Newly generated trip ID)

#### 8-Point Validation Architecture:
1. **Schedule Existence & Route Alignment**: Verifies that `schedule_id` exists and that `schedules.route_id = p_route_id`. Prevents mismatched route scheduling.
2. **Schedule Status & Validity Range**: Confirms `schedules.status = 'ACTIVE'` and checks that `p_service_date` is between `effective_from` and `effective_until`.
3. **Operating Day Validation**: Extracts ISO day of week (`EXTRACT(ISODOW FROM p_service_date)`) and confirms the day exists in `schedule_operating_days`.
4. **Bus Availability (Concurrency Row Lock)**: Executes `SELECT status FROM buses WHERE bus_id = p_bus_id FOR UPDATE`. Confirms status is `'ACTIVE'`.
5. **Driver Availability (Concurrency Row Lock)**: Executes `SELECT status FROM drivers WHERE driver_id = p_driver_id FOR UPDATE`. Confirms status is `'AVAILABLE'`.
6. **Conflicting Overlapping Bus Assignment Check**: Inspects `trips` to guarantee the selected bus is not already assigned to an overlapping scheduled or running trip during that operational window.
7. **Conflicting Overlapping Driver Assignment Check**: Inspects `trips` to guarantee the driver is not double-booked on an overlapping trip.
8. **Scheduled Start Timestamp Validation**: Validates that `p_scheduled_start` strictly equals `(p_service_date + s.departure_time)::TIMESTAMPTZ`.

#### Transit Use Case:
The central dispatch engine calls this procedure when publishing daily rosters. It provides rock-solid ACID guarantees against double-booking vehicles or drivers.

---

### PROCEDURE 2: `sp_record_passenger_count(...)`

```sql
CALL sp_record_passenger_count(
    p_trip_stop_log_id => 205,
    p_boarding_count   => 12,
    p_alighting_count  => 5,
    p_message          => v_status_msg
);
```

#### Parameters:
- `p_trip_stop_log_id BIGINT` (Input)
- `p_boarding_count INTEGER` (Input)
- `p_alighting_count INTEGER` (Input)
- `INOUT p_message TEXT DEFAULT NULL` (Output: Status description)

#### Business Logic:
1. Validates that `p_trip_stop_log_id` exists in `trip_stop_logs`.
2. Validates that neither `p_boarding_count` nor `p_alighting_count` is negative.
3. Performs an upsert via `INSERT ... ON CONFLICT (trip_stop_log_id) DO UPDATE`.
4. Automatically updates `recorded_at = CURRENT_TIMESTAMP`.
5. Sets `p_message` to inform the caller whether the record was inserted or updated.

#### Transit Use Case:
Automated Passenger Counting (APC) sensors transmit sensor telemetry via IoT gateways at every bus stop. This procedure safely ingests or corrects readings without primary key conflicts.

---

### PROCEDURE 3: `sp_record_delay(...)`

```sql
CALL sp_record_delay(
    p_trip_stop_log_id => 312,
    p_reason_id        => 1,
    p_delay_seconds    => 480,
    p_remarks          => 'Signal failure at North Junction',
    p_delay_id         => v_new_delay_id
);
```

#### Parameters:
- `p_trip_stop_log_id BIGINT` (Input)
- `p_reason_id BIGINT` (Input)
- `p_delay_seconds INTEGER` (Input)
- `p_remarks TEXT` (Input)
- `INOUT p_delay_id BIGINT DEFAULT NULL` (Output: Generated delay ID)

#### Business Logic:
1. Validates that `p_trip_stop_log_id` exists in `trip_stop_logs`.
2. Validates that `p_reason_id` exists in `delay_reasons`.
3. Validates that `p_delay_seconds >= 0`.
4. Calls `fn_calculate_delay_severity(p_delay_seconds)` to automatically set `severity` (`MINOR`, `MODERATE`, or `SEVERE`).
5. Inserts the incident into `delay_records` and returns the generated `delay_id`.

#### Transit Use Case:
Automatic Vehicle Location (AVL) and Computer-Aided Dispatch (CAD) systems log delay incidents when buses exceed schedule headway thresholds.

---

## Part 3: Automated Test Harness (`database/09_routine_tests.sql`)

The test harness provides 15 isolated, transactional test scenarios:

| Test ID | Routine Tested | Scenario Description | Expected Outcome |
| :---: | :--- | :--- | :--- |
| **TEST 1** | `fn_get_bus_*` | Valid bus ID verification across 3 routines | Returns populated records |
| **TEST 2** | `fn_get_bus_status` | Non-existent bus ID (9999999) | Throws `no_data_found` (P0002) |
| **TEST 3** | `fn_get_route_performance` | Valid route ID test | Returns non-null trips & boardings |
| **TEST 4** | `fn_get_route_performance` | Invalid route ID (8888888) | Throws `no_data_found` (P0002) |
| **TEST 5** | `fn_get_driver_performance` | Valid driver performance query | Returns completed trip counts |
| **TEST 6** | `fn_check_license_expiry` | Expired / expiring license check | Returns valid status & days remaining |
| **TEST 7** | `sp_record_passenger_count` | Negative boarding count (-5) | Throws `check_violation` (23514) |
| **TEST 8** | `sp_record_passenger_count` | New passenger count insertion | Inserts record, sets `recorded_at` |
| **TEST 9** | `sp_record_passenger_count` | Upsert existing stop log | Updates existing record in place |
| **TEST 10** | `sp_record_delay` | Valid delay (750s) insertion | Inserts record with `severity = 'SEVERE'` |
| **TEST 11** | `sp_record_delay` | Negative delay (-120s) | Throws `check_violation` (23514) |
| **TEST 12** | `sp_create_trip` | Conflicting overlapping bus assignment | Throws `unique_violation` |
| **TEST 13** | `sp_create_trip` | Conflicting driver assignment | Throws `unique_violation` |
| **TEST 14** | `sp_create_trip` | Schedule-route ID mismatch | Throws `check_violation` |
| **TEST 15** | `sp_create_trip` | Service date outside effective range | Throws `check_violation` |

---

## Part 4: pgAdmin 4 Execution Guide

To compile and verify all functions, procedures, and tests in **pgAdmin 4**:

1. Connect to **pgAdmin 4** -> Open database **`transitiq_db`**.
2. Open the **Query Tool**.
3. Execute the scripts in the following order:
   - **Step 1**: Open and run [database/07_functions.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/07_functions.sql).
   - **Step 2**: Open and run [database/08_procedures.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/08_procedures.sql).
   - **Step 3**: Open and run [database/09_routine_tests.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/09_routine_tests.sql).
4. Review the Messages tab in pgAdmin: You should see all 15 tests reporting `[PASS]` with zero residual side effects.
