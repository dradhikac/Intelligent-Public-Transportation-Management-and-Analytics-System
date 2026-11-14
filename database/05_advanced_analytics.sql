-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/05_advanced_analytics.sql
-- PURPOSE: Advanced SQL Analytics Engine (24 Production-Grade Queries)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- =====================================================================
-- MODULE A: FLEET ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 1: Total Buses Grouped by Bus Status
-- Purpose: Evaluate overall fleet operational availability vs out-of-service assets.
-- Administrator Insight: Provides instantaneous visibility into fleet health. High
-- proportions of 'MAINTENANCE' or 'INACTIVE' buses signal depot bottlenecks or
-- aging stock requiring capital replacement.
-- ---------------------------------------------------------------------
SELECT
    b.status AS bus_status,
    COUNT(b.bus_id) AS total_buses,
    ROUND(
        100.0 * COUNT(b.bus_id) / NULLIF(SUM(COUNT(b.bus_id)) OVER (), 0),
        2
    ) AS fleet_share_percentage
FROM buses b
GROUP BY b.status
ORDER BY total_buses DESC;


-- ---------------------------------------------------------------------
-- QUERY 2: Total Buses Grouped by Bus Type with Capacity Profile
-- Purpose: Analyze fleet composition across categories (AC, Electric, etc.) and seating profiles.
-- Administrator Insight: Ensures fleet capacity aligns with city green initiatives (e.g. Electric)
-- and passenger comfort demands (e.g. AC vs Non-AC during peak summer).
-- ---------------------------------------------------------------------
SELECT
    bt.bus_type_id,
    bt.type_name,
    bt.seating_capacity,
    bt.standing_capacity,
    (bt.seating_capacity + bt.standing_capacity) AS total_passenger_capacity,
    COUNT(b.bus_id) AS total_assigned_buses,
    COUNT(CASE WHEN b.status = 'ACTIVE' THEN 1 END) AS active_in_service_buses,
    ROUND(
        100.0 * COUNT(CASE WHEN b.status = 'ACTIVE' THEN 1 END) / NULLIF(COUNT(b.bus_id), 0),
        2
    ) AS operational_availability_pct
FROM bus_types bt
LEFT JOIN buses b ON bt.bus_type_id = b.bus_type_id
GROUP BY bt.bus_type_id, bt.type_name, bt.seating_capacity, bt.standing_capacity
ORDER BY total_assigned_buses DESC, bt.type_name;


-- ---------------------------------------------------------------------
-- QUERY 3: Bus Maintenance History and Maintenance Expenditure
-- Purpose: Calculate aggregate maintenance volume, expenditure, and recent service dates per bus.
-- Administrator Insight: Highlights chronic "money pit" vehicles where cumulative repair
-- costs exceed asset depreciation thresholds, guiding vehicle retirement decisions.
-- ---------------------------------------------------------------------
SELECT
    b.bus_id,
    b.registration_number,
    bt.type_name AS bus_type,
    b.manufacturer,
    b.model,
    b.status AS current_status,
    COUNT(mr.maintenance_id) AS total_maintenance_events,
    COUNT(CASE WHEN mr.maintenance_status = 'COMPLETED' THEN 1 END) AS completed_maintenance_events,
    COALESCE(SUM(mr.maintenance_cost), 0.00) AS total_maintenance_expenditure,
    ROUND(COALESCE(AVG(mr.maintenance_cost), 0.00), 2) AS avg_cost_per_service,
    MAX(mr.maintenance_date) AS most_recent_maintenance_date
FROM buses b
JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
LEFT JOIN maintenance_records mr ON b.bus_id = mr.bus_id
GROUP BY b.bus_id, b.registration_number, bt.type_name, b.manufacturer, b.model, b.status
ORDER BY total_maintenance_expenditure DESC, b.bus_id ASC;


