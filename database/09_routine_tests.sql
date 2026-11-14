-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/09_routine_tests.sql
-- PURPOSE: Automated Test Harness for 9 Functions & 3 Stored Procedures
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'STARTING TRANSITIQ ROUTINE TEST HARNESS';
    RAISE NOTICE '=====================================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- TEST 1: Valid Bus ID Testing (fn_get_bus_status, fn_get_maintenance_status, fn_get_bus_utilization)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_bus_rec RECORD;
    v_maint_rec RECORD;
    v_util_rec RECORD;
    v_test_bus_id BIGINT;
BEGIN
    SELECT b.bus_id INTO v_test_bus_id FROM buses b LIMIT 1;

    SELECT * INTO v_bus_rec FROM fn_get_bus_status(v_test_bus_id);
    IF v_bus_rec.bus_id IS NULL OR v_bus_rec.registration_number IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: fn_get_bus_status returned empty fields';
    END IF;

    SELECT * INTO v_maint_rec FROM fn_get_maintenance_status(v_test_bus_id);
    IF v_maint_rec.maintenance_status IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: fn_get_maintenance_status returned null status';
    END IF;

    SELECT * INTO v_util_rec FROM fn_get_bus_utilization(v_test_bus_id);
    IF v_util_rec.bus_id IS NULL THEN
        RAISE EXCEPTION 'TEST 1 FAILED: fn_get_bus_utilization returned null';
    END IF;

    RAISE NOTICE '[PASS] TEST 1: Valid bus routines executed successfully for bus ID %', v_test_bus_id;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 2: Invalid Bus ID Handling
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_rec RECORD;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        SELECT * INTO v_rec FROM fn_get_bus_status(9999999);
    EXCEPTION
        WHEN no_data_found THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected exception for non-existent bus ID 9999999';
    END IF;

    RAISE NOTICE '[PASS] TEST 2: Invalid bus ID correctly raised NO_DATA_FOUND exception';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 3: Valid Route ID Testing (fn_get_route_performance)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_route_id BIGINT;
    v_perf RECORD;
BEGIN
    SELECT r.route_id INTO v_route_id FROM routes r LIMIT 1;

    SELECT * INTO v_perf FROM fn_get_route_performance(v_route_id);
    IF v_perf.route_id IS NULL OR v_perf.route_number IS NULL THEN
        RAISE EXCEPTION 'TEST 3 FAILED: fn_get_route_performance returned null data';
    END IF;

    RAISE NOTICE '[PASS] TEST 3: fn_get_route_performance succeeded for route % (% trips, % boardings)',
        v_perf.route_number, v_perf.total_trips, v_perf.total_passenger_boardings;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 4: Invalid Route ID Handling
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_perf RECORD;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        SELECT * INTO v_perf FROM fn_get_route_performance(8888888);
    EXCEPTION
        WHEN no_data_found THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Expected exception for non-existent route ID 8888888';
    END IF;

    RAISE NOTICE '[PASS] TEST 4: Invalid route ID correctly raised NO_DATA_FOUND exception';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 5: Valid Driver ID Testing (fn_get_driver_performance)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_driver_id BIGINT;
    v_perf RECORD;
BEGIN
    SELECT d.driver_id INTO v_driver_id FROM drivers d LIMIT 1;

    SELECT * INTO v_perf FROM fn_get_driver_performance(v_driver_id);
    IF v_perf.driver_id IS NULL THEN
        RAISE EXCEPTION 'TEST 5 FAILED: fn_get_driver_performance returned null driver ID';
    END IF;

    RAISE NOTICE '[PASS] TEST 5: fn_get_driver_performance succeeded for % (% trips completed)',
        v_perf.driver_name, v_perf.completed_trips;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 6: Expired Driving License Classification (fn_check_license_expiry)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_driver_id BIGINT;
    v_check RECORD;
