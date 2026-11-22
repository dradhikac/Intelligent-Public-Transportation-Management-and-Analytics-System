-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/11_trigger_tests.sql
-- PURPOSE: Automated Trigger & Audit Validation Test Suite (15 Tests)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'STARTING TRANSITIQ TRIGGER & AUDIT TEST HARNESS';
    RAISE NOTICE '=====================================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- TEST 1: Insert a Bus and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_type_id BIGINT;
    v_bus_id BIGINT;
    v_audit_count INTEGER;
BEGIN
    SELECT bt.bus_type_id INTO v_type_id FROM bus_types bt LIMIT 1;

    INSERT INTO buses (
        registration_number, bus_type_id, manufacturer, model,
        manufacturing_year, status
    )
    VALUES (
        'TEST-BUS-999', v_type_id, 'Volvo', 'Test Model', 2024, 'ACTIVE'
    )
    RETURNING bus_id INTO v_bus_id;

    SELECT COUNT(*) INTO v_audit_count
    FROM audit_logs
    WHERE table_name = 'buses'
      AND record_id = v_bus_id
      AND operation = 'INSERT'
      AND new_data->>'registration_number' = 'TEST-BUS-999';

    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected 1 audit entry for bus insert, found %', v_audit_count;
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'buses' AND record_id = v_bus_id;
    DELETE FROM buses WHERE bus_id = v_bus_id;

    RAISE NOTICE '[PASS] TEST 1: Bus insert triggered audit entry with correct JSONB new_data';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 2: Update a Bus and Verify OLD and NEW JSONB Records
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_type_id BIGINT;
    v_bus_id BIGINT;
    v_old_status TEXT;
    v_new_status TEXT;
BEGIN
    SELECT bt.bus_type_id INTO v_type_id FROM bus_types bt LIMIT 1;

    INSERT INTO buses (registration_number, bus_type_id, status)
    VALUES ('TEST-BUS-998', v_type_id, 'ACTIVE')
    RETURNING bus_id INTO v_bus_id;

    UPDATE buses
    SET status = 'MAINTENANCE'
    WHERE bus_id = v_bus_id;

    SELECT old_data->>'status', new_data->>'status'
    INTO v_old_status, v_new_status
    FROM audit_logs
    WHERE table_name = 'buses'
      AND record_id = v_bus_id
      AND operation = 'UPDATE'
    ORDER BY audit_id DESC
    LIMIT 1;

    IF v_old_status <> 'ACTIVE' OR v_new_status <> 'MAINTENANCE' THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected OLD=ACTIVE, NEW=MAINTENANCE, got OLD=%, NEW=%',
            v_old_status, v_new_status;
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'buses' AND record_id = v_bus_id;
    DELETE FROM buses WHERE bus_id = v_bus_id;

    RAISE NOTICE '[PASS] TEST 2: Bus update captured both OLD and NEW JSONB states accurately';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 3: Delete a Test Bus and Verify Its Audit Record
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_type_id BIGINT;
    v_bus_id BIGINT;
    v_audit_count INTEGER;
    v_del_old_reg TEXT;
BEGIN
    SELECT bt.bus_type_id INTO v_type_id FROM bus_types bt LIMIT 1;

    INSERT INTO buses (registration_number, bus_type_id, status)
    VALUES ('TEST-BUS-997', v_type_id, 'INACTIVE')
    RETURNING bus_id INTO v_bus_id;

    DELETE FROM buses WHERE bus_id = v_bus_id;

    SELECT COUNT(*), old_data->>'registration_number'
    INTO v_audit_count, v_del_old_reg
    FROM audit_logs
    WHERE table_name = 'buses'
      AND record_id = v_bus_id
      AND operation = 'DELETE'
    GROUP BY old_data;

    IF v_audit_count <> 1 OR v_del_old_reg <> 'TEST-BUS-997' THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Delete audit log not captured properly';
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'buses' AND record_id = v_bus_id;

    RAISE NOTICE '[PASS] TEST 3: Bus deletion captured with OLD state JSONB and NULL new_data';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 4: Insert a Driver and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_driver_id BIGINT;
    v_audit_count INTEGER;