-- ---------------------------------------------------------------------
-- QUERY 4: Buses Requiring Maintenance Based on Next Service Date
-- Purpose: Identify buses with upcoming or overdue scheduled maintenance dates.
-- Administrator Insight: Serves as an operational dispatch checklist preventing
-- legally non-compliant or mechanically hazardous vehicles from being assigned to trips.
-- ---------------------------------------------------------------------
WITH latest_bus_maintenance AS (
    SELECT
        b.bus_id,
        b.registration_number,
        b.status AS bus_status,
        b.last_service_date,
        mr.maintenance_id,
        mr.maintenance_type,
        mr.maintenance_date,
        mr.next_service_date,
        ROW_NUMBER() OVER (
            PARTITION BY b.bus_id
            ORDER BY mr.maintenance_date DESC, mr.maintenance_id DESC
        ) AS rn
    FROM buses b
    LEFT JOIN maintenance_records mr ON b.bus_id = mr.bus_id
)
SELECT
    lbm.bus_id,
    lbm.registration_number,
    lbm.bus_status,
    lbm.last_service_date,
    lbm.maintenance_type AS last_maintenance_type,
    lbm.next_service_date,
    (lbm.next_service_date - CURRENT_DATE) AS days_until_due,
    CASE
        WHEN lbm.next_service_date IS NULL THEN 'NO SCHEDULED DATE'
        WHEN lbm.next_service_date < CURRENT_DATE THEN 'OVERDUE'
        WHEN lbm.next_service_date = CURRENT_DATE THEN 'DUE TODAY'
        WHEN lbm.next_service_date <= CURRENT_DATE + 14 THEN 'DUE SOON (Within 14 Days)'
        ELSE 'UPCOMING'
    END AS maintenance_urgency
FROM latest_bus_maintenance lbm
WHERE lbm.rn = 1
ORDER BY
    CASE
        WHEN lbm.next_service_date < CURRENT_DATE THEN 1
        WHEN lbm.next_service_date = CURRENT_DATE THEN 2
        WHEN lbm.next_service_date <= CURRENT_DATE + 14 THEN 3
        WHEN lbm.next_service_date IS NULL THEN 5
        ELSE 4
    END,
    lbm.next_service_date ASC;


-- =====================================================================
-- MODULE B: ROUTE ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 5: Total Number of Trips Operated on Each Route
-- Purpose: Measure operational trip volume and completion rates by route.
-- Administrator Insight: Evaluates service fulfillment across transit lines. Routes
-- with poor completion rates indicate vehicle breakdowns, route congestion, or staffing deficits.
-- ---------------------------------------------------------------------
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    r.status AS route_status,
    COUNT(t.trip_id) AS total_scheduled_trips,
    COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
    COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips,
    COUNT(CASE WHEN t.trip_status = 'RUNNING' THEN 1 END) AS in_transit_trips,
    ROUND(
        100.0 * COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) /
        NULLIF(COUNT(t.trip_id), 0),
        2
    ) AS completion_rate_percentage
FROM routes r
LEFT JOIN trips t ON r.route_id = t.route_id
GROUP BY r.route_id, r.route_number, r.route_name, r.status
ORDER BY total_scheduled_trips DESC, r.route_number;