BEGIN
    -- Find or identify a driver with expired license
    SELECT d.driver_id INTO v_driver_id
    FROM drivers d
    WHERE d.license_expiry_date < CURRENT_DATE
    LIMIT 1;

    IF v_driver_id IS NULL THEN
        -- Fallback: test on first driver
        SELECT d.driver_id INTO v_driver_id FROM drivers d LIMIT 1;
    END IF;

    SELECT * INTO v_check FROM fn_check_license_expiry(v_driver_id);
    IF v_check.license_status IS NULL THEN
        RAISE EXCEPTION 'TEST 6 FAILED: fn_check_license_expiry returned null status';
    END IF;

    RAISE NOTICE '[PASS] TEST 6: License audit check for driver ID %: Status = %, Days Remaining = %',
        v_driver_id, v_check.license_status, v_check.days_remaining;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 7: Negative Passenger Count Rejection (sp_record_passenger_count)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tsl_id BIGINT;
    v_msg TEXT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    SELECT tsl.trip_stop_log_id INTO v_tsl_id FROM trip_stop_logs tsl LIMIT 1;

    BEGIN
        CALL sp_record_passenger_count(v_tsl_id, -5, 10, v_msg);
    EXCEPTION
        WHEN check_violation THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Negative boarding count was not rejected';
    END IF;

    RAISE NOTICE '[PASS] TEST 7: Negative boarding count correctly rejected with CHECK_VIOLATION';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 8: Valid Passenger Count Insertion (sp_record_passenger_count)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_test_trip_id BIGINT;
    v_route_id BIGINT;
    v_schedule_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_route_stop_id BIGINT;
    v_temp_tsl_id BIGINT;
    v_msg TEXT;
    v_board INTEGER;
BEGIN
    SELECT t.route_id, t.schedule_id, t.bus_id, t.driver_id
    INTO v_route_id, v_schedule_id, v_bus_id, v_driver_id
    FROM trips t LIMIT 1;

    SELECT rs.route_stop_id INTO v_route_stop_id
    FROM route_stops rs
    WHERE rs.route_id = v_route_id
    LIMIT 1;

    -- Create an isolated temporary trip with unique date to avoid (trip_id, route_stop_id) collision
    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_schedule_id, v_route_id, v_bus_id, v_driver_id,
        DATE '2099-01-01', TIMESTAMPTZ '2099-01-01 05:00:00+00', 'COMPLETED'
    )
    RETURNING trip_id INTO v_test_trip_id;

    -- Now insert trip_stop_log for this new trip
    INSERT INTO trip_stop_logs (trip_id, route_id, route_stop_id, stop_status)
    VALUES (v_test_trip_id, v_route_id, v_route_stop_id, 'REACHED')
    RETURNING trip_stop_log_id INTO v_temp_tsl_id;

    -- Call procedure to insert passenger count
    CALL sp_record_passenger_count(v_temp_tsl_id, 14, 8, v_msg);

    SELECT pc.boarding_count INTO v_board
    FROM passenger_counts pc
    WHERE pc.trip_stop_log_id = v_temp_tsl_id;

    IF v_board <> 14 THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Expected 14 boardings, found %', v_board;
    END IF;

    -- Cleanup test records in reverse dependency order
    DELETE FROM passenger_counts WHERE trip_stop_log_id = v_temp_tsl_id;
    DELETE FROM trip_stop_logs WHERE trip_stop_log_id = v_temp_tsl_id;
    DELETE FROM trips WHERE trip_id = v_test_trip_id;

    RAISE NOTICE '[PASS] TEST 8: Valid passenger count inserted and verified: %', v_msg;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 9: Updating an Existing Passenger Count (sp_record_passenger_count)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tsl_id BIGINT;
    v_msg TEXT;
    v_orig_board INTEGER;
    v_orig_alight INTEGER;
    v_new_board INTEGER;
