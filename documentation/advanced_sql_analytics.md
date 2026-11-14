# TransitIQ – Advanced SQL Analytics Engine Documentation

## Executive Overview
**TransitIQ (Intelligent Public Transportation Management and Analytics System)** utilizes a 3NF relational database schema implemented in **PostgreSQL 14+**. The analytics engine provides comprehensive business intelligence across fleet operations, network scheduling, ridership demand patterns, delay root causes, and crew productivity.

The analytics architecture consists of:
1. **`database/05_advanced_analytics.sql`**: 24 modular, production-grade analytical queries.
2. **`database/06_analytics_views.sql`**: 5 reusable, high-performance database views for dashboards and operational reporting.
3. **`database/05_verification.sql`**: Smoke tests, orphan integrity checks, and validation suites.

---

## Part 1: Detailed Catalog of All 24 Analytical Queries

### MODULE A: FLEET ANALYTICS

#### Query 1: Total Buses Grouped by Bus Status
- **Business Problem Solved**: Tracks operational readiness of the vehicle inventory versus buses out of service.
- **SQL Concepts Used**: `COUNT()`, `GROUP BY`, `SUM() OVER ()` (windowed percentage), `NULLIF()`, `ROUND()`.
- **Expected Output Columns**:
  - `bus_status` (`VARCHAR(20)`) – Operational state ('ACTIVE', 'MAINTENANCE', 'INACTIVE', 'RETIRED').
  - `total_buses` (`BIGINT`) – Count of vehicles in that state.
  - `fleet_share_percentage` (`NUMERIC(5,2)`) – Percentage of total fleet.
- **Administrator Action**: Triggers asset reviews if maintenance or inactive pools exceed 15% of the total fleet.

#### Query 2: Total Buses Grouped by Bus Type with Capacity Profile
- **Business Problem Solved**: Analyzes fleet asset composition against capacity standards (seating, standing, total).
- **SQL Concepts Used**: `LEFT JOIN`, `GROUP BY`, Conditional Aggregation (`COUNT(CASE WHEN ...)`), `ROUND()`, `NULLIF()`.
- **Expected Output Columns**:
  - `bus_type_id`, `type_name` – Bus classification (AC, Non-AC, Electric, Mini).
  - `seating_capacity`, `standing_capacity`, `total_passenger_capacity` – Capacity limits.
  - `total_assigned_buses` – Total fleet count of this type.
  - `active_in_service_buses` – Available active buses.
  - `operational_availability_pct` – Availability ratio.
- **Administrator Action**: Informs green fleet transition targets (EV adoption) and procurement plans based on passenger demand.

#### Query 3: Bus Maintenance History and Maintenance Expenditure
- **Business Problem Solved**: Tracks life-to-date repair volume and financial expense per vehicle asset.
- **SQL Concepts Used**: Multi-table `JOIN` (`buses`, `bus_types`, `maintenance_records`), `SUM()`, `AVG()`, `COALESCE()`, `GROUP BY`.
- **Expected Output Columns**:
  - `bus_id`, `registration_number`, `bus_type`, `manufacturer`, `model`, `current_status`.
  - `total_maintenance_events`, `completed_maintenance_events`.
  - `total_maintenance_expenditure` – Cumulative maintenance cost in INR.
  - `avg_cost_per_service` – Average cost per service event.
  - `most_recent_maintenance_date`.
- **Administrator Action**: Pinpoints unreliable, high-maintenance vehicles ("lemon" units) for early retirement or warranty claim audits.

#### Query 4: Buses Requiring Maintenance Based on Next Service Date
- **Business Problem Solved**: Proactively flags upcoming and overdue vehicle maintenance deadlines.
- **SQL Concepts Used**: Common Table Expressions (CTE), `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ...)`, `CASE` statement, Date Arithmetic (`next_service_date - CURRENT_DATE`).
- **Expected Output Columns**:
  - `bus_id`, `registration_number`, `bus_status`, `last_service_date`, `last_maintenance_type`.
  - `next_service_date`, `days_until_due`.
  - `maintenance_urgency` ('OVERDUE', 'DUE TODAY', 'DUE SOON (Within 14 Days)', 'UPCOMING', 'NO SCHEDULED DATE').