-- ---------------------------------------------------------------------
-- QUERY 6: Top 10 Busiest Routes Based on Passenger Boardings
-- Purpose: Identify the primary passenger travel corridors in the transit system.
-- Administrator Insight: Pinpoints high-yield transit arteries where peak frequencies,
-- double-decker/articulated buses, or dedicated transit lanes would have maximum public impact.
-- ---------------------------------------------------------------------
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    r.total_distance_km,
    COUNT(DISTINCT t.trip_id) AS trips_operated,
    COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
    COALESCE(SUM(pc.alighting_count), 0) AS total_alightings,
    COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_passenger_turnover,
    ROUND(
        COALESCE(SUM(pc.boarding_count), 0)::NUMERIC /
        NULLIF(COUNT(DISTINCT t.trip_id), 0),
        2
    ) AS avg_boardings_per_trip
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
GROUP BY r.route_id, r.route_number, r.route_name, r.total_distance_km
ORDER BY total_boardings DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- QUERY 7: Average Passenger Demand Per Route
-- Purpose: Compute normalized demand metrics (per trip, per km, per stop visit) across all routes.
-- Administrator Insight: Allows fair cross-route comparison regardless of route length,
-- identifying underperforming feeder routes vs highly efficient trunk lines.
-- ---------------------------------------------------------------------
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    r.total_distance_km,
    COUNT(DISTINCT t.trip_id) AS total_trips,
    COUNT(tsl.trip_stop_log_id) AS total_stop_visits,
    COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
    ROUND(
        COALESCE(SUM(pc.boarding_count), 0)::NUMERIC / NULLIF(COUNT(DISTINCT t.trip_id), 0),
        2
    ) AS avg_boardings_per_trip,
    ROUND(
        COALESCE(SUM(pc.boarding_count), 0)::NUMERIC / NULLIF(COUNT(tsl.trip_stop_log_id), 0),
        2
    ) AS avg_boardings_per_stop_visit,
    ROUND(
        COALESCE(SUM(pc.boarding_count), 0)::NUMERIC / NULLIF(r.total_distance_km, 0),
        2
    ) AS boardings_per_route_km
FROM routes r
LEFT JOIN trips t ON r.route_id = t.route_id
LEFT JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
GROUP BY r.route_id, r.route_number, r.route_name, r.total_distance_km
ORDER BY avg_boardings_per_trip DESC NULLS LAST;


-- ---------------------------------------------------------------------
-- QUERY 8: Routes with the Highest Average Travel Delays
-- Purpose: Identify routes experiencing recurring transit delays and high schedule deviation.
-- Administrator Insight: Guides timetable recalibration (padding realistic run times)
-- and signals where municipal traffic enforcement / signal prioritization is urgently required.
-- ---------------------------------------------------------------------
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    r.estimated_duration_minutes,
    COUNT(dr.delay_id) AS total_delay_incidents,
    ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2) AS avg_delay_minutes,
    ROUND(COALESCE(MAX(dr.delay_seconds), 0) / 60.0, 2) AS max_delay_minutes,
    ROUND(COALESCE(SUM(dr.delay_seconds), 0) / 3600.0, 2) AS cumulative_delay_hours
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
GROUP BY r.route_id, r.route_number, r.route_name, r.estimated_duration_minutes
ORDER BY avg_delay_minutes DESC, total_delay_incidents DESC;


-- =====================================================================
-- MODULE C: PASSENGER DEMAND ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 9: Total Passenger Boardings and Alightings Network-Wide
-- Purpose: Summarize macro-level ridership, net passenger retention, and boarding-to-alighting balance.
-- Administrator Insight: Provides senior executives with executive scorecard figures for
-- system-wide ridership growth and overall transit patronage.
-- ---------------------------------------------------------------------
SELECT
    COALESCE(SUM(pc.boarding_count), 0) AS network_total_boardings,
    COALESCE(SUM(pc.alighting_count), 0) AS network_total_alightings,
    COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_passenger_interactions,
    COALESCE(SUM(pc.boarding_count - pc.alighting_count), 0) AS net_passenger_differential,
    ROUND(
        COALESCE(SUM(pc.alighting_count), 0)::NUMERIC /
        NULLIF(SUM(pc.boarding_count), 0),
        4
    ) AS system_turnover_ratio,
    COUNT(DISTINCT pc.passenger_count_id) AS total_sampling_events
FROM passenger_counts pc;


