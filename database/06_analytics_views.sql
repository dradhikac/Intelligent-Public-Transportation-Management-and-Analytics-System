-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/06_analytics_views.sql
-- PURPOSE: Production Analytical Views (5 Reusable Business Views)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- =====================================================================
-- VIEW 1: vw_fleet_summary
-- Purpose: Complete fleet operational status, capacity, maintenance cost,
-- and assignment metrics consolidated per bus asset.
-- =====================================================================
CREATE OR REPLACE VIEW vw_fleet_summary AS
WITH bus_maintenance_agg AS (
    SELECT
        mr.bus_id,
        COUNT(mr.maintenance_id) AS total_maintenance_events,
        COUNT(CASE WHEN mr.maintenance_status = 'COMPLETED' THEN 1 END) AS completed_maintenance_events,
        COUNT(CASE WHEN mr.maintenance_status = 'PENDING' THEN 1 END) AS pending_maintenance_events,
        COALESCE(SUM(mr.maintenance_cost), 0.00) AS total_maintenance_cost,
        ROUND(COALESCE(AVG(mr.maintenance_cost), 0.00), 2) AS avg_maintenance_cost,
        MAX(mr.maintenance_date) AS latest_service_date,
        MAX(mr.next_service_date) AS upcoming_service_date
    FROM maintenance_records mr
    GROUP BY mr.bus_id
),
bus_trip_agg AS (
    SELECT
        t.bus_id,
        COUNT(t.trip_id) AS total_assigned_trips,
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
        COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips
    FROM trips t
    GROUP BY t.bus_id
)
SELECT
    b.bus_id,
    b.registration_number,
    bt.bus_type_id,
    bt.type_name AS bus_type,
    bt.seating_capacity,
    bt.standing_capacity,
    (bt.seating_capacity + bt.standing_capacity) AS total_passenger_capacity,
    b.manufacturer,
    b.model,
    b.manufacturing_year,
    b.status AS operational_status,
    b.purchase_date,
    b.last_service_date,
    COALESCE(bma.total_maintenance_events, 0) AS total_maintenance_events,
    COALESCE(bma.completed_maintenance_events, 0) AS completed_maintenance_events,
    COALESCE(bma.pending_maintenance_events, 0) AS pending_maintenance_events,
    COALESCE(bma.total_maintenance_cost, 0.00) AS total_maintenance_expenditure,
    COALESCE(bma.avg_maintenance_cost, 0.00) AS avg_maintenance_cost,
    bma.latest_service_date,
    bma.upcoming_service_date,
    CASE
        WHEN bma.upcoming_service_date IS NULL THEN 'NO SCHEDULE'
        WHEN bma.upcoming_service_date < CURRENT_DATE THEN 'OVERDUE'
        WHEN bma.upcoming_service_date = CURRENT_DATE THEN 'DUE TODAY'
        WHEN bma.upcoming_service_date <= CURRENT_DATE + INTERVAL '14 days' THEN 'DUE SOON'
        ELSE 'UP TO DATE'
    END AS service_status,
    COALESCE(bta.total_assigned_trips, 0) AS total_assigned_trips,
    COALESCE(bta.completed_trips, 0) AS completed_trips,
    ROUND(
        100.0 * COALESCE(bta.completed_trips, 0) /
        NULLIF(COALESCE(bta.total_assigned_trips, 0), 0),
        2
    ) AS trip_completion_rate_pct
FROM buses b
JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
LEFT JOIN bus_maintenance_agg bma ON b.bus_id = bma.bus_id
LEFT JOIN bus_trip_agg bta ON b.bus_id = bta.bus_id;