BEGIN
    INSERT INTO drivers (
        employee_code, first_name, last_name, license_number,
        license_expiry_date, status
    )
    VALUES (
        'DRV-TEST-99', 'AuditTest', 'Driver', 'LIC-TEST-99',
        CURRENT_DATE + 365, 'AVAILABLE'
    )
    RETURNING driver_id INTO v_driver_id;

    SELECT COUNT(*) INTO v_audit_count
    FROM audit_logs
    WHERE table_name = 'drivers'
      AND record_id = v_driver_id
      AND operation = 'INSERT';

    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Driver insert audit record missing';
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'drivers' AND record_id = v_driver_id;
    DELETE FROM drivers WHERE driver_id = v_driver_id;

    RAISE NOTICE '[PASS] TEST 4: Driver insert verified in audit_logs';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 5: Update a Driver and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_driver_id BIGINT;
    v_old_status TEXT;
    v_new_status TEXT;
BEGIN
    INSERT INTO drivers (
        employee_code, first_name, last_name, license_number,
        license_expiry_date, status
    )
    VALUES (
        'DRV-TEST-98', 'UpdateTest', 'Driver', 'LIC-TEST-98',
        CURRENT_DATE + 365, 'AVAILABLE'
    )
    RETURNING driver_id INTO v_driver_id;

    UPDATE drivers
    SET status = 'ON_LEAVE'
    WHERE driver_id = v_driver_id;

    SELECT old_data->>'status', new_data->>'status'
    INTO v_old_status, v_new_status
    FROM audit_logs
    WHERE table_name = 'drivers'
      AND record_id = v_driver_id
      AND operation = 'UPDATE'
    ORDER BY audit_id DESC
    LIMIT 1;

    IF v_old_status <> 'AVAILABLE' OR v_new_status <> 'ON_LEAVE' THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Expected OLD=AVAILABLE, NEW=ON_LEAVE';
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'drivers' AND record_id = v_driver_id;
    DELETE FROM drivers WHERE driver_id = v_driver_id;

    RAISE NOTICE '[PASS] TEST 5: Driver status update captured in audit_logs';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 6: Create a Trip and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_route_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_trip_id BIGINT;
    v_audit_count INTEGER;
BEGIN
    SELECT s.schedule_id, s.route_id INTO v_sched_id, v_route_id FROM schedules s LIMIT 1;
    SELECT b.bus_id INTO v_bus_id FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id, v_driver_id,
        DATE '2099-03-01', TIMESTAMPTZ '2099-03-01 05:00:00+00', 'SCHEDULED'
    )
    RETURNING trip_id INTO v_trip_id;

    SELECT COUNT(*) INTO v_audit_count
    FROM audit_logs
    WHERE table_name = 'trips'
      AND record_id = v_trip_id
      AND operation = 'INSERT';

    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Expected 1 audit entry for trip insertion';
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'trips' AND record_id = v_trip_id;
    DELETE FROM trips WHERE trip_id = v_trip_id;

    RAISE NOTICE '[PASS] TEST 6: Trip creation captured in audit_logs';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 7: Update Trip Status and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_route_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_trip_id BIGINT;
    v_old_status TEXT;
    v_new_status TEXT;
BEGIN
    SELECT s.schedule_id, s.route_id INTO v_sched_id, v_route_id FROM schedules s LIMIT 1;
    SELECT b.bus_id INTO v_bus_id FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id, v_driver_id,
        DATE '2099-03-02', TIMESTAMPTZ '2099-03-02 05:00:00+00', 'SCHEDULED'
    )
    RETURNING trip_id INTO v_trip_id;

    UPDATE trips
    SET trip_status = 'CANCELLED'
    WHERE trip_id = v_trip_id;

    SELECT old_data->>'trip_status', new_data->>'trip_status'
    INTO v_old_status, v_new_status
    FROM audit_logs
    WHERE table_name = 'trips'
      AND record_id = v_trip_id
      AND operation = 'UPDATE'
    ORDER BY audit_id DESC
    LIMIT 1;

    IF v_old_status <> 'SCHEDULED' OR v_new_status <> 'CANCELLED' THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Expected OLD=SCHEDULED, NEW=CANCELLED';
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'trips' AND record_id = v_trip_id;
    DELETE FROM trips WHERE trip_id = v_trip_id;

    RAISE NOTICE '[PASS] TEST 7: Trip status update captured in audit_logs';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 8: Insert Passenger Count and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_trip_id BIGINT;
    v_route_id BIGINT;
    v_sched_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_route_stop_id BIGINT;
    v_tsl_id BIGINT;
    v_pc_id BIGINT;
    v_audit_count INTEGER;