- **Administrator Action**: Automatically feeds the daily workshop queue to prevent non-compliant or unsafe buses from leaving the depot.

---

### MODULE B: ROUTE ANALYTICS

#### Query 5: Total Number of Trips Operated on Each Route
- **Business Problem Solved**: Evaluates schedule fulfillment and cancellation rates per transit corridor.
- **SQL Concepts Used**: `LEFT JOIN`, `COUNT()`, Filtered Aggregations (`CASE WHEN`), `ROUND()`, `NULLIF()`.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`, `route_status`.
  - `total_scheduled_trips`, `completed_trips`, `cancelled_trips`, `in_transit_trips`.
  - `completion_rate_percentage`.
- **Administrator Action**: Highlights routes suffering from systematic cancellations for operational audits (driver shortages or chronic mechanical issues).

#### Query 6: Top 10 Busiest Routes Based on Passenger Boardings
- **Business Problem Solved**: Identifies core arterial passenger corridors across the municipality.
- **SQL Concepts Used**: Multi-table inner joins across 4 entities (`routes`, `trips`, `trip_stop_logs`, `passenger_counts`), `COUNT(DISTINCT)`, `SUM()`, `ORDER BY ... DESC LIMIT 10`.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`, `total_distance_km`.
  - `trips_operated`, `total_boardings`, `total_alightings`, `total_passenger_turnover`.
  - `avg_boardings_per_trip`.
- **Administrator Action**: Justifies investments in high-capacity vehicles (articulated/electric buses) and dedicated bus priority lanes.

#### Query 7: Average Passenger Demand Per Route
- **Business Problem Solved**: Normalizes ridership demand against distance and stop count to evaluate route density.
- **SQL Concepts Used**: `LEFT JOIN`, Multiple Aggregates, `NULLIF()`, Division sanitization.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`, `total_distance_km`, `total_trips`, `total_stop_visits`.
  - `total_boardings`, `avg_boardings_per_trip`, `avg_boardings_per_stop_visit`, `boardings_per_route_km`.
- **Administrator Action**: Distinguishes between long, low-density rural routes and short, high-density feeder routes for fare-structure optimization.

#### Query 8: Routes with the Highest Average Travel Delays
- **Business Problem Solved**: Measures cumulative delay severity and schedule variance across lines.
- **SQL Concepts Used**: Hierarchical joins (`routes` -> `trips` -> `trip_stop_logs` -> `delay_records`), Time conversions (`delay_seconds / 60.0`), `AVG()`, `MAX()`, `SUM()`.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`, `estimated_duration_minutes`.
  - `total_delay_incidents`, `avg_delay_minutes`, `max_delay_minutes`, `cumulative_delay_hours`.
- **Administrator Action**: Directs traffic engineering coordination and timetable recalibration (adjusting runtime buffers).

---

### MODULE C: PASSENGER DEMAND ANALYTICS

#### Query 9: Total Passenger Boardings and Alightings Network-Wide
- **Business Problem Solved**: Quantifies macroscopic system volume and passenger balance.
- **SQL Concepts Used**: Scalar aggregations, `COALESCE()`, `SUM()`, `NULLIF()`, `COUNT(DISTINCT)`.
- **Expected Output Columns**:
  - `network_total_boardings`, `network_total_alightings`, `total_passenger_interactions`.
  - `net_passenger_differential`, `system_turnover_ratio`, `total_sampling_events`.
- **Administrator Action**: Provides macro KPI reports for municipal transit authorities, subsidy auditors, and executive scorecards.