-- ---------------------------------------------------------------------
-- QUERY 10: Passenger Demand at Each Bus Stop
-- Purpose: Detail footfall, passenger boarding, and passenger alighting for every bus stop.
-- Administrator Insight: Informs station infrastructure planning (need for covered canopies,
-- electronic countdown boards, ticket vending machines, and seating).
-- ---------------------------------------------------------------------
SELECT
    s.stop_id,
    s.stop_name,
    s.location_description,
    s.is_active,
    COUNT(DISTINCT rs.route_id) AS routes_served,
    COUNT(tsl.trip_stop_log_id) AS stop_visit_count,
    COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
    COALESCE(SUM(pc.alighting_count), 0) AS total_alightings,
    COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_footfall,
    ROUND(
        COALESCE(SUM(pc.boarding_count), 0)::NUMERIC /
        NULLIF(COUNT(tsl.trip_stop_log_id), 0),
        2
    ) AS avg_boardings_per_visit
FROM stops s
LEFT JOIN route_stops rs ON s.stop_id = rs.stop_id
LEFT JOIN trip_stop_logs tsl ON rs.route_stop_id = tsl.route_stop_id
LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
GROUP BY s.stop_id, s.stop_name, s.location_description, s.is_active
ORDER BY total_footfall DESC, s.stop_name;


-- ---------------------------------------------------------------------
-- QUERY 11: Top 10 Busiest Bus Stops
-- Purpose: Rank and isolate the 10 highest-traffic passenger hubs across the network.
-- Administrator Insight: Guides crowd management, transit police deployments,
-- and identifies priority stops for multi-modal interchange development.
-- ---------------------------------------------------------------------
SELECT
    s.stop_id,
    s.stop_name,
    COUNT(DISTINCT rs.route_id) AS connecting_routes,
    COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
    COALESCE(SUM(pc.alighting_count), 0) AS total_alightings,
    COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) AS total_activity_volume,
    DENSE_RANK() OVER (
        ORDER BY COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0) DESC
    ) AS traffic_rank
FROM stops s
JOIN route_stops rs ON s.stop_id = rs.stop_id
JOIN trip_stop_logs tsl ON rs.route_stop_id = tsl.route_stop_id
JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
GROUP BY s.stop_id, s.stop_name
ORDER BY total_activity_volume DESC
LIMIT 10;


-- ---------------------------------------------------------------------
-- QUERY 12: Routes with Passenger Demand Above the Overall Average
-- Purpose: Find routes whose passenger volume exceeds the mean route volume across the system.
-- Administrator Insight: Validates subsidy allocation and identifies high-revenue routes
-- that can cross-subsidize essential social/rural feeder services.
-- ---------------------------------------------------------------------
WITH route_boardings AS (
    SELECT
        r.route_id,
        r.route_number,
        r.route_name,
        COALESCE(SUM(pc.boarding_count), 0) AS total_route_boardings
    FROM routes r
    LEFT JOIN trips t ON r.route_id = t.route_id
    LEFT JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY r.route_id, r.route_number, r.route_name
),
network_stats AS (
    SELECT
        ROUND(AVG(total_route_boardings), 2) AS avg_network_route_boardings
    FROM route_boardings
)
SELECT
    rb.route_id,
    rb.route_number,
    rb.route_name,
    rb.total_route_boardings,
    ns.avg_network_route_boardings,
    (rb.total_route_boardings - ns.avg_network_route_boardings) AS surplus_over_average,
    ROUND(
        100.0 * (rb.total_route_boardings - ns.avg_network_route_boardings) /
        NULLIF(ns.avg_network_route_boardings, 0),
        2
    ) AS pct_above_average
FROM route_boardings rb
CROSS JOIN network_stats ns
WHERE rb.total_route_boardings > ns.avg_network_route_boardings
ORDER BY rb.total_route_boardings DESC;