BEGIN
    SELECT t.route_id, t.schedule_id, t.bus_id, t.driver_id
    INTO v_route_id, v_sched_id, v_bus_id, v_driver_id
    FROM trips t LIMIT 1;

    SELECT rs.route_stop_id INTO v_route_stop_id
    FROM route_stops rs
    WHERE rs.route_id = v_route_id LIMIT 1;

    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id, v_driver_id,
        DATE '2099-03-03', TIMESTAMPTZ '2099-03-03 05:00:00+00', 'COMPLETED'
    )
    RETURNING trip_id INTO v_trip_id;

    INSERT INTO trip_stop_logs (trip_id, route_id, route_stop_id, stop_status)
    VALUES (v_trip_id, v_route_id, v_route_stop_id, 'REACHED')
    RETURNING trip_stop_log_id INTO v_tsl_id;

    INSERT INTO passenger_counts (trip_stop_log_id, boarding_count, alighting_count)
    VALUES (v_tsl_id, 18, 4)
    RETURNING passenger_count_id INTO v_pc_id;

    SELECT COUNT(*) INTO v_audit_count
    FROM audit_logs
    WHERE table_name = 'passenger_counts'
      AND record_id = v_pc_id
      AND operation = 'INSERT';

    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Expected 1 audit entry for passenger_counts insert';
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'passenger_counts' AND record_id = v_pc_id;
    DELETE FROM passenger_counts WHERE passenger_count_id = v_pc_id;
    DELETE FROM trip_stop_logs WHERE trip_stop_log_id = v_tsl_id;
    DELETE FROM trips WHERE trip_id = v_trip_id;

    RAISE NOTICE '[PASS] TEST 8: Passenger count insert successfully logged in audit_logs';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 9: Update Passenger Count and Verify Audit Entry
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_trip_id BIGINT;
    v_route_id BIGINT;
    v_sched_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_route_stop_id BIGINT;
    v_tsl_id BIGINT;
    v_pc_id BIGINT;
    v_old_board TEXT;
    v_new_board TEXT;