-- =====================================================================
-- VIEW 2: vw_route_performance
-- Purpose: Holistic performance dashboard for transit routes combining
-- trip fulfillment, ridership volume, and delay statistics.
-- =====================================================================
CREATE OR REPLACE VIEW vw_route_performance AS
WITH route_trip_stats AS (
    SELECT
        t.route_id,
        COUNT(t.trip_id) AS total_scheduled_trips,
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
        COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips,
        COUNT(CASE WHEN t.trip_status = 'RUNNING' THEN 1 END) AS running_trips
    FROM trips t
    GROUP BY t.route_id
),
route_passenger_stats AS (
    SELECT
        t.route_id,
        COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
        COALESCE(SUM(pc.alighting_count), 0) AS total_alightings,
        COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_passenger_turnover
    FROM trips t
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY t.route_id
),
route_delay_stats AS (
    SELECT
        t.route_id,
        COUNT(dr.delay_id) AS total_delay_incidents,
        COALESCE(SUM(dr.delay_seconds), 0) AS total_delay_seconds,
        ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2) AS avg_delay_minutes,
        ROUND(COALESCE(MAX(dr.delay_seconds), 0) / 60.0, 2) AS max_delay_minutes,
        COUNT(CASE WHEN dr.severity = 'SEVERE' THEN 1 END) AS severe_delay_count
    FROM trips t
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
    GROUP BY t.route_id
)
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    r.start_location,
    r.end_location,
    r.total_distance_km,
    r.estimated_duration_minutes,
    r.status AS route_status,
    COALESCE(rts.total_scheduled_trips, 0) AS total_scheduled_trips,
    COALESCE(rts.completed_trips, 0) AS completed_trips,
    COALESCE(rts.cancelled_trips, 0) AS cancelled_trips,
    ROUND(
        100.0 * COALESCE(rts.completed_trips, 0) /
        NULLIF(COALESCE(rts.total_scheduled_trips, 0), 0),
        2
    ) AS trip_completion_rate_pct,
    COALESCE(rps.total_boardings, 0) AS total_boardings,
    COALESCE(rps.total_alightings, 0) AS total_alightings,
    COALESCE(rps.total_passenger_turnover, 0) AS total_passenger_turnover,
    ROUND(
        COALESCE(rps.total_boardings, 0)::NUMERIC /
        NULLIF(COALESCE(rts.completed_trips, 0), 0),
        2
    ) AS avg_boardings_per_completed_trip,
    COALESCE(rds.total_delay_incidents, 0) AS total_delay_incidents,
    COALESCE(rds.avg_delay_minutes, 0.00) AS avg_delay_minutes,
    COALESCE(rds.max_delay_minutes, 0.00) AS max_delay_minutes,
    COALESCE(rds.severe_delay_count, 0) AS severe_delay_count
FROM routes r
LEFT JOIN route_trip_stats rts ON r.route_id = rts.route_id
LEFT JOIN route_passenger_stats rps ON r.route_id = rps.route_id
LEFT JOIN route_delay_stats rds ON r.route_id = rds.route_id;


-- =====================================================================
-- VIEW 3: vw_passenger_demand
-- Purpose: Stop- and route-level passenger boarding, alighting, and footfall
-- analysis to support transit stop infrastructure and scheduling.
-- =====================================================================
CREATE OR REPLACE VIEW vw_passenger_demand AS
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    s.stop_id,
    s.stop_name,
    rs.stop_sequence,
    rs.distance_from_start_km,
    rs.estimated_travel_minutes,
    COUNT(tsl.trip_stop_log_id) AS total_scheduled_visits,
    COUNT(CASE WHEN tsl.stop_status = 'REACHED' THEN 1 END) AS successful_stop_visits,
    COUNT(CASE WHEN tsl.stop_status = 'SKIPPED' THEN 1 END) AS skipped_stop_visits,
    COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
    COALESCE(SUM(pc.alighting_count), 0) AS total_alightings,
    COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_footfall,
    ROUND(
        COALESCE(SUM(pc.boarding_count), 0)::NUMERIC /
        NULLIF(COUNT(CASE WHEN tsl.stop_status = 'REACHED' THEN 1 END), 0),
        2
    ) AS avg_boardings_per_visit,
    ROUND(
        COALESCE(SUM(pc.alighting_count), 0)::NUMERIC /
        NULLIF(COUNT(CASE WHEN tsl.stop_status = 'REACHED' THEN 1 END), 0),
        2
    ) AS avg_alightings_per_visit
FROM routes r
JOIN route_stops rs ON r.route_id = rs.route_id
JOIN stops s ON rs.stop_id = s.stop_id
LEFT JOIN trip_stop_logs tsl ON rs.route_stop_id = tsl.route_stop_id
LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
GROUP BY
    r.route_id,
    r.route_number,
    r.route_name,
    s.stop_id,
    s.stop_name,
    rs.stop_sequence,
    rs.distance_from_start_km,
    rs.estimated_travel_minutes;


