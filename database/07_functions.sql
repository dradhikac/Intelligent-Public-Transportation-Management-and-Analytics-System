-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/07_functions.sql
-- PURPOSE: Production PL/pgSQL Business Functions (9 Functions)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- =====================================================================
-- MODULE A: FLEET MANAGEMENT
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION 1: fn_get_bus_status
-- Purpose: Retrieve current operational status and technical profile of a bus.
-- Error Handling: Validates bus existence; raises NOT_FOUND exception on invalid ID.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_bus_status(p_bus_id BIGINT)
RETURNS TABLE (
    bus_id BIGINT,
    registration_number VARCHAR(20),
    bus_type VARCHAR(50),
    operational_status VARCHAR(20),
    last_service_date DATE
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_bus_id IS NULL THEN
        RAISE EXCEPTION 'Bus ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM buses b WHERE b.bus_id = p_bus_id) THEN
        RAISE EXCEPTION 'Bus with ID % does not exist in the fleet', p_bus_id
            USING ERRCODE = 'no_data_found';
    END IF;

    RETURN QUERY
    SELECT
        b.bus_id,
        b.registration_number,
        bt.type_name AS bus_type,
        b.status AS operational_status,
        b.last_service_date
    FROM buses b
    JOIN bus_types bt ON b.bus_type_id = bt.bus_type_id
    WHERE b.bus_id = p_bus_id;
END;
$$;


-- ---------------------------------------------------------------------
-- FUNCTION 2: fn_get_maintenance_status
-- Purpose: Determine upcoming maintenance urgency based on the latest service record.
-- Classification: OVERDUE, DUE TODAY, DUE SOON (within 30 days), NOT DUE, NO SERVICE DATE.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_maintenance_status(p_bus_id BIGINT)
RETURNS TABLE (
    bus_id BIGINT,
    registration_number VARCHAR(20),
    last_service_date DATE,
    next_service_date DATE,
    maintenance_status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_bus_exists BOOLEAN;
    v_reg_no VARCHAR(20);
    v_last_service DATE;
    v_next_service DATE;
    v_status TEXT;
BEGIN
    IF p_bus_id IS NULL THEN
        RAISE EXCEPTION 'Bus ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT
        b.registration_number,
        b.last_service_date
    INTO
        v_reg_no,
        v_last_service
    FROM buses b
    WHERE b.bus_id = p_bus_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bus with ID % does not exist in the fleet', p_bus_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Retrieve latest scheduled next service date
    SELECT mr.next_service_date
    INTO v_next_service
    FROM maintenance_records mr
    WHERE mr.bus_id = p_bus_id
    ORDER BY mr.maintenance_date DESC, mr.maintenance_id DESC
    LIMIT 1;

    -- Classify urgency based on service interval
    IF v_next_service IS NULL THEN
        v_status := 'NO SERVICE DATE';
    ELSIF v_next_service < CURRENT_DATE THEN
        v_status := 'OVERDUE';
    ELSIF v_next_service = CURRENT_DATE THEN
        v_status := 'DUE TODAY';
    ELSIF v_next_service <= CURRENT_DATE + 30 THEN
        v_status := 'DUE SOON (within 30 days)';
    ELSE
        v_status := 'NOT DUE';
    END IF;

    RETURN QUERY
    SELECT
        p_bus_id,
        v_reg_no,
        v_last_service,
        v_next_service,
        v_status;
END;
$$;


-- ---------------------------------------------------------------------
-- FUNCTION 3: fn_get_bus_utilization
-- Purpose: Calculate operational trip-based completion efficiency for a bus.
-- Note: Represents a trip-based schedule completion proxy, not engine-hour utilization.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_bus_utilization(p_bus_id BIGINT)
RETURNS TABLE (
    bus_id BIGINT,
    total_assigned_trips BIGINT,
    completed_trips BIGINT,
    cancelled_trips BIGINT,
    completion_percentage NUMERIC(5,2)
)
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_bus_id IS NULL THEN
        RAISE EXCEPTION 'Bus ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF NOT EXISTS (SELECT 1 FROM buses b WHERE b.bus_id = p_bus_id) THEN
        RAISE EXCEPTION 'Bus with ID % does not exist', p_bus_id
            USING ERRCODE = 'no_data_found';
    END IF;

    RETURN QUERY
    SELECT
        p_bus_id,
        COUNT(t.trip_id) AS total_assigned_trips,
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) AS completed_trips,
        COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END) AS cancelled_trips,
        ROUND(
            100.0 * COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END) /
            NULLIF(COUNT(t.trip_id), 0),
            2
        ) AS completion_percentage
    FROM trips t
    WHERE t.bus_id = p_bus_id;