-- =====================================================================
-- MODULE D: DELAY ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 13: Total Delay Incidents Grouped by Delay Reason
-- Purpose: Break down operational delay incidents by root cause with duration metrics.
-- Administrator Insight: Pinpoints whether transit agency interventions should focus
-- on road coordination (traffic), engineering (breakdowns), or operator rostering (driver issues).
-- ---------------------------------------------------------------------
SELECT
    drn.reason_id,
    drn.reason_name,
    drn.description,
    COUNT(dr.delay_id) AS incident_count,
    ROUND(
        100.0 * COUNT(dr.delay_id) / NULLIF(SUM(COUNT(dr.delay_id)) OVER (), 0),
        2
    ) AS pct_of_total_delays,
    ROUND(COALESCE(SUM(dr.delay_seconds), 0) / 60.0, 2) AS total_lost_minutes,
    ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2) AS avg_delay_minutes_per_incident,
    ROUND(COALESCE(MAX(dr.delay_seconds), 0) / 60.0, 2) AS max_single_delay_minutes
FROM delay_reasons drn
LEFT JOIN delay_records dr ON drn.reason_id = dr.reason_id
GROUP BY drn.reason_id, drn.reason_name, drn.description
ORDER BY incident_count DESC;


-- ---------------------------------------------------------------------
-- QUERY 14: Average Delay Duration by Route
-- Purpose: Calculate average delay duration and standard deviation for each route.
-- Administrator Insight: High average delay paired with high variance indicates volatile,
-- unpredictable corridors that damage commuter trust and require route simplification.
-- ---------------------------------------------------------------------
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    COUNT(dr.delay_id) AS recorded_delays,
    ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2) AS avg_delay_minutes,
    ROUND(COALESCE(STDDEV_POP(dr.delay_seconds), 0) / 60.0, 2) AS delay_stddev_minutes,
    ROUND(COALESCE(MIN(dr.delay_seconds), 0) / 60.0, 2) AS min_delay_minutes,
    ROUND(COALESCE(MAX(dr.delay_seconds), 0) / 60.0, 2) AS max_delay_minutes
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
GROUP BY r.route_id, r.route_number, r.route_name
ORDER BY avg_delay_minutes DESC;


-- ---------------------------------------------------------------------
-- QUERY 15: Routes with the Highest Number of Severe Delays
-- Purpose: Filter and rank routes by volume of severe delays (>10 min delay).
-- Administrator Insight: Alerts dispatchers to routes experiencing critical service breakdowns
-- where emergency replacement buses or detour plans must be deployed.
-- ---------------------------------------------------------------------
SELECT
    r.route_id,
    r.route_number,
    r.route_name,
    COUNT(CASE WHEN dr.severity = 'SEVERE' THEN 1 END) AS severe_delay_count,
    COUNT(CASE WHEN dr.severity = 'MODERATE' THEN 1 END) AS moderate_delay_count,
    COUNT(CASE WHEN dr.severity = 'MINOR' THEN 1 END) AS minor_delay_count,
    COUNT(dr.delay_id) AS total_delays,
    ROUND(
        100.0 * COUNT(CASE WHEN dr.severity = 'SEVERE' THEN 1 END) /
        NULLIF(COUNT(dr.delay_id), 0),
        2
    ) AS severe_delay_ratio_pct
FROM routes r
JOIN trips t ON r.route_id = t.route_id
JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
GROUP BY r.route_id, r.route_number, r.route_name
HAVING COUNT(CASE WHEN dr.severity = 'SEVERE' THEN 1 END) > 0
ORDER BY severe_delay_count DESC, total_delays DESC;


-- ---------------------------------------------------------------------
-- QUERY 16: Daily Delay Trends with Severity Classification
-- Purpose: Monitor daily progression of delay incidents categorized by severity.
-- Administrator Insight: Identifies macro patterns (such as Monday morning or Friday evening spikes)
-- to dynamically adapt fleet dispatch schedules by day of week.
-- ---------------------------------------------------------------------
SELECT
    t.service_date,
    TO_CHAR(t.service_date, 'Day') AS day_of_week,
    COUNT(dr.delay_id) AS total_delays_logged,
    COUNT(CASE WHEN dr.severity = 'MINOR' THEN 1 END) AS minor_delays,
    COUNT(CASE WHEN dr.severity = 'MODERATE' THEN 1 END) AS moderate_delays,
    COUNT(CASE WHEN dr.severity = 'SEVERE' THEN 1 END) AS severe_delays,
    ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2) AS avg_delay_minutes_per_event,
    ROUND(COALESCE(SUM(dr.delay_seconds), 0) / 3600.0, 2) AS total_delay_hours