#### Query 10: Passenger Demand at Each Bus Stop
- **Business Problem Solved**: Analyzes boarding/alighting footfall for all 100 individual bus stops.
- **SQL Concepts Used**: 4-table `LEFT JOIN`, `COUNT(DISTINCT)`, `GROUP BY`, `COALESCE()`.
- **Expected Output Columns**:
  - `stop_id`, `stop_name`, `location_description`, `is_active`.
  - `routes_served`, `stop_visit_count`, `total_boardings`, `total_alightings`, `total_footfall`.
  - `avg_boardings_per_visit`.
- **Administrator Action**: Informs stop amenity planning (shelters, benches, lighting, real-time passenger displays, automated ticketing kiosks).

#### Query 11: Top 10 Busiest Bus Stops
- **Business Problem Solved**: Identifies and ranks the top 10 transit transfer points and major activity centers.
- **SQL Concepts Used**: `DENSE_RANK() OVER (ORDER BY ...)`, `SUM()`, `LIMIT 10`.
- **Expected Output Columns**:
  - `stop_id`, `stop_name`, `connecting_routes`.
  - `total_boardings`, `total_alightings`, `total_activity_volume`.
  - `traffic_rank`.
- **Administrator Action**: Prioritizes crowd control management, platform marshals, and transit police presence during peak hours.

#### Query 12: Routes with Passenger Demand Above the Overall Average
- **Business Problem Solved**: Discovers above-average performing routes through dynamic subqueries/CTEs.
- **SQL Concepts Used**: Multiple CTEs, `CROSS JOIN`, Arithmetic difference, percentage variance.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`, `total_route_boardings`.
  - `avg_network_route_boardings`, `surplus_over_average`, `pct_above_average`.
- **Administrator Action**: Identifies lines generating surplus revenue that cross-subsidize social access routes.

---

### MODULE D: DELAY ANALYTICS

#### Query 13: Total Delay Incidents Grouped by Delay Reason
- **Business Problem Solved**: Performs root-cause analysis on operational disruptions.
- **SQL Concepts Used**: `LEFT JOIN`, Windowed proportion (`SUM(COUNT()) OVER ()`), `AVG()`, `MAX()`, `SUM()`.
- **Expected Output Columns**:
  - `reason_id`, `reason_name`, `description`.
  - `incident_count`, `pct_of_total_delays`.
  - `total_lost_minutes`, `avg_delay_minutes_per_incident`, `max_single_delay_minutes`.
- **Administrator Action**: Determines whether budget should go toward mechanical maintenance, driver training, or municipal traffic agreements.

#### Query 14: Average Delay Duration by Route
- **Business Problem Solved**: Evaluates delay consistency and statistical dispersion per transit route.
- **SQL Concepts Used**: `AVG()`, `STDDEV_POP()`, `MIN()`, `MAX()`, unit conversion from seconds to minutes.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`.
  - `recorded_delays`, `avg_delay_minutes`, `delay_stddev_minutes`, `min_delay_minutes`, `max_delay_minutes`.
- **Administrator Action**: Routes with large standard deviations require dynamic dispatching; routes with high average and low variance simply need scheduled runtime extensions.

#### Query 15: Routes with the Highest Number of Severe Delays
- **Business Problem Solved**: Identifies routes prone to catastrophic delays exceeding 10 minutes.
- **SQL Concepts Used**: Filtered Aggregations (`COUNT(CASE WHEN severity = 'SEVERE')`), `HAVING` clause, percentage calculation.
- **Expected Output Columns**:
  - `route_id`, `route_number`, `route_name`.
  - `severe_delay_count`, `moderate_delay_count`, `minor_delay_count`, `total_delays`.
  - `severe_delay_ratio_pct`.
- **Administrator Action**: Signals routes needing active bypass routing or tactical turnback strategies during rush hours.

#### Query 16: Daily Delay Trends with Severity Classification
- **Business Problem Solved**: Tracks longitudinal system reliability by day of the week with severity bucketing.
- **SQL Concepts Used**: Multi-condition `CASE WHEN`, `TO_CHAR(service_date, 'Day')`, date grouping, aggregate statistics.
- **Expected Output Columns**:
  - `service_date`, `day_of_week`, `total_delays_logged`.
  - `minor_delays`, `moderate_delays`, `severe_delays`.
  - `avg_delay_minutes_per_event`, `total_delay_hours`.
