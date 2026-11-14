-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/08_procedures.sql
-- PURPOSE: Production Stored Procedures (3 Procedures)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- =====================================================================
-- PROCEDURE 1: sp_create_trip
-- Purpose: Concurrency-safe, transactional trip dispatch validator and generator.
-- Validations:
--   1. Schedule existence and route ownership.
--   2. Schedule active status and effective date window.
--   3. Permitted operating day (ISO DOW match in schedule_operating_days).
--   4. Bus existence and ACTIVE operational status (row-locked).
--   5. Driver existence and AVAILABLE operational status (row-locked).
--   6. Conflicting bus overlapping assignment check.
--   7. Conflicting driver overlapping assignment check.
--   8. Scheduled start timestamp alignment with service date and departure time.
-- Returns: Newly generated trip_id.
-- =====================================================================
CREATE OR REPLACE PROCEDURE sp_create_trip(
    p_schedule_id BIGINT,
    p_route_id BIGINT,
    p_bus_id BIGINT,
    p_driver_id BIGINT,
    p_service_date DATE,
    p_scheduled_start TIMESTAMPTZ,
    INOUT p_trip_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_sched_route_id BIGINT;
    v_sched_status VARCHAR(20);
    v_effective_from DATE;
    v_effective_until DATE;
    v_departure_time TIME;
    v_duration_min INTEGER;
    v_iso_dow SMALLINT;
    v_day_allowed BOOLEAN;
    v_bus_status VARCHAR(20);
    v_driver_status VARCHAR(20);
    v_expected_start TIMESTAMPTZ;
    v_new_trip_end TIMESTAMPTZ;
    v_conflict_count INTEGER;
BEGIN
    -- 1. Input parameter non-null validations
    IF p_schedule_id IS NULL OR p_route_id IS NULL OR p_bus_id IS NULL OR
       p_driver_id IS NULL OR p_service_date IS NULL OR p_scheduled_start IS NULL THEN
        RAISE EXCEPTION 'All input parameters for sp_create_trip are required and cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    -- 2. Validate schedule existence, route ownership, status, and effective dates
    SELECT
        s.route_id,
        s.status,
        s.effective_from,
        s.effective_until,
        s.departure_time,
        r.estimated_duration_minutes
    INTO
        v_sched_route_id,
        v_sched_status,
        v_effective_from,
        v_effective_until,
        v_departure_time,
        v_duration_min
    FROM schedules s
    JOIN routes r ON s.route_id = r.route_id
    WHERE s.schedule_id = p_schedule_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Schedule ID % does not exist in the system', p_schedule_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_sched_route_id <> p_route_id THEN
        RAISE EXCEPTION 'Schedule ID % belongs to route ID %, not provided route ID %',
            p_schedule_id, v_sched_route_id, p_route_id
            USING ERRCODE = 'check_violation';
    END IF;

    IF v_sched_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Schedule ID % is not ACTIVE (current status: %)', p_schedule_id, v_sched_status
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    IF p_service_date < v_effective_from OR
       (v_effective_until IS NOT NULL AND p_service_date > v_effective_until) THEN
        RAISE EXCEPTION 'Service date % is outside effective schedule date range (% to %)',
            p_service_date, v_effective_from, COALESCE(v_effective_until::TEXT, 'indefinite')
            USING ERRCODE = 'check_violation';
    END IF;

    -- 3. Verify operating day permission
    v_iso_dow := EXTRACT(ISODOW FROM p_service_date)::SMALLINT;

    SELECT EXISTS (
        SELECT 1
        FROM schedule_operating_days sod
        WHERE sod.schedule_id = p_schedule_id
          AND sod.day_id = v_iso_dow
    ) INTO v_day_allowed;

    IF NOT v_day_allowed THEN
        RAISE EXCEPTION 'Service date % falls on ISO day % which is not an authorized operating day for schedule ID %',
            p_service_date, v_iso_dow, p_schedule_id
            USING ERRCODE = 'check_violation';
    END IF;

    -- 4. Concurrency-safe bus verification (row lock)
    SELECT b.status
    INTO v_bus_status
    FROM buses b
    WHERE b.bus_id = p_bus_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bus ID % does not exist', p_bus_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_bus_status <> 'ACTIVE' THEN
        RAISE EXCEPTION 'Bus ID % cannot be dispatched: status is %, expected ACTIVE',
            p_bus_id, v_bus_status
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    -- 5. Concurrency-safe driver verification (row lock)
    SELECT d.status
    INTO v_driver_status
    FROM drivers d
    WHERE d.driver_id = p_driver_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Driver ID % does not exist', p_driver_id
            USING ERRCODE = 'no_data_found';
    END IF;

    IF v_driver_status <> 'AVAILABLE' THEN
        RAISE EXCEPTION 'Driver ID % cannot be assigned: status is %, expected AVAILABLE',
            p_driver_id, v_driver_status
            USING ERRCODE = 'object_not_in_prerequisite_state';
    END IF;

    -- 6. Validate scheduled start timestamp matches service date and departure time
    v_expected_start := (p_service_date + v_departure_time)::TIMESTAMPTZ;
    IF p_scheduled_start <> v_expected_start THEN
        RAISE EXCEPTION 'Provided scheduled start (%) does not match schedule departure time (%) on service date (%)',
            p_scheduled_start, v_departure_time, p_service_date
            USING ERRCODE = 'check_violation';
    END IF;

    v_new_trip_end := p_scheduled_start + (COALESCE(v_duration_min, 60) * INTERVAL '1 minute');

    -- 7. Prevent conflicting overlapping bus assignment
    SELECT COUNT(*)
    INTO v_conflict_count
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    WHERE t.bus_id = p_bus_id
      AND t.service_date = p_service_date
      AND t.trip_status IN ('SCHEDULED', 'RUNNING')
      AND (
          p_scheduled_start < (t.scheduled_start + (COALESCE(r.estimated_duration_minutes, 60) * INTERVAL '1 minute'))
          AND
          v_new_trip_end > t.scheduled_start
      );

    IF v_conflict_count > 0 THEN
        RAISE EXCEPTION 'Conflict: Bus ID % is already scheduled or running an overlapping trip on %',
            p_bus_id, p_service_date
            USING ERRCODE = 'unique_violation';
    END IF;

    -- 8. Prevent conflicting overlapping driver assignment
    SELECT COUNT(*)
    INTO v_conflict_count
    FROM trips t
    JOIN routes r ON t.route_id = r.route_id
    WHERE t.driver_id = p_driver_id
      AND t.service_date = p_service_date
      AND t.trip_status IN ('SCHEDULED', 'RUNNING')
      AND (
          p_scheduled_start < (t.scheduled_start + (COALESCE(r.estimated_duration_minutes, 60) * INTERVAL '1 minute'))
          AND
          v_new_trip_end > t.scheduled_start
      );

    IF v_conflict_count > 0 THEN
        RAISE EXCEPTION 'Conflict: Driver ID % is already assigned to an overlapping trip on %',
            p_driver_id, p_service_date
            USING ERRCODE = 'unique_violation';
    END IF;

    -- 9. Insert trip record
    INSERT INTO trips (
        schedule_id,
        route_id,
        bus_id,
        driver_id,
        service_date,
        scheduled_start,
        trip_status
    )
    VALUES (
        p_schedule_id,
        p_route_id,
        p_bus_id,
        p_driver_id,
        p_service_date,
        p_scheduled_start,
        'SCHEDULED'
    )
    RETURNING trips.trip_id INTO p_trip_id;

    RAISE NOTICE 'Trip ID % successfully scheduled for route % on %',
        p_trip_id, p_route_id, p_service_date;
END;
$$;


-- =====================================================================
-- PROCEDURE 2: sp_record_passenger_count
-- Purpose: Insert or update passenger boarding and alighting count for a stop log.
-- Respects UNIQUE constraint on trip_stop_log_id using ON CONFLICT DO UPDATE.
-- =====================================================================
CREATE OR REPLACE PROCEDURE sp_record_passenger_count(
    p_trip_stop_log_id BIGINT,
    p_boarding_count INTEGER,
    p_alighting_count INTEGER,
    INOUT p_message TEXT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stop_log_exists BOOLEAN;
    v_is_update BOOLEAN := FALSE;
BEGIN
    IF p_trip_stop_log_id IS NULL OR p_boarding_count IS NULL OR p_alighting_count IS NULL THEN
        RAISE EXCEPTION 'Parameters for sp_record_passenger_count cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF p_boarding_count < 0 THEN
        RAISE EXCEPTION 'Boarding count cannot be negative: %', p_boarding_count
            USING ERRCODE = 'check_violation';
    END IF;

    IF p_alighting_count < 0 THEN
        RAISE EXCEPTION 'Alighting count cannot be negative: %', p_alighting_count
            USING ERRCODE = 'check_violation';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM trip_stop_logs tsl WHERE tsl.trip_stop_log_id = p_trip_stop_log_id
    ) INTO v_stop_log_exists;

    IF NOT v_stop_log_exists THEN
        RAISE EXCEPTION 'Trip stop log ID % does not exist', p_trip_stop_log_id
            USING ERRCODE = 'no_data_found';
    END IF;

    SELECT EXISTS (
        SELECT 1 FROM passenger_counts pc WHERE pc.trip_stop_log_id = p_trip_stop_log_id
    ) INTO v_is_update;

    INSERT INTO passenger_counts (
        trip_stop_log_id,
        boarding_count,
        alighting_count,
        recorded_at
    )
    VALUES (
        p_trip_stop_log_id,
        p_boarding_count,
        p_alighting_count,
        CURRENT_TIMESTAMP
    )
    ON CONFLICT (trip_stop_log_id)
    DO UPDATE SET
        boarding_count = EXCLUDED.boarding_count,
        alighting_count = EXCLUDED.alighting_count,
        recorded_at = CURRENT_TIMESTAMP;

    IF v_is_update THEN
        p_message := FORMAT('Passenger count updated for stop log %s: %s boardings, %s alightings',
                            p_trip_stop_log_id, p_boarding_count, p_alighting_count);
    ELSE
        p_message := FORMAT('Passenger count inserted for stop log %s: %s boardings, %s alightings',
                            p_trip_stop_log_id, p_boarding_count, p_alighting_count);
    END IF;

    RAISE NOTICE '%', p_message;
END;
$$;


-- =====================================================================
-- PROCEDURE 3: sp_record_delay
-- Purpose: Log transit delay incidents with automated severity classification.
-- Uses fn_calculate_delay_severity() for severity tier assignment.
-- =====================================================================
CREATE OR REPLACE PROCEDURE sp_record_delay(
    p_trip_stop_log_id BIGINT,
    p_reason_id BIGINT,
    p_delay_seconds INTEGER,
    p_remarks TEXT,
    INOUT p_delay_id BIGINT DEFAULT NULL
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_stop_log_exists BOOLEAN;
    v_reason_exists BOOLEAN;
    v_severity VARCHAR(20);
BEGIN
    IF p_trip_stop_log_id IS NULL OR p_reason_id IS NULL OR p_delay_seconds IS NULL THEN
        RAISE EXCEPTION 'Trip stop log ID, reason ID, and delay seconds cannot be NULL'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF p_delay_seconds < 0 THEN
        RAISE EXCEPTION 'Delay seconds cannot be negative: %', p_delay_seconds
            USING ERRCODE = 'check_violation';
    END IF;

    -- Validate trip stop log
    SELECT EXISTS (
        SELECT 1 FROM trip_stop_logs tsl WHERE tsl.trip_stop_log_id = p_trip_stop_log_id
    ) INTO v_stop_log_exists;

    IF NOT v_stop_log_exists THEN
        RAISE EXCEPTION 'Trip stop log ID % does not exist', p_trip_stop_log_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Validate delay reason
    SELECT EXISTS (
        SELECT 1 FROM delay_reasons drn WHERE drn.reason_id = p_reason_id
    ) INTO v_reason_exists;

    IF NOT v_reason_exists THEN
        RAISE EXCEPTION 'Delay reason ID % does not exist', p_reason_id
            USING ERRCODE = 'no_data_found';
    END IF;

    -- Calculate severity using business function
    v_severity := fn_calculate_delay_severity(p_delay_seconds);

    -- Insert delay record
    INSERT INTO delay_records (
        trip_stop_log_id,
        reason_id,
        delay_seconds,
        severity,
        remarks,
        recorded_at
    )
    VALUES (
        p_trip_stop_log_id,
        p_reason_id,
        p_delay_seconds,
        v_severity,
        COALESCE(p_remarks, 'Operational delay logged via sp_record_delay'),
        CURRENT_TIMESTAMP
    )
    RETURNING delay_records.delay_id INTO p_delay_id;

    RAISE NOTICE 'Delay incident ID % logged (Severity: %, Duration: %s)',
        p_delay_id, v_severity, p_delay_seconds;
END;
$$;

-- =====================================================================
-- END OF STORED PROCEDURES SCRIPT
-- =====================================================================