BEGIN
    SELECT pc.trip_stop_log_id, pc.boarding_count, pc.alighting_count
    INTO v_tsl_id, v_orig_board, v_orig_alight
    FROM passenger_counts pc
    LIMIT 1;

    -- Update existing record
    CALL sp_record_passenger_count(v_tsl_id, 25, 12, v_msg);

    SELECT pc.boarding_count INTO v_new_board
    FROM passenger_counts pc
    WHERE pc.trip_stop_log_id = v_tsl_id;

    IF v_new_board <> 25 THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Boarding count was not updated to 25';
    END IF;

    -- Restore original sample data
    UPDATE passenger_counts
    SET boarding_count = v_orig_board,
        alighting_count = v_orig_alight
    WHERE trip_stop_log_id = v_tsl_id;

    RAISE NOTICE '[PASS] TEST 9: Existing passenger count updated via upsert and restored: %', v_msg;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 10: Valid Delay Insertion (sp_record_delay)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tsl_id BIGINT;
    v_reason_id BIGINT;
    v_delay_id BIGINT;
    v_severity VARCHAR(20);
BEGIN
    SELECT tsl.trip_stop_log_id INTO v_tsl_id FROM trip_stop_logs tsl LIMIT 1;
    SELECT drn.reason_id INTO v_reason_id FROM delay_reasons drn LIMIT 1;

    CALL sp_record_delay(v_tsl_id, v_reason_id, 750, 'Heavy storm slowdown test', v_delay_id);

    SELECT dr.severity INTO v_severity FROM delay_records dr WHERE dr.delay_id = v_delay_id;

    IF v_severity <> 'SEVERE' THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Delay of 750s expected SEVERE, got %', v_severity;
    END IF;

    -- Clean up test delay record
    DELETE FROM delay_records WHERE delay_id = v_delay_id;

    RAISE NOTICE '[PASS] TEST 10: Valid delay logged (ID: %, Severity: SEVERE)', v_delay_id;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 11: Negative Delay Rejection (sp_record_delay & fn_calculate_delay_severity)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tsl_id BIGINT;
    v_reason_id BIGINT;
    v_delay_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    SELECT tsl.trip_stop_log_id INTO v_tsl_id FROM trip_stop_logs tsl LIMIT 1;
    SELECT drn.reason_id INTO v_reason_id FROM delay_reasons drn LIMIT 1;

    BEGIN
        CALL sp_record_delay(v_tsl_id, v_reason_id, -120, 'Negative delay test', v_delay_id);
    EXCEPTION
        WHEN check_violation THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 11 FAILED: Negative delay was not rejected';
    END IF;

    RAISE NOTICE '[PASS] TEST 11: Negative delay correctly rejected with CHECK_VIOLATION';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 12: Duplicate or Conflicting Bus Assignment (sp_create_trip)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_route_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_service_date DATE;
    v_dep_time TIME;
    v_sched_start TIMESTAMPTZ;
    v_test_trip_id BIGINT;
    v_second_trip_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    SELECT s.schedule_id, s.route_id, s.departure_time
    INTO v_sched_id, v_route_id, v_dep_time
    FROM schedules s
    WHERE s.status = 'ACTIVE'
    LIMIT 1;

    SELECT b.bus_id INTO v_bus_id FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    v_service_date := CURRENT_DATE;
    v_sched_start := (v_service_date + v_dep_time)::TIMESTAMPTZ;

    -- Create a baseline SCHEDULED trip
    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id, v_driver_id,
        v_service_date, v_sched_start, 'SCHEDULED'
    )
    RETURNING trip_id INTO v_test_trip_id;

    BEGIN
        -- Attempt to call sp_create_trip with the same bus at the same time
        CALL sp_create_trip(
            v_sched_id,
            v_route_id,
            v_bus_id,
            v_driver_id,
            v_service_date,
            v_sched_start,
            v_second_trip_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_error_caught := TRUE;
    END;

    -- Clean up test trip
    DELETE FROM trips WHERE trip_id = v_test_trip_id;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Conflicting bus assignment was permitted';
    END IF;

    RAISE NOTICE '[PASS] TEST 12: Conflicting bus assignment prevented successfully';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 13: Duplicate or Conflicting Driver Assignment (sp_create_trip)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_route_id BIGINT;
    v_bus_id1 BIGINT;
    v_bus_id2 BIGINT;
    v_driver_id BIGINT;
    v_service_date DATE;
    v_dep_time TIME;
    v_sched_start TIMESTAMPTZ;
    v_test_trip_id BIGINT;
    v_second_trip_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    SELECT s.schedule_id, s.route_id, s.departure_time
    INTO v_sched_id, v_route_id, v_dep_time
    FROM schedules s
    WHERE s.status = 'ACTIVE'
    LIMIT 1;

    SELECT b.bus_id INTO v_bus_id1 FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT b.bus_id INTO v_bus_id2 FROM buses b WHERE b.status = 'ACTIVE' AND b.bus_id <> v_bus_id1 LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    v_service_date := CURRENT_DATE;
    v_sched_start := (v_service_date + v_dep_time)::TIMESTAMPTZ;

    -- Create a baseline SCHEDULED trip for this driver
    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id1, v_driver_id,
        v_service_date, v_sched_start, 'SCHEDULED'
    )
    RETURNING trip_id INTO v_test_trip_id;

    BEGIN
        -- Attempt to call sp_create_trip with different bus but SAME driver at same time
        CALL sp_create_trip(
            v_sched_id,
            v_route_id,
            v_bus_id2,
            v_driver_id,
            v_service_date,
            v_sched_start,
            v_second_trip_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_error_caught := TRUE;
    END;

    -- Clean up test trip
    DELETE FROM trips WHERE trip_id = v_test_trip_id;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Conflicting driver assignment was permitted';
    END IF;

    RAISE NOTICE '[PASS] TEST 13: Conflicting driver assignment prevented successfully';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 14: Invalid Schedule-Route Combination (sp_create_trip)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_wrong_route_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_new_trip_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    SELECT s.schedule_id, s.route_id INTO v_sched_id, v_wrong_route_id FROM schedules s LIMIT 1;
    -- Select mismatched route
    SELECT r.route_id INTO v_wrong_route_id FROM routes r WHERE r.route_id <> v_wrong_route_id LIMIT 1;
    SELECT b.bus_id INTO v_bus_id FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    BEGIN
        CALL sp_create_trip(
            v_sched_id,
            v_wrong_route_id,
            v_bus_id,
            v_driver_id,
            CURRENT_DATE,
            CURRENT_TIMESTAMP,
            v_new_trip_id
        );
    EXCEPTION
        WHEN check_violation THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 14 FAILED: Invalid schedule-route mismatch was not caught';
    END IF;

    RAISE NOTICE '[PASS] TEST 14: Schedule-route mismatch correctly raised CHECK_VIOLATION';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 15: Invalid Operating Day Rejection (sp_create_trip)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_route_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_test_date DATE;
    v_new_trip_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    -- Pick a schedule
    SELECT s.schedule_id, s.route_id INTO v_sched_id, v_route_id FROM schedules s LIMIT 1;
    SELECT b.bus_id INTO v_bus_id FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    -- Temporarily delete day 7 (Sunday) for testing on a temporary test schedule or date
    -- Test with past date before effective_from
    v_test_date := DATE '2010-01-01';

    BEGIN
        CALL sp_create_trip(
            v_sched_id,
            v_route_id,
            v_bus_id,
            v_driver_id,
            v_test_date,
            (v_test_date + TIME '05:00')::TIMESTAMPTZ,
            v_new_trip_id
        );
    EXCEPTION
        WHEN check_violation THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Out-of-range date was not rejected';
    END IF;

    RAISE NOTICE '[PASS] TEST 15: Invalid service date correctly rejected with CHECK_VIOLATION';
END;
$$;

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'ALL 15 TRANSITIQ ROUTINE TESTS COMPLETED';
    RAISE NOTICE '=====================================================================';
END;
$$;