FROM trips t
JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
GROUP BY t.service_date
ORDER BY t.service_date ASC;


-- =====================================================================
-- MODULE E: DRIVER ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 17: Total Trips Completed by Each Driver
-- Purpose: Track driver trip assignments, completed trips, and completion percentages.
-- Administrator Insight: Enables fair workload distribution and identifies drivers
-- experiencing disproportionate cancellations or operational obstacles.
-- ---------------------------------------------------------------------
SELECT
    d.driver_id,
    d.employee_code,
    CONCAT_WS(' ', d.first_name, d.last_name) AS driver_full_name,
    d.status AS driver_status,
    COUNT(t.trip_id) AS total_assigned_trips,
    COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
    COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips,
    ROUND(
        100.0 * COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) /
        NULLIF(COUNT(t.trip_id), 0),
        2
    ) AS completion_rate_pct
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.driver_id, d.employee_code, d.first_name, d.last_name, d.status
ORDER BY completed_trips DESC, total_assigned_trips DESC;


-- ---------------------------------------------------------------------
-- QUERY 18: Driver Ranking Based on Number of Completed Trips
-- Purpose: Rank drivers by completed trip volume using DENSE_RANK() with tenure context.
-- Administrator Insight: Provides an objective basis for monthly driver recognition programs,
-- productivity bonuses, and seniority awards without relying on subjective appraisals.
-- ---------------------------------------------------------------------
SELECT
    DENSE_RANK() OVER (
        ORDER BY COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) DESC
    ) AS productivity_rank,
    d.driver_id,
    d.employee_code,
    CONCAT_WS(' ', d.first_name, d.last_name) AS driver_full_name,
    d.date_of_joining,
    COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
    ROUND(
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END)::NUMERIC /
        NULLIF((CURRENT_DATE - d.date_of_joining) / 30.42, 0),
        2
    ) AS estimated_trips_per_month_tenure
FROM drivers d
LEFT JOIN trips t ON d.driver_id = t.driver_id
GROUP BY d.driver_id, d.employee_code, d.first_name, d.last_name, d.date_of_joining
ORDER BY productivity_rank ASC, d.employee_code ASC;


-- ---------------------------------------------------------------------
-- QUERY 19: Drivers with Expiring or Expired Licenses
-- Purpose: Audit commercial driver license validity and upcoming expiration thresholds.
-- Administrator Insight: Critical regulatory compliance safety net; alerts fleet HR
-- 30 to 90 days before expiration to mandate physical verification and avoid heavy municipal fines.
-- ---------------------------------------------------------------------
SELECT
    d.driver_id,
    d.employee_code,
    CONCAT_WS(' ', d.first_name, d.last_name) AS driver_full_name,
    d.phone_number,
    d.license_number,
    d.license_expiry_date,
    (d.license_expiry_date - CURRENT_DATE) AS days_until_expiry,
    CASE
        WHEN d.license_expiry_date < CURRENT_DATE THEN 'EXPIRED - SUSPEND IMMEDIATELY'
        WHEN d.license_expiry_date <= CURRENT_DATE + INTERVAL '30 days' THEN 'CRITICAL (Expires <= 30 Days)'
        WHEN d.license_expiry_date <= CURRENT_DATE + INTERVAL '90 days' THEN 'WARNING (Expires <= 90 Days)'
        ELSE 'VALID'
    END AS license_audit_status
FROM drivers d
ORDER BY d.license_expiry_date ASC;