- **Administrator Action**: Informs day-specific timetable adjustments (e.g., adding travel buffers on high-delay days like Fridays).

---

### MODULE E: DRIVER ANALYTICS

#### Query 17: Total Trips Completed by Each Driver
- **Business Problem Solved**: Audits individual driver assignment volume, completed trips, and cancellation rates.
- **SQL Concepts Used**: `LEFT JOIN`, `COUNT()`, `GROUP BY`, Filtered completion metrics, `NULLIF()`.
- **Expected Output Columns**:
  - `driver_id`, `employee_code`, `driver_full_name`, `driver_status`.
  - `total_assigned_trips`, `completed_trips`, `cancelled_trips`, `completion_rate_pct`.
- **Administrator Action**: Detects driver fatigue, unassigned availability, or unusual cancellation patterns.

#### Query 18: Driver Ranking Based on Number of Completed Trips
- **Business Problem Solved**: Establishes objective driver productivity rankings adjusted for length of service.
- **SQL Concepts Used**: `DENSE_RANK() OVER (ORDER BY ...)`, date difference calculations (`CURRENT_DATE - date_of_joining`), tenure normalization.
- **Expected Output Columns**:
  - `productivity_rank`, `driver_id`, `employee_code`, `driver_full_name`, `date_of_joining`.
  - `completed_trips`, `estimated_trips_per_month_tenure`.
- **Administrator Action**: Facilitates fair performance awards, driver incentives, and priority choice on preferred roster schedules.

#### Query 19: Drivers with Expiring or Expired Licenses
- **Business Problem Solved**: Enforces regulatory driver credential compliance and prevents unlicensed vehicle operation.
- **SQL Concepts Used**: Date subtraction, multi-tier `CASE WHEN`, sorting by urgency.
- **Expected Output Columns**:
  - `driver_id`, `employee_code`, `driver_full_name`, `phone_number`, `license_number`.
  - `license_expiry_date`, `days_until_expiry`.
  - `license_audit_status` ('EXPIRED - SUSPEND IMMEDIATELY', 'CRITICAL (Expires <= 30 Days)', 'WARNING (Expires <= 90 Days)', 'VALID').
- **Administrator Action**: Immediately blocks expired drivers from dispatch assignment and dispatches SMS renewal warnings to upcoming drivers.

---

### MODULE F: ADVANCED SQL ANALYTICS

#### Query 20: Rank Routes Based on Total Passenger Demand Using RANK()
- **Business Problem Solved**: Ranks all routes by passenger volume and computes network market share.
- **SQL Concepts Used**: CTE, `RANK() OVER (ORDER BY ...)`, `DENSE_RANK() OVER (ORDER BY ...)`, `SUM() OVER ()`.
- **Expected Output Columns**:
  - `demand_rank`, `demand_dense_rank`, `route_id`, `route_number`, `route_name`.
  - `total_boardings`, `total_alightings`, `network_demand_share_pct`.
- **Administrator Action**: Provides clean tiered rankings for network-level rationalization and scheduling prioritization.

#### Query 21: Calculate Running Passenger Boarding Totals Using SUM() OVER()
- **Business Problem Solved**: Measures progressive ridership accumulation partitioned by route and for the network overall.
- **SQL Concepts Used**: CTE, Windowed `SUM() OVER (PARTITION BY ... ORDER BY ... ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)`.
- **Expected Output Columns**:
  - `service_date`, `route_number`, `daily_boardings`.
  - `route_running_total_boardings`, `network_cumulative_boardings`.
- **Administrator Action**: Enables mid-month revenue tracking against monthly target trajectories.