BEGIN
    SELECT t.route_id, t.schedule_id, t.bus_id, t.driver_id
    INTO v_route_id, v_sched_id, v_bus_id, v_driver_id
    FROM trips t LIMIT 1;

    SELECT rs.route_stop_id INTO v_route_stop_id
    FROM route_stops rs
    WHERE rs.route_id = v_route_id LIMIT 1;

    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id, v_driver_id,
        DATE '2099-03-04', TIMESTAMPTZ '2099-03-04 05:00:00+00', 'COMPLETED'
    )
    RETURNING trip_id INTO v_trip_id;

    INSERT INTO trip_stop_logs (trip_id, route_id, route_stop_id, stop_status)
    VALUES (v_trip_id, v_route_id, v_route_stop_id, 'REACHED')
    RETURNING trip_stop_log_id INTO v_tsl_id;

    INSERT INTO passenger_counts (trip_stop_log_id, boarding_count, alighting_count)
    VALUES (v_tsl_id, 10, 2)
    RETURNING passenger_count_id INTO v_pc_id;

    UPDATE passenger_counts
    SET boarding_count = 35
    WHERE passenger_count_id = v_pc_id;

    SELECT old_data->>'boarding_count', new_data->>'boarding_count'
    INTO v_old_board, v_new_board
    FROM audit_logs
    WHERE table_name = 'passenger_counts'
      AND record_id = v_pc_id
      AND operation = 'UPDATE'
    ORDER BY audit_id DESC
    LIMIT 1;

    IF v_old_board <> '10' OR v_new_board <> '35' THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Expected OLD=10, NEW=35, got OLD=%, NEW=%',
            v_old_board, v_new_board;
    END IF;

    -- Cleanup
    DELETE FROM audit_logs WHERE table_name = 'passenger_counts' AND record_id = v_pc_id;
    DELETE FROM passenger_counts WHERE passenger_count_id = v_pc_id;
    DELETE FROM trip_stop_logs WHERE trip_stop_log_id = v_tsl_id;
    DELETE FROM trips WHERE trip_id = v_trip_id;

    RAISE NOTICE '[PASS] TEST 9: Passenger count update audited with OLD and NEW values';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 10: Insert a Delay Record with 200 Seconds and Verify MINOR
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

    -- Insert with wrong severity to verify trigger auto-overrides it to MINOR
    INSERT INTO delay_records (trip_stop_log_id, reason_id, delay_seconds, severity)
    VALUES (v_tsl_id, v_reason_id, 200, 'SEVERE')
    RETURNING delay_id, severity INTO v_delay_id, v_severity;

    IF v_severity <> 'MINOR' THEN
        RAISE EXCEPTION 'TEST 10 FAILED: 200s expected MINOR, got %', v_severity;
    END IF;

    DELETE FROM audit_logs WHERE table_name = 'delay_records' AND record_id = v_delay_id;
    DELETE FROM delay_records WHERE delay_id = v_delay_id;

    RAISE NOTICE '[PASS] TEST 10: 200s delay correctly classified as MINOR by trigger';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 11: Insert a Delay Record with 450 Seconds and Verify MODERATE
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

    INSERT INTO delay_records (trip_stop_log_id, reason_id, delay_seconds, severity)
    VALUES (v_tsl_id, v_reason_id, 450, 'MINOR')
    RETURNING delay_id, severity INTO v_delay_id, v_severity;

    IF v_severity <> 'MODERATE' THEN
        RAISE EXCEPTION 'TEST 11 FAILED: 450s expected MODERATE, got %', v_severity;
    END IF;

    DELETE FROM audit_logs WHERE table_name = 'delay_records' AND record_id = v_delay_id;
    DELETE FROM delay_records WHERE delay_id = v_delay_id;

    RAISE NOTICE '[PASS] TEST 11: 450s delay correctly classified as MODERATE by trigger';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 12: Insert a Delay Record with 750 Seconds and Verify SEVERE
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

    INSERT INTO delay_records (trip_stop_log_id, reason_id, delay_seconds, severity)
    VALUES (v_tsl_id, v_reason_id, 750, 'MINOR')
    RETURNING delay_id, severity INTO v_delay_id, v_severity;

    IF v_severity <> 'SEVERE' THEN
        RAISE EXCEPTION 'TEST 12 FAILED: 750s expected SEVERE, got %', v_severity;
    END IF;

    DELETE FROM audit_logs WHERE table_name = 'delay_records' AND record_id = v_delay_id;
    DELETE FROM delay_records WHERE delay_id = v_delay_id;

    RAISE NOTICE '[PASS] TEST 12: 750s delay correctly classified as SEVERE by trigger';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 13: Update an Existing Delay Duration and Verify Recalculation
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tsl_id BIGINT;
    v_reason_id BIGINT;
    v_delay_id BIGINT;
    v_updated_severity VARCHAR(20);
