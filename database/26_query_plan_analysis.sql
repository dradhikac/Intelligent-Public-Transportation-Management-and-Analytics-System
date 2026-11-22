-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/26_query_plan_analysis.sql
-- PURPOSE: Step 12 – Query Execution Plan Analysis (10 Core Workloads)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- DESCRIPTION:
--   Executes EXPLAIN (ANALYZE, BUFFERS) across 10 representative operational
--   and analytical queries. Each section breaks down the query execution plan,
--   join algorithms, cost estimates, memory buffers, and tuning insights.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: EXPLAIN (ANALYZE, BUFFERS) QUERY ANALYSIS';
    RAISE NOTICE '=====================================================';
END;
$$;

-- =====================================================================
-- QUERY 1: FLEET AVAILABILITY & OPERATIONAL RATIO
-- Target: buses GROUP BY status with window aggregation
-- Access Method: Seq Scan on buses + HashAggregate + WindowAgg
-- Cost Meaning: Startup cost to compute first row vs Total cost for all rows
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    b.status AS bus_status,
    COUNT(b.bus_id) AS total_buses,
    ROUND(100.0 * COUNT(b.bus_id) / NULLIF(SUM(COUNT(b.bus_id)) OVER (), 0), 2) AS fleet_share_pct
FROM buses b
GROUP BY b.status
ORDER BY total_buses DESC;


-- =====================================================================
-- QUERY 2: BUS MAINTENANCE EXPENDITURE JOIN
-- Target: buses JOIN bus_types LEFT JOIN maintenance_records
-- Access Method: Hash Left Join / Nested Loop + HashAggregate + Sort
-- Optimization Insight: Left join ensures buses with zero maintenance events
-- are retained without dropping from fleet inventory reports.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    b.bus_id,
    b.registration_number,
    bt.type_name AS bus_type,
    b.status AS operational_status,
    COUNT(mr.maintenance_id) AS total_maintenance_events,
    COALESCE(SUM(mr.maintenance_cost), 0.00) AS total_expenditure
FROM buses b
JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
LEFT JOIN maintenance_records mr ON b.bus_id = mr.bus_id
GROUP BY b.bus_id, b.registration_number, bt.type_name, b.status
ORDER BY total_expenditure DESC;


-- =====================================================================
-- QUERY 3: ROUTE PERFORMANCE & TRIP COMPLETION RATE
-- Target: routes LEFT JOIN trips GROUP BY route
-- Access Method: Hash Join + GroupAggregate
-- Optimization Insight: Grouping by route_id utilizes unique primary key
-- semantics, reducing hash table memory footprint during aggregation.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    COUNT(t.trip_id) AS total_trips,
    COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
    ROUND(
        100.0 * COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) / NULLIF(COUNT(t.trip_id), 0),
        2
    ) AS completion_rate_pct
FROM routes r
LEFT JOIN trips t ON r.route_id = t.route_id
GROUP BY r.route_id, r.route_number, r.route_name
ORDER BY total_trips DESC;


-- =====================================================================
-- QUERY 4: PASSENGER BOARDINGS BY STOP & CORRIDOR DEMAND
-- Target: stops JOIN route_stops JOIN trip_stop_logs JOIN passenger_counts
-- Access Method: Multi-table Hash Join chain + HashAggregate
-- Buffer Metric: Buffers: shared hit measures buffer cache efficiency
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    s.stop_id,
    s.stop_name,
    COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
    COALESCE(SUM(pc.alighting_count), 0) AS total_alightings,
    COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_footfall
FROM stops s
JOIN route_stops rs ON s.stop_id = rs.stop_id
JOIN trip_stop_logs tsl ON rs.route_stop_id = tsl.route_stop_id
JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
GROUP BY s.stop_id, s.stop_name
ORDER BY total_footfall DESC;