END;
$$;


-- =====================================================================
-- MODULE B: TRIP AND ROUTE MANAGEMENT
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION 4: fn_calculate_trip_delay
-- Purpose: Compute actual schedule variance (delay in seconds & minutes) at a bus stop log.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calculate_trip_delay(p_trip_stop_log_id BIGINT)
RETURNS TABLE (
    trip_stop_log_id BIGINT,
    scheduled_arrival TIMESTAMPTZ,
    actual_arrival TIMESTAMPTZ,
    delay_seconds INTEGER,
    delay_minutes NUMERIC(8,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sched TIMESTAMPTZ;
    v_actual TIMESTAMPTZ;
    v_sec INTEGER;
    v_min NUMERIC(8,2);
BEGIN
    IF p_trip_stop_log_id IS NULL THEN
        RAISE EXCEPTION 'Trip stop log ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT
        tsl.scheduled_arrival_at,
        tsl.actual_arrival_at
    INTO
        v_sched,
        v_actual
    FROM trip_stop_logs tsl
    WHERE tsl.trip_stop_log_id = p_trip_stop_log_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Trip stop log with ID % does not exist', p_trip_stop_log_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_sched IS NULL OR v_actual IS NULL THEN
        RAISE NOTICE 'Stop log ID % has incomplete arrival timestamps; cannot compute delay', p_trip_stop_log_id;
        RETURN QUERY SELECT p_trip_stop_log_id, v_sched, v_actual, NULL::INTEGER, NULL::NUMERIC(8,2);
        RETURN;
    END IF;

    v_sec := EXTRACT(EPOCH FROM (v_actual - v_sched))::INTEGER;
    v_min := ROUND(v_sec / 60.0, 2);

    RETURN QUERY SELECT p_trip_stop_log_id, v_sched, v_actual, v_sec, v_min;
END;
$$;


-- ---------------------------------------------------------------------
-- FUNCTION 5: fn_get_route_performance
-- Purpose: Generate a route-level performance scorecard isolating trip, passenger,
-- and delay metrics into distinct subqueries to eliminate Cartesian row multiplication.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_route_performance(p_route_id BIGINT)
RETURNS TABLE (
    route_id BIGINT,
    route_number VARCHAR(20),
    total_trips BIGINT,
    completed_trips BIGINT,
    cancelled_trips BIGINT,
    total_passenger_boardings BIGINT,
    average_delay_minutes NUMERIC(8,2),
    completion_percentage NUMERIC(5,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_route_number VARCHAR(20);
    v_total_trips BIGINT := 0;
    v_completed_trips BIGINT := 0;
    v_cancelled_trips BIGINT := 0;
    v_boardings BIGINT := 0;
    v_avg_delay NUMERIC(8,2) := 0.00;
    v_completion_pct NUMERIC(5,2) := 0.00;
BEGIN
    IF p_route_id IS NULL THEN
        RAISE EXCEPTION 'Route ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT r.route_number
    INTO v_route_number
    FROM routes r
    WHERE r.route_id = p_route_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Route with ID % does not exist', p_route_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Aggregate trips metrics
    SELECT
        COUNT(t.trip_id),
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END),
        COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END)
    INTO
        v_total_trips,
        v_completed_trips,
        v_cancelled_trips
    FROM trips t
    WHERE t.route_id = p_route_id;

    -- Aggregate passenger metrics (isolated from delay records)
    SELECT COALESCE(SUM(pc.boarding_count), 0)
    INTO v_boardings
    FROM trips t
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN passenger_counts pc ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    WHERE t.route_id = p_route_id;

    -- Aggregate delay metrics
    SELECT ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2)
    INTO v_avg_delay
    FROM trips t
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
    WHERE t.route_id = p_route_id;

    -- Completion percentage
    v_completion_pct := ROUND(100.0 * v_completed_trips / NULLIF(v_total_trips, 0), 2);

    RETURN QUERY
    SELECT
        p_route_id,
        v_route_number,
        v_total_trips,
        v_completed_trips,
        v_cancelled_trips,
        v_boardings,
        v_avg_delay,
        v_completion_pct;
END;
$$;


-- =====================================================================
-- MODULE C: PASSENGER MANAGEMENT
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION 6: fn_get_stop_demand
-- Purpose: Calculate aggregate passenger demand and footfall for a specific stop
-- across all routes that visit it, avoiding duplicate counting.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_stop_demand(p_stop_id BIGINT)
RETURNS TABLE (
    stop_id BIGINT,
    stop_name VARCHAR(100),
    total_boardings BIGINT,
    total_alightings BIGINT,
    total_footfall BIGINT,
    number_of_visits BIGINT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stop_name VARCHAR(100);
BEGIN
    IF p_stop_id IS NULL THEN
        RAISE EXCEPTION 'Stop ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT s.stop_name
    INTO v_stop_name
    FROM stops s
    WHERE s.stop_id = p_stop_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stop with ID % does not exist', p_stop_id
            USING ERRCODE = 'no_data_found';
    END IF;

    RETURN QUERY
    SELECT
        p_stop_id,
        v_stop_name,
        COALESCE(SUM(pc.boarding_count), 0)::BIGINT AS total_boardings,
        COALESCE(SUM(pc.alighting_count), 0)::BIGINT AS total_alightings,
        COALESCE(SUM(pc.boarding_count + pc.alighting_count), 0)::BIGINT AS total_footfall,
        COUNT(tsl.trip_stop_log_id)::BIGINT AS number_of_visits
    FROM route_stops rs
    LEFT JOIN trip_stop_logs tsl
        ON rs.route_stop_id = tsl.route_stop_id
       AND rs.route_id = tsl.route_id
    LEFT JOIN passenger_counts pc
        ON tsl.trip_stop_log_id = pc.trip_stop_log_id
    WHERE rs.stop_id = p_stop_id;
END;
$$;


-- =====================================================================
-- MODULE D: DRIVER AND DELAY MANAGEMENT
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION 7: fn_check_license_expiry
-- Purpose: Audit driver license validity against regulatory thresholds.
-- Classification: EXPIRED, CRITICAL (<=30 days), WARNING (<=90 days), VALID.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_check_license_expiry(p_driver_id BIGINT)
RETURNS TABLE (
    driver_id BIGINT,
    driver_name TEXT,
    license_number VARCHAR(30),
    expiry_date DATE,
    days_remaining INTEGER,
    license_status TEXT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_first_name VARCHAR(50);
    v_last_name VARCHAR(50);
    v_license_no VARCHAR(30);
    v_expiry DATE;
    v_days INTEGER;
    v_status TEXT;
BEGIN
    IF p_driver_id IS NULL THEN
        RAISE EXCEPTION 'Driver ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT
        d.first_name,
        d.last_name,
        d.license_number,
        d.license_expiry_date
    INTO
        v_first_name,
        v_last_name,
        v_license_no,
        v_expiry
    FROM drivers d
    WHERE d.driver_id = p_driver_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Driver with ID % does not exist', p_driver_id
            USING ERRCODE = 'no_data_found';
    END IF;

    v_days := (v_expiry - CURRENT_DATE);

    IF v_expiry < CURRENT_DATE THEN
        v_status := 'EXPIRED';
    ELSIF v_days <= 30 THEN
        v_status := 'CRITICAL (expires within 30 days)';
    ELSIF v_days <= 90 THEN
        v_status := 'WARNING (expires within 90 days)';
    ELSE
        v_status := 'VALID';
    END IF;

    RETURN QUERY
    SELECT
        p_driver_id,
        CONCAT_WS(' ', v_first_name, v_last_name),
        v_license_no,
        v_expiry,
        v_days,
        v_status;
END;
$$;


-- ---------------------------------------------------------------------
-- FUNCTION 8: fn_calculate_delay_severity
-- Purpose: Classify operational delay into standard severity tiers.
-- Thresholds: MINOR (0-300s), MODERATE (301-600s), SEVERE (>600s). Rejects negative values.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_calculate_delay_severity(p_delay_seconds INTEGER)
RETURNS VARCHAR(20)
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
    IF p_delay_seconds IS NULL THEN
        RAISE EXCEPTION 'Delay seconds parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF p_delay_seconds < 0 THEN
        RAISE EXCEPTION 'Delay duration cannot be negative: % seconds', p_delay_seconds
            USING ERRCODE = 'check_violation';
    END IF;

    IF p_delay_seconds <= 300 THEN
        RETURN 'MINOR';
    ELSIF p_delay_seconds <= 600 THEN
        RETURN 'MODERATE';
    ELSE
        RETURN 'SEVERE';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- FUNCTION 9: fn_get_driver_performance
-- Purpose: Generate a comprehensive productivity and delay scorecard for a driver.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_get_driver_performance(p_driver_id BIGINT)
RETURNS TABLE (
    driver_id BIGINT,
    driver_name TEXT,
    total_assigned_trips BIGINT,
    completed_trips BIGINT,
    cancelled_trips BIGINT,
    completion_percentage NUMERIC(5,2),
    average_recorded_delay_minutes NUMERIC(8,2)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_first_name VARCHAR(50);
    v_last_name VARCHAR(50);
    v_total BIGINT := 0;
    v_completed BIGINT := 0;
    v_cancelled BIGINT := 0;
    v_completion_pct NUMERIC(5,2) := 0.00;
    v_avg_delay NUMERIC(8,2) := 0.00;
BEGIN
    IF p_driver_id IS NULL THEN
        RAISE EXCEPTION 'Driver ID parameter cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    SELECT d.first_name, d.last_name
    INTO v_first_name, v_last_name
    FROM drivers d
    WHERE d.driver_id = p_driver_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Driver with ID % does not exist', p_driver_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Aggregate trips
    SELECT
        COUNT(t.trip_id),
        COUNT(CASE WHEN t.trip_status = 'COMPLETED' THEN 1 END),
        COUNT(CASE WHEN t.trip_status = 'CANCELLED' THEN 1 END)
    INTO
        v_total,
        v_completed,
        v_cancelled
    FROM trips t
    WHERE t.driver_id = p_driver_id;

    v_completion_pct := ROUND(100.0 * v_completed / NULLIF(v_total, 0), 2);

    -- Aggregate delay records logged during this driver's trips
    SELECT ROUND(COALESCE(AVG(dr.delay_seconds), 0) / 60.0, 2)
    INTO v_avg_delay
    FROM trips t
    JOIN trip_stop_logs tsl ON t.trip_id = tsl.trip_id
    JOIN delay_records dr ON tsl.trip_stop_log_id = dr.trip_stop_log_id
    WHERE t.driver_id = p_driver_id;

    RETURN QUERY
    SELECT
        p_driver_id,
        CONCAT_WS(' ', v_first_name, v_last_name),
        v_total,
        v_completed,
        v_cancelled,
        v_completion_pct,
        v_avg_delay;
END;
$$;

-- =====================================================================
-- END OF FUNCTIONS SCRIPT
-- =====================================================================