-- =====================================================================
-- MODULE F: ADVANCED SQL ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 20: Rank Routes Based on Total Passenger Demand Using RANK()
-- Purpose: Assign competitive ranks to routes based on total boarding volume.
-- Administrator Insight: Distinguishes high-density core corridors from secondary routes,
-- driving commercial sponsorship decisions and public service obligation (PSO) accounting.
-- ---------------------------------------------------------------------
WITH route_aggregates AS (
    SELECT
        r.route_id,
        r.route_number,
        r.route_name,
        COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
        COALESCE(SUM(pc.alighting_count), 0) AS total_alightings
    FROM routes r
    LEFT JOIN trips t ON r.route_id = t.route_id
    LEFT JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    LEFT JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY r.route_id, r.route_number, r.route_name
)
SELECT
    RANK() OVER (ORDER BY ra.total_boardings DESC) AS demand_rank,
    DENSE_RANK() OVER (ORDER BY ra.total_boardings DESC) AS demand_dense_rank,
    ra.route_id,
    ra.route_number,
    ra.route_name,
    ra.total_boardings,
    ra.total_alightings,
    ROUND(
        100.0 * ra.total_boardings / NULLIF(SUM(ra.total_boardings) OVER (), 0),
        2
    ) AS network_demand_share_pct
FROM route_aggregates ra
ORDER BY demand_rank ASC, ra.route_number;