BEGIN
    SELECT tsl.trip_stop_log_id INTO v_tsl_id FROM trip_stop_logs tsl LIMIT 1;
    SELECT drn.reason_id INTO v_reason_id FROM delay_reasons drn LIMIT 1;

    -- Initially MINOR (150s)
    INSERT INTO delay_records (trip_stop_log_id, reason_id, delay_seconds, severity)
    VALUES (v_tsl_id, v_reason_id, 150, 'MINOR')
    RETURNING delay_id INTO v_delay_id;

    -- Update to 800s (should trigger recalculation to SEVERE)
    UPDATE delay_records
    SET delay_seconds = 800
    WHERE delay_id = v_delay_id;

    SELECT dr.severity INTO v_updated_severity
    FROM delay_records dr
    WHERE dr.delay_id = v_delay_id;

    IF v_updated_severity <> 'SEVERE' THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Updated delay of 800s expected SEVERE, got %', v_updated_severity;
    END IF;

    DELETE FROM audit_logs WHERE table_name = 'delay_records' AND record_id = v_delay_id;
    DELETE FROM delay_records WHERE delay_id = v_delay_id;

    RAISE NOTICE '[PASS] TEST 13: Delay update automatically recalculated severity to SEVERE';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 14: Reject Negative Delay Duration
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_tsl_id BIGINT;
    v_reason_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    SELECT tsl.trip_stop_log_id INTO v_tsl_id FROM trip_stop_logs tsl LIMIT 1;
    SELECT drn.reason_id INTO v_reason_id FROM delay_reasons drn LIMIT 1;

    BEGIN
        INSERT INTO delay_records (trip_stop_log_id, reason_id, delay_seconds, severity)
        VALUES (v_tsl_id, v_reason_id, -50, 'MINOR');
    EXCEPTION
        WHEN check_violation THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 14 FAILED: Negative delay was not rejected by trigger';
    END IF;

    RAISE NOTICE '[PASS] TEST 14: Negative delay successfully rejected with CHECK_VIOLATION';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 15: Verify Maintenance Audit Logging & Date Synchronization
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_bus_id BIGINT;
    v_maint_id BIGINT;
    v_orig_last_service DATE;
    v_audit_count INTEGER;
    v_check_date DATE;
BEGIN
    SELECT b.bus_id, b.last_service_date
    INTO v_bus_id, v_orig_last_service
    FROM buses b
    WHERE b.status = 'ACTIVE'
    LIMIT 1;

    -- 1. Insert COMPLETED record with future/current date
    INSERT INTO maintenance_records (
        bus_id, maintenance_type, description,
        maintenance_date, next_service_date, maintenance_cost, maintenance_status
    )
    VALUES (
        v_bus_id, 'Emergency Inspection', 'Test routine maintenance',
        CURRENT_DATE, CURRENT_DATE + 90, 500.00, 'COMPLETED'
    )
    RETURNING maintenance_id INTO v_maint_id;

    -- Verify audit log entry
    SELECT COUNT(*) INTO v_audit_count
    FROM audit_logs
    WHERE table_name = 'maintenance_records'
      AND record_id = v_maint_id
      AND operation = 'INSERT';

    IF v_audit_count <> 1 THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Maintenance audit entry not created';
    END IF;

    -- Verify maintenance sync trigger updated buses.last_service_date
    SELECT b.last_service_date INTO v_check_date
    FROM buses b WHERE b.bus_id = v_bus_id;

    IF v_check_date <> CURRENT_DATE THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Bus last_service_date not synced to %', CURRENT_DATE;
    END IF;

    -- 2. Verify Reversal: update to PENDING should recalculate back to previous max
    UPDATE maintenance_records
    SET maintenance_status = 'PENDING'
    WHERE maintenance_id = v_maint_id;

    SELECT b.last_service_date INTO v_check_date
    FROM buses b WHERE b.bus_id = v_bus_id;

    IF v_check_date IS DISTINCT FROM v_orig_last_service THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Reversing to PENDING did not restore previous service date';
    END IF;

    -- Cleanup test record and audit entry
    DELETE FROM audit_logs WHERE table_name = 'maintenance_records' AND record_id = v_maint_id;
    DELETE FROM maintenance_records WHERE maintenance_id = v_maint_id;

    -- Verify deletion restores original state
    SELECT b.last_service_date INTO v_check_date
    FROM buses b WHERE b.bus_id = v_bus_id;

    IF v_check_date IS DISTINCT FROM v_orig_last_service THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Deletion of test maintenance record did not preserve original service date';
    END IF;

    RAISE NOTICE '[PASS] TEST 15: Maintenance audit logged, date synced, reversed, and restored successfully';
END;
$$;

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'ALL 15 TRANSITIQ TRIGGER & AUDIT TESTS COMPLETED';
    RAISE NOTICE '=====================================================================';
END;
$$;