-- =====================================================================
-- VIEW 4: vw_delay_analysis
-- Purpose: Granular operational view linking delay incidents with their
-- root cause, scheduled vs actual arrival times, severity, and context.
-- =====================================================================
CREATE OR REPLACE VIEW vw_delay_analysis AS
SELECT
    dr.delay_id,
    t.service_date,
    t.trip_id,
    r.route_id,
    r.route_number,
    r.route_name,
    b.bus_id,
    b.registration_number AS bus_registration,
    d.driver_id,
    (d.first_name || ' ' || COALESCE(d.last_name, '')) AS driver_name,
    s.stop_id,
    s.stop_name,
    rs.stop_sequence,
    tsl.scheduled_arrival_at,
    tsl.actual_arrival_at,
    drn.reason_id,
    drn.reason_name AS delay_reason,
    dr.delay_seconds,
    ROUND(dr.delay_seconds / 60.0, 2) AS delay_minutes,
    dr.severity,
    CASE
        WHEN dr.severity = 'SEVERE' OR dr.delay_seconds > 600 THEN 'CRITICAL DISRUPTION'
        WHEN dr.severity = 'MODERATE' OR dr.delay_seconds > 300 THEN 'MODERATE DELAY'
        ELSE 'MINOR DELAY'
    END AS delay_operational_tier,
    dr.remarks,
    dr.recorded_at AS delay_logged_at
FROM delay_records dr
JOIN delay_reasons drn ON dr.reason_id = drn.reason_id
JOIN trip_stop_logs tsl ON dr.trip_stop_log_id = tsl.trip_stop_log_id
JOIN trips t ON tsl.trip_id = t.trip_id
JOIN routes r ON t.route_id = r.route_id
JOIN route_stops rs ON tsl.route_stop_id = rs.route_stop_id
JOIN stops s ON rs.stop_id = s.stop_id
JOIN buses b ON t.bus_id = b.bus_id
JOIN drivers d ON t.driver_id = d.driver_id;


-- =====================================================================
-- VIEW 5: vw_driver_performance
-- Purpose: Driver workload, operational completion rates, license compliance,
-- and trip-level delay metrics aggregated by driver.
-- =====================================================================
CREATE OR REPLACE VIEW vw_driver_performance AS
WITH driver_trip_stats AS (
    SELECT
        t.driver_id,
        COUNT(t.trip_id) AS total_assigned_trips,
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
        COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips,
        COUNT(CASE WHEN t.trip_status = 'RUNNING' THEN 1 END) AS in_transit_trips
    FROM trips t
    GROUP BY t.driver_id
),
driver_delay_stats AS (
    SELECT
        t.driver_id,
        COUNT(dr.delay_id) AS total_delays_logged,
        COALESCE(SUM(dr.delay_seconds), 0) AS total_delay_seconds,
        ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2) AS avg_delay_minutes
    FROM trips t
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
    GROUP BY t.driver_id
)
SELECT
    d.driver_id,
    d.employee_code,
    (d.first_name || ' ' || COALESCE(d.last_name, '')) AS driver_full_name,
    d.phone_number,
    d.status AS driver_status,
    d.license_number,
    d.license_expiry_date,
    (d.license_expiry_date - CURRENT_DATE) AS days_until_license_expiry,
    CASE
        WHEN d.license_expiry_date < CURRENT_DATE THEN 'EXPIRED'
        WHEN d.license_expiry_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'EXPIRING SOON (<=30 Days)'
        WHEN d.license_expiry_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'WARNING (<=90 Days)'
        ELSE 'VALID'
    END AS license_status,
    d.date_of_joining,
    COALESCE(dts.total_assigned_trips, 0) AS total_assigned_trips,
    COALESCE(dts.completed_trips, 0) AS completed_trips,
    COALESCE(dts.cancelled_trips, 0) AS cancelled_trips,
    ROUND(
        100.0 * COALESCE(dts.completed_trips, 0) /
        NULLIF(COALESCE(dts.total_assigned_trips, 0), 0),
        2
    ) AS trip_completion_rate_pct,
    COALESCE(dds.total_delays_logged, 0) AS total_delays_logged,
    COALESCE(dds.avg_delay_minutes, 0.00) AS avg_delay_minutes
FROM drivers d
LEFT JOIN driver_trip_stats dts ON d.driver_id = dts.driver_id
LEFT JOIN driver_delay_stats dds ON d.driver_id = dds.driver_id;

-- =====================================================================
-- END OF ANALYTICAL VIEWS
-- =====================================================================