#### Query 22: Route-Wise Average Passenger Demand Using Window Functions
- **Business Problem Solved**: Evaluates trip-level variance against route averages without collapsing rows.
- **SQL Concepts Used**: CTE, `AVG() OVER (PARTITION BY ...)`, inline deviation calculation, classification `CASE`.
- **Expected Output Columns**:
  - `trip_id`, `service_date`, `route_number`, `route_name`, `trip_total_boardings`.
  - `route_avg_boardings`, `variance_from_route_avg`, `trip_capacity_classification`.
- **Administrator Action**: Identifies individual runs that are severely overcrowded (>25% above average) or underutilized (<25% below average).

#### Query 23: Compare Each Route's Passenger Demand with Previous Day Using LAG()
- **Business Problem Solved**: Calculates day-over-day ridership volatility and growth rates per route.
- **SQL Concepts Used**: CTE, `LAG() OVER (PARTITION BY ... ORDER BY ...)`, day-over-day difference, growth percentage formula with `NULLIF()`.
- **Expected Output Columns**:
  - `service_date`, `route_number`, `route_name`, `current_day_boardings`.
  - `previous_day_boardings`, `daily_boarding_change`, `day_over_day_growth_pct`.
- **Administrator Action**: Detects unexpected demand drop-offs triggered by road closures, service anomalies, or adverse weather.

#### Query 24: Identify the Busiest Route for Each Day Using ROW_NUMBER()
- **Business Problem Solved**: Determines the leading route for each operational service date.
- **SQL Concepts Used**: CTE, `ROW_NUMBER() OVER (PARTITION BY ... ORDER BY ... DESC)`, filter condition `WHERE daily_rank = 1`.
- **Expected Output Columns**:
  - `service_date`, `day_of_week`, `route_id`, `route_number`, `route_name`.
  - `winning_route_boardings`, `trips_operated`, `avg_boardings_per_trip`.
- **Administrator Action**: Analyzes temporal demand shifts (e.g. weekday business corridors vs weekend leisure lines).

---

## Part 2: Detailed Catalog of Analytical Views

### 1. `vw_fleet_summary`
- **Purpose**: Unified view consolidating bus specs, current status, maintenance expenditure, and completed trips per vehicle.
- **Design Philosophy**: Pre-aggregates maintenance and trip records using isolated CTEs to prevent Cartesian row multiplication.
- **Underlying Tables**: `buses`, `bus_types`, `maintenance_records`, `trips`.
- **Key Columns**:
  - `bus_id`, `registration_number`, `bus_type`, `total_passenger_capacity`.
  - `operational_status`, `total_maintenance_expenditure`, `avg_maintenance_cost`.
  - `latest_service_date`, `upcoming_service_date`, `service_status` ('OVERDUE', 'DUE SOON', etc.).
  - `total_assigned_trips`, `completed_trips`, `trip_completion_rate_pct`.

### 2. `vw_route_performance`
- **Purpose**: Comprehensive route-level dashboard combining timetable metrics, passenger ridership, and delay impact.
- **Design Philosophy**: Separates trip statistics, passenger metrics, and delay metrics into three independent CTEs joined to `routes`.
- **Underlying Tables**: `routes`, `trips`, `trip_stop_logs`, `passenger_counts`, `delay_records`.
- **Key Columns**:
  - `route_id`, `route_number`, `route_name`, `total_distance_km`, `route_status`.
  - `total_scheduled_trips`, `completed_trips`, `cancelled_trips`, `trip_completion_rate_pct`.
  - `total_boardings`, `total_alightings`, `avg_boardings_per_completed_trip`.
  - `total_delay_incidents`, `avg_delay_minutes`, `max_delay_minutes`, `severe_delay_count`.

### 3. `vw_passenger_demand`
- **Purpose**: High-resolution stop-by-stop passenger demand and boarding density matrix across all routes.
- **Underlying Tables**: `routes`, `route_stops`, `stops`, `trip_stop_logs`, `passenger_counts`.
- **Key Columns**:
  - `route_id`, `route_number`, `route_name`.
  - `stop_id`, `stop_name`, `stop_sequence`, `distance_from_start_km`.
  - `total_scheduled_visits`, `successful_stop_visits`, `skipped_stop_visits`.
  - `total_boardings`, `total_alightings`, `total_footfall`.
  - `avg_boardings_per_visit`, `avg_alightings_per_visit`.

