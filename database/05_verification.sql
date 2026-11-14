-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/05_verification.sql
-- PURPOSE: Database Integrity Verification & Analytical View Smoke Tests
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. VERIFY ALL 17 TABLES EXIST IN PUBLIC SCHEMA
-- ---------------------------------------------------------------------
SELECT
    table_name,
    table_type
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;


-- ---------------------------------------------------------------------
-- 2. VERIFY ROW COUNTS ACROSS ALL 17 RELATIONAL TABLES
-- ---------------------------------------------------------------------
SELECT 'bus_types' AS table_name, COUNT(*) AS total_records FROM bus_types
UNION ALL
SELECT 'buses', COUNT(*) FROM buses
UNION ALL
SELECT 'maintenance_records', COUNT(*) FROM maintenance_records
UNION ALL
SELECT 'routes', COUNT(*) FROM routes
UNION ALL
SELECT 'stops', COUNT(*) FROM stops
UNION ALL
SELECT 'route_stops', COUNT(*) FROM route_stops
UNION ALL
SELECT 'drivers', COUNT(*) FROM drivers
UNION ALL
SELECT 'schedules', COUNT(*) FROM schedules
UNION ALL
SELECT 'operating_days', COUNT(*) FROM operating_days
UNION ALL
SELECT 'schedule_operating_days', COUNT(*) FROM schedule_operating_days
UNION ALL
SELECT 'schedule_stop_times', COUNT(*) FROM schedule_stop_times
UNION ALL
SELECT 'trips', COUNT(*) FROM trips
UNION ALL
SELECT 'trip_stop_logs', COUNT(*) FROM trip_stop_logs
UNION ALL
SELECT 'passenger_counts', COUNT(*) FROM passenger_counts
UNION ALL
SELECT 'delay_reasons', COUNT(*) FROM delay_reasons
UNION ALL
SELECT 'delay_records', COUNT(*) FROM delay_records
UNION ALL
SELECT 'audit_logs', COUNT(*) FROM audit_logs
ORDER BY table_name;


-- ---------------------------------------------------------------------
-- 3. VERIFY ALL 5 ANALYTICAL VIEWS EXIST AND RETURN DATA
-- ---------------------------------------------------------------------
-- Test View 1: Fleet Summary
SELECT
    bus_id,
    registration_number,
    bus_type,
    operational_status,
    total_maintenance_expenditure,
    service_status,
    completed_trips
FROM vw_fleet_summary
ORDER BY bus_id
LIMIT 5;

-- Test View 2: Route Performance
SELECT
    route_id,
    route_number,
    route_name,
    total_scheduled_trips,
    completed_trips,
    trip_completion_rate_pct,
    total_boardings,
    total_delay_incidents
FROM vw_route_performance
ORDER BY route_number
LIMIT 5;

-- Test View 3: Passenger Demand
SELECT
    route_number,
    stop_name,
    stop_sequence,
    total_boardings,
    total_alightings,
    avg_boardings_per_visit
FROM vw_passenger_demand
ORDER BY route_number, stop_sequence
LIMIT 5;

-- Test View 4: Delay Analysis
SELECT
    delay_id,
    service_date,
    route_number,
    bus_registration,
    driver_name,
    stop_name,
    delay_reason,
    delay_minutes,
    severity
FROM vw_delay_analysis
ORDER BY delay_id
LIMIT 5;

-- Test View 5: Driver Performance
SELECT
    driver_id,
    employee_code,
    driver_full_name,
    driver_status,
    license_status,
    completed_trips,
    trip_completion_rate_pct,
    total_delays_logged
FROM vw_driver_performance
ORDER BY completed_trips DESC
LIMIT 5;


-- ---------------------------------------------------------------------
-- 4. VERIFY FOREIGN KEY INTEGRITY (ORPHAN RECORD CHECKS)
-- ---------------------------------------------------------------------
-- Orphan check: Buses with invalid bus_type_id
SELECT COUNT(*) AS orphan_buses
FROM buses b
LEFT JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
WHERE bt.bus_type_id IS NULL;

-- Orphan check: Route stops with invalid route_id or stop_id
SELECT COUNT(*) AS orphan_route_stops
FROM route_stops rs
LEFT JOIN routes r ON rs.route_id = r.route_id
LEFT JOIN stops s ON rs.stop_id = s.stop_id
WHERE r.route_id IS NULL OR s.stop_id IS NULL;

-- Orphan check: Trips with invalid route, bus, or driver
SELECT COUNT(*) AS orphan_trips
FROM trips t
LEFT JOIN routes r ON t.route_id = r.route_id
LEFT JOIN buses b ON t.bus_id = b.bus_id
LEFT JOIN drivers d ON t.driver_id = d.driver_id
WHERE r.route_id IS NULL OR b.bus_id IS NULL OR d.driver_id IS NULL;

-- Orphan check: Passenger counts without matching trip stop logs
SELECT COUNT(*) AS orphan_passenger_counts
FROM passenger_counts pc
LEFT JOIN trip_stop_logs tsl ON pc.trip_stop_log_id = tsl.trip_stop_log_id
WHERE tsl.trip_stop_log_id IS NULL;

-- Orphan check: Delay records without matching trip stop logs or reasons
SELECT COUNT(*) AS orphan_delay_records
FROM delay_records dr
LEFT JOIN trip_stop_logs tsl ON dr.trip_stop_log_id = tsl.trip_stop_log_id
LEFT JOIN delay_reasons drn ON dr.reason_id = drn.reason_id
WHERE tsl.trip_stop_log_id IS NULL OR drn.reason_id IS NULL;