-- ---------------------------------------------------------------------
-- QUERY 21: Calculate Running Passenger Boarding Totals Using SUM() OVER()
-- Purpose: Track progressive accumulation of passenger boardings over time and per route.
-- Administrator Insight: Allows financial controllers to assess whether mid-month ridership
-- is pacing towards monthly revenue targets or lagging behind expectations.
-- ---------------------------------------------------------------------
WITH daily_route_boardings AS (
    SELECT
        t.service_date,
        r.route_id,
        r.route_number,
        COALESCE(SUM(pc.boarding_count), 0) AS daily_boardings
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY t.service_date, r.route_id, r.route_number
)
SELECT
    drb.service_date,
    drb.route_number,
    drb.daily_boardings,
    SUM(drb.daily_boardings) OVER (
        PARTITION BY drb.route_id
        ORDER BY drb.service_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS route_running_total_boardings,
    SUM(drb.daily_boardings) OVER (
        ORDER BY drb.service_date, drb.route_number
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS network_cumulative_boardings
FROM daily_route_boardings drb
ORDER BY drb.service_date ASC, drb.route_number ASC;


-- ---------------------------------------------------------------------
-- QUERY 22: Route-Wise Average Passenger Demand Using Window Functions
-- Purpose: Compare individual trip boardings against the route average without row collapse.
-- Administrator Insight: Highlights abnormal runs (overcrowded trips needing duplicate relief buses,
-- or empty ghost runs that can be pruned from the schedule).
-- ---------------------------------------------------------------------
WITH trip_boardings AS (
    SELECT
        t.trip_id,
        t.service_date,
        r.route_id,
        r.route_number,
        r.route_name,
        COALESCE(SUM(pc.boarding_count), 0) AS trip_total_boardings
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY t.trip_id, t.service_date, r.route_id, r.route_number, r.route_name
)
SELECT
    tb.trip_id,
    tb.service_date,
    tb.route_number,
    tb.route_name,
    tb.trip_total_boardings,
    ROUND(
        AVG(tb.trip_total_boardings) OVER (PARTITION BY tb.route_id),
        2
    ) AS route_avg_boardings,
    (
        tb.trip_total_boardings -
        ROUND(AVG(tb.trip_total_boardings) OVER (PARTITION BY tb.route_id), 2)
    ) AS variance_from_route_avg,
    CASE
        WHEN tb.trip_total_boardings > 1.25 * AVG(tb.trip_total_boardings) OVER (PARTITION BY tb.route_id)
            THEN 'HEAVY OVERLOAD (>25% Above Avg)'
        WHEN tb.trip_total_boardings < 0.75 * AVG(tb.trip_total_boardings) OVER (PARTITION BY tb.route_id)
            THEN 'UNDERUTILIZED (<25% Below Avg)'
        ELSE 'NORMAL RANGE'
    END AS trip_capacity_classification
FROM trip_boardings tb
ORDER BY tb.route_number, tb.service_date, tb.trip_id;


-- ---------------------------------------------------------------------
-- QUERY 23: Compare Each Route's Passenger Demand with Previous Day Using LAG()
-- Purpose: Calculate day-over-day ridership growth/decline rate per route.
-- Administrator Insight: Provides rapid alerts to localized disruptions (e.g. unexpected roadworks,
-- metro line openings, or school holidays) causing sudden swings in route demand.
-- ---------------------------------------------------------------------
WITH daily_route_demand AS (
    SELECT
        t.service_date,
        r.route_id,
        r.route_number,
        r.route_name,
        COALESCE(SUM(pc.boarding_count), 0) AS current_day_boardings
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY t.service_date, r.route_id, r.route_number, r.route_name
)
SELECT
    drd.service_date,
    drd.route_number,
    drd.route_name,
    drd.current_day_boardings,
    LAG(drd.current_day_boardings, 1) OVER (
        PARTITION BY drd.route_id
        ORDER BY drd.service_date
    ) AS previous_day_boardings,
    (
        drd.current_day_boardings -
        LAG(drd.current_day_boardings, 1) OVER (
            PARTITION BY drd.route_id
            ORDER BY drd.service_date
        )
    ) AS daily_boarding_change,
    ROUND(
        100.0 * (
            drd.current_day_boardings -
            LAG(drd.current_day_boardings, 1) OVER (
                PARTITION BY drd.route_id
                ORDER BY drd.service_date
            )
        ) / NULLIF(
            LAG(drd.current_day_boardings, 1) OVER (
                PARTITION BY drd.route_id
                ORDER BY drd.service_date
            ),
            0
        ),
        2
    ) AS day_over_day_growth_pct
FROM daily_route_demand drd
ORDER BY drd.route_number, drd.service_date;


-- ---------------------------------------------------------------------
-- QUERY 24: Identify the Busiest Route for Each Day Using ROW_NUMBER()
-- Purpose: Extract the single highest-ridership route for every calendar day.
-- Administrator Insight: Reveals shifting weekday vs weekend ridership patterns (e.g. commuter
-- corridors dominating Tuesday-Thursday while shopping/recreation corridors lead on Saturday-Sunday).
-- ---------------------------------------------------------------------
WITH daily_route_boardings AS (
    SELECT
        t.service_date,
        r.route_id,
        r.route_number,
        r.route_name,
        COALESCE(SUM(pc.boarding_count), 0) AS total_boardings,
        COUNT(DISTINCT t.trip_id) AS trips_operated,
        ROW_NUMBER() OVER (
            PARTITION BY t.service_date
            ORDER BY COALESCE(SUM(pc.boarding_count), 0) DESC, r.route_id ASC
        ) AS daily_rank
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    GROUP BY t.service_date, r.route_id, r.route_number, r.route_name
)
SELECT
    drb.service_date,
    TO_CHAR(drb.service_date, 'Day') AS day_of_week,
    drb.route_id,
    drb.route_number,
    drb.route_name,
    drb.total_boardings AS winning_route_boardings,
    drb.trips_operated,
    ROUND(
        drb.total_boardings::NUMERIC / NULLIF(drb.trips_operated, 0),
        2
    ) AS avg_boardings_per_trip
FROM daily_route_boardings drb
WHERE drb.daily_rank = 1
ORDER BY drb.service_date ASC;

-- =====================================================================
-- END OF ADVANCED SQL ANALYTICS
-- =====================================================================