### 4. `vw_delay_analysis`
- **Purpose**: Granular operational audit log associating every delay event with its scheduled timetable, actual arrival, driver, bus, and root cause.
- **Underlying Tables**: `delay_records`, `delay_reasons`, `trip_stop_logs`, `trips`, `routes`, `route_stops`, `stops`, `buses`, `drivers`.
- **Key Columns**:
  - `delay_id`, `service_date`, `trip_id`, `route_number`, `bus_registration`, `driver_name`.
  - `stop_name`, `scheduled_arrival_at`, `actual_arrival_at`.
  - `delay_reason`, `delay_seconds`, `delay_minutes`, `severity`.
  - `delay_operational_tier` ('CRITICAL DISRUPTION', 'MODERATE DELAY', 'MINOR DELAY').
  - `remarks`, `delay_logged_at`.

### 5. `vw_driver_performance`
- **Purpose**: Driver compliance and operational productivity scorecards.
- **Design Philosophy**: Pre-aggregates driver trips and driver-related delays separately to preserve 1:1 row cardinality with the `drivers` table.
- **Underlying Tables**: `drivers`, `trips`, `trip_stop_logs`, `delay_records`.
- **Key Columns**:
  - `driver_id`, `employee_code`, `driver_full_name`, `phone_number`, `driver_status`.
  - `license_number`, `license_expiry_date`, `days_until_license_expiry`, `license_status`.
  - `total_assigned_trips`, `completed_trips`, `cancelled_trips`, `trip_completion_rate_pct`.
  - `total_delays_logged`, `avg_delay_minutes`.

---

## Part 3: Step-by-Step pgAdmin Execution & Testing Guide

To execute and verify the database and analytics engine in **pgAdmin 4**:

### Step 1: Connect to Database
1. Launch **pgAdmin 4**.
2. Expand **Servers** -> Enter master password -> Connect to PostgreSQL instance.
3. If not already present, create the database:
   ```sql
   CREATE DATABASE transitiq_db;
   ```
4. Right-click `transitiq_db` and select **Query Tool**.

### Step 2: Execute Schema & Seed Scripts in Sequence
Execute the scripts in order:

```text
1. database/01_create_tables.sql
   └─ Creates all 17 relational tables with primary keys, foreign keys, and CHECK constraints.

2. database/02_constraints.sql
   └─ Creates secondary indexes on foreign keys, statuses, and timestamp filters.

3. database/03_indexes.sql
   └─ Inserts initial lookup data (bus_types, operating_days, delay_reasons).

4. database/04_seed_data.sql
   └─ Generates operational dataset: 50 buses, 40 drivers, 25 routes, 100 stops,
      250 route stops, 100 maintenance records, 25 schedules, 175 schedule operating days,
      250 schedule stop times, 350 trips, 3,500 stop logs, 3,500 passenger counts, and delay records.

5. database/06_analytics_views.sql
   └─ Creates the 5 reusable analytical views.

6. database/05_advanced_analytics.sql
   └─ Runs the 24 advanced SQL analytical queries.

7. database/05_verification.sql
   └─ Runs table existence, row counts, and orphan integrity validation checks.
```

### Step 3: Verify View Execution in pgAdmin
Execute the test queries to verify views:
```sql
SELECT * FROM vw_fleet_summary LIMIT 10;
SELECT * FROM vw_route_performance LIMIT 10;
SELECT * FROM vw_passenger_demand LIMIT 10;
SELECT * FROM vw_delay_analysis LIMIT 10;
SELECT * FROM vw_driver_performance LIMIT 10;
```
Verify that all 5 views return rows with zero SQL errors and accurate calculated columns.