-- =====================================================================
-- QUERY 5: DELAY REASON AGGREGATION & SEVERITY METRICS
-- Target: delay_records JOIN delay_reasons
-- Access Method: Hash Join + HashAggregate
-- Tuning Insight: Filtering by recorded_at can leverage idx_delay_recorded_at
-- when date-range filters are applied.
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    dr.reason_name,
    COUNT(d.delay_id) AS incident_count,
    ROUND(AVG(d.delay_seconds), 1) AS avg_delay_seconds,
    MAX(d.delay_seconds) AS max_delay_seconds,
    COUNT(CASE WHEN d.severity = 'SEVERE' THEN 1 END) AS severe_incident_count
FROM delay_records d
JOIN delay_reasons dr ON d.reason_id = dr.reason_id
GROUP BY dr.reason_name
ORDER BY incident_count DESC;


-- =====================================================================
-- QUERY 6: DRIVER PERFORMANCE & RELIABILITY SCORING
-- Target: drivers LEFT JOIN trips GROUP BY driver
-- Access Method: Hash Left Join + HashAggregate + Sort
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    d.driver_id,
    d.first_name || ' ' || COALESCE(d.last_name, '') AS driver_name,
    d.status AS driver_status,
    COUNT(t.trip_id) AS total_assigned_trips,
    COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
    COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.driver_id, d.first_name, d.last_name, d.status
ORDER BY total_assigned_trips DESC;


-- =====================================================================
-- QUERY 7: ACTIVE SCHEDULES EFFECTIVE TIMETABLE WINDOW
-- Target: schedules JOIN routes with date and status predicates
-- Access Method: Hash Join or Nested Loop + Filter
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    s.schedule_id,
    s.schedule_name,
    r.route_number,
    s.departure_time,
    s.arrival_time,
    s.effective_from,
    s.effective_until
FROM schedules s
JOIN routes r ON s.route_id = r.route_id
WHERE s.status = 'ACTIVE'
  AND s.effective_from <= CURRENT_DATE
  AND (s.effective_until IS NULL OR s.effective_until >= CURRENT_DATE);


-- =====================================================================
-- QUERY 8: TRIP STOP ARRIVAL TIME VARIANCE & DELAY DETECTION
-- Target: trip_stop_logs JOIN trips
-- Access Method: Hash Join with timestamp arithmetic
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    tsl.trip_id,
    tsl.route_stop_id,
    tsl.scheduled_arrival_at,
    tsl.actual_arrival_at,
    ROUND(EXTRACT(EPOCH FROM (tsl.actual_arrival_at - tsl.scheduled_arrival_at))) AS delay_seconds,
    tsl.stop_status
FROM trip_stop_logs tsl
JOIN trips t ON tsl.trip_id = t.trip_id
WHERE tsl.actual_arrival_at IS NOT NULL
  AND tsl.scheduled_arrival_at IS NOT NULL
ORDER BY delay_seconds DESC;


-- =====================================================================
-- QUERY 9: PASSENGER DEMAND VIEW (vw_passenger_demand)
-- Target: Complex 4-table join view with day-of-week and hourly extraction
-- Access Method: View expansion with multi-table hash joins
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    route_number,
    service_date,
    total_boardings,
    total_alightings
FROM vw_passenger_demand
ORDER BY service_date DESC, total_boardings DESC;


-- =====================================================================
-- QUERY 10: HEAVY MULTI-CORRIDOR FLEET TELEMETRY AUDIT
-- Target: trips + routes + buses + drivers + stop logs + passenger counts
-- Access Method: 6-table join graph evaluating join order & memory overhead
-- =====================================================================
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    t.trip_id,
    r.route_number,
    b.registration_number,
    d.first_name || ' ' || COALESCE(d.last_name, '') AS driver_name,
    COUNT(tsl.trip_stop_log_id) AS total_logged_stops,
    COALESCE(SUM(pc.boarding_count), 0) AS total_trip_passengers
FROM trips t
JOIN routes r ON t.route_id = r.route_id
JOIN buses b ON t.bus_id = b.bus_id
JOIN drivers d ON t.driver_id = d.driver_id
LEFT JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
WHERE t.service_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY t.trip_id, r.route_number, b.registration_number, d.first_name, d.last_name
ORDER BY t.trip_id DESC;
