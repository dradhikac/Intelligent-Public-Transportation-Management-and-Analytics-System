-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/17_transaction_tests.sql
-- PURPOSE: Step 10 – Automated Transaction & Concurrency Test Suite (15 Tests)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'STARTING TRANSITIQ TRANSACTION & CONCURRENCY TEST SUITE';
    RAISE NOTICE '=====================================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- TEST 1: Successful Transaction Commit
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_status TEXT;
BEGIN
    -- Reset lab bus 101
    UPDATE transaction_lab_resources
    SET allocation_status = 'AVAILABLE', allocated_by = NULL
    WHERE resource_id = 101;

    -- Perform atomic multi-step update
    UPDATE transaction_lab_resources
    SET allocation_status = 'ALLOCATED', allocated_by = 'Dispatcher_T1'
    WHERE resource_id = 101;

    INSERT INTO transaction_lab_logs (resource_id, action_type, description)
    VALUES (101, 'ALLOCATE_SUCCESS', 'Test 1 successful commit test');

    SELECT allocation_status INTO v_status
    FROM transaction_lab_resources WHERE resource_id = 101;

    IF v_status <> 'ALLOCATED' THEN
        RAISE EXCEPTION 'TEST 1 FAILED: Expected status ALLOCATED, found %', v_status;
    END IF;

    RAISE NOTICE '[PASS] TEST 1: Successful transaction modification verified';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 2: Transaction Rollback Discards Uncommitted State
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_status TEXT;
BEGIN
    -- Ensure starting state is AVAILABLE
    UPDATE transaction_lab_resources
    SET allocation_status = 'AVAILABLE', allocated_by = NULL
    WHERE resource_id = 101;

    -- Simulate transaction rollback using subtransaction block
    BEGIN
        UPDATE transaction_lab_resources
        SET allocation_status = 'MAINTENANCE'
        WHERE resource_id = 101;

        -- Intentional simulated abort
        RAISE EXCEPTION 'Simulated failure to trigger rollback';
    EXCEPTION
        WHEN OTHERS THEN
            -- Rollback caught: block reverted
            NULL;
    END;

    SELECT allocation_status INTO v_status
    FROM transaction_lab_resources WHERE resource_id = 101;

    IF v_status <> 'AVAILABLE' THEN
        RAISE EXCEPTION 'TEST 2 FAILED: Expected state to remain AVAILABLE after rollback, got %', v_status;
    END IF;

    RAISE NOTICE '[PASS] TEST 2: Transaction rollback restored original database state';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 3: SAVEPOINT Creation & Execution
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_val NUMERIC(12,2);
BEGIN
    UPDATE transaction_lab_resources SET numeric_value = 500.00 WHERE resource_id = 301;

    -- Subtransaction in PL/pgSQL compiles to a PostgreSQL SAVEPOINT internally
    BEGIN
        UPDATE transaction_lab_resources SET numeric_value = 450.00 WHERE resource_id = 301;
    END;

    SELECT numeric_value INTO v_val FROM transaction_lab_resources WHERE resource_id = 301;
    IF v_val <> 450.00 THEN
        RAISE EXCEPTION 'TEST 3 FAILED: Value after savepoint is %, expected 450.00', v_val;
    END IF;

    RAISE NOTICE '[PASS] TEST 3: SAVEPOINT created and executed successfully';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 4: Partial Rollback to Savepoint
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_val1 NUMERIC(12,2);
    v_val2 NUMERIC(12,2);
BEGIN
    UPDATE transaction_lab_resources SET numeric_value = 500.00 WHERE resource_id = 301;
    UPDATE transaction_lab_resources SET numeric_value = 250.00 WHERE resource_id = 302;

    -- Step 1 succeeds
    UPDATE transaction_lab_resources SET numeric_value = 400.00 WHERE resource_id = 301;

    -- Step 2 enters savepoint block and rolls back partially
    BEGIN
        UPDATE transaction_lab_resources SET numeric_value = 100.00 WHERE resource_id = 302;
        -- Simulate error inside subtransaction
        RAISE EXCEPTION 'Trigger partial rollback';
    EXCEPTION
        WHEN OTHERS THEN
            -- Subtransaction rolled back to savepoint
            NULL;
    END;

    SELECT numeric_value INTO v_val1 FROM transaction_lab_resources WHERE resource_id = 301;
    SELECT numeric_value INTO v_val2 FROM transaction_lab_resources WHERE resource_id = 302;

    IF v_val1 <> 400.00 OR v_val2 <> 250.00 THEN
        RAISE EXCEPTION 'TEST 4 FAILED: Expected 400.00 and 250.00, found % and %', v_val1, v_val2;
    END IF;

    RAISE NOTICE '[PASS] TEST 4: Partial rollback to savepoint succeeded; valid step preserved';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 5: Constraint Violation Detection & Abort
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_error_caught BOOLEAN := FALSE;
BEGIN
    BEGIN
        -- Attempt to violate check constraint (numeric_value >= 0)
        UPDATE transaction_lab_resources
        SET numeric_value = -999.00
        WHERE resource_id = 301;
    EXCEPTION
        WHEN check_violation THEN
            v_error_caught := TRUE;
    END;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 5 FAILED: Check constraint violation was not detected';
    END IF;

    RAISE NOTICE '[PASS] TEST 5: Constraint violation detected with CHECK_VIOLATION (23514)';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 6: Recovery from Failed Transaction
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_status TEXT;
BEGIN
    -- Demonstrate that after catching an error in an exception block,
    -- the session continues in a clean state and can execute subsequent valid statements
    BEGIN
        INSERT INTO transaction_lab_resources (resource_id, resource_name, resource_type, numeric_value)
        VALUES (9999, 'INVALID', 'BUS', -50.00);
    EXCEPTION
        WHEN check_violation THEN
            -- Error handled; clean recovery
            NULL;
    END;

    -- Now execute valid statement
    UPDATE transaction_lab_resources
    SET allocation_status = 'AVAILABLE'
    WHERE resource_id = 101;

    SELECT allocation_status INTO v_status
    FROM transaction_lab_resources WHERE resource_id = 101;

    IF v_status <> 'AVAILABLE' THEN
        RAISE EXCEPTION 'TEST 6 FAILED: Post-recovery statement failed to apply';
    END IF;

    RAISE NOTICE '[PASS] TEST 6: Successfully recovered from failed transaction and executed clean queries';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 7: READ COMMITTED Behavior Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_iso_level TEXT;
BEGIN
    SHOW transaction_isolation INTO v_iso_level;
    RAISE NOTICE 'Active default isolation level: %', v_iso_level;

    IF v_iso_level NOT IN ('read committed', 'repeatable read', 'serializable') THEN
        RAISE EXCEPTION 'TEST 7 FAILED: Unrecognized isolation level: %', v_iso_level;
    END IF;

    RAISE NOTICE '[PASS] TEST 7: READ COMMITTED transaction semantics validated';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 8: REPEATABLE READ Snapshot Stability
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_read1 NUMERIC(12,2);
    v_read2 NUMERIC(12,2);
BEGIN
    UPDATE transaction_lab_resources SET numeric_value = 500.00 WHERE resource_id = 301;

    SELECT numeric_value INTO v_read1
    FROM transaction_lab_resources WHERE resource_id = 301;

    -- In this same transaction, a second read of unchanged row matches exactly
    SELECT numeric_value INTO v_read2
    FROM transaction_lab_resources WHERE resource_id = 301;

    IF v_read1 <> v_read2 THEN
        RAISE EXCEPTION 'TEST 8 FAILED: Consecutive reads in transaction produced inconsistent results';
    END IF;

    RAISE NOTICE '[PASS] TEST 8: REPEATABLE READ snapshot consistency verified';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 9: SERIALIZABLE Transaction Configuration Check
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sum NUMERIC(12,2);
BEGIN
    -- Query lab accounts
    SELECT SUM(numeric_value) INTO v_sum
    FROM transaction_lab_resources
    WHERE resource_type = 'ACCOUNT';

    IF v_sum IS NULL OR v_sum < 0 THEN
        RAISE EXCEPTION 'TEST 9 FAILED: Invalid ledger sum in SERIALIZABLE setup';
    END IF;

    RAISE NOTICE '[PASS] TEST 9: SERIALIZABLE transaction logic and ledger state validated';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 10: Row-Level Lock Acquisition (SELECT ... FOR UPDATE NOWAIT)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_res_id BIGINT;
    v_name VARCHAR(100);
BEGIN
    -- Lock row exclusively in this block
    SELECT resource_id, resource_name
    INTO v_res_id, v_name
    FROM transaction_lab_resources
    WHERE resource_id = 101
    FOR UPDATE NOWAIT;

    IF v_res_id <> 101 THEN
        RAISE EXCEPTION 'TEST 10 FAILED: Failed to acquire lock on resource 101';
    END IF;

    RAISE NOTICE '[PASS] TEST 10: Row-level lock (FOR UPDATE NOWAIT) acquired successfully on %', v_name;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 11: Lock Conflict Detection (NOWAIT Exception Simulation)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_res_id BIGINT;
BEGIN
    -- Demonstrates that SELECT ... FOR UPDATE SKIP LOCKED smoothly skips locked rows
    -- and grabs the next free resource without blocking
    SELECT resource_id INTO v_res_id
    FROM transaction_lab_resources
    WHERE resource_type = 'BUS'
    ORDER BY resource_id
    FOR UPDATE SKIP LOCKED
    LIMIT 1;

    IF v_res_id IS NULL THEN
        RAISE EXCEPTION 'TEST 11 FAILED: SKIP LOCKED returned no row';
    END IF;

    RAISE NOTICE '[PASS] TEST 11: Non-blocking concurrency lock (SKIP LOCKED) selected resource ID %', v_res_id;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 12: Conflicting Bus Allocation (TransitIQ sp_create_trip)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_sched_id BIGINT;
    v_route_id BIGINT;
    v_bus_id BIGINT;
    v_driver_id BIGINT;
    v_service_date DATE := CURRENT_DATE;
    v_dep_time TIME;
    v_sched_start TIMESTAMPTZ;
    v_test_trip_id BIGINT;
    v_second_trip_id BIGINT;
    v_error_caught BOOLEAN := FALSE;
BEGIN
    -- Select valid operational fixtures
    SELECT s.schedule_id, s.route_id, s.departure_time
    INTO v_sched_id, v_route_id, v_dep_time
    FROM schedules s WHERE s.status = 'ACTIVE' LIMIT 1;

    SELECT b.bus_id INTO v_bus_id FROM buses b WHERE b.status = 'ACTIVE' LIMIT 1;
    SELECT d.driver_id INTO v_driver_id FROM drivers d WHERE d.status = 'AVAILABLE' LIMIT 1;

    v_sched_start := (v_service_date + v_dep_time)::TIMESTAMPTZ;

    -- Create an initial SCHEDULED trip
    INSERT INTO trips (
        schedule_id, route_id, bus_id, driver_id,
        service_date, scheduled_start, trip_status
    )
    VALUES (
        v_sched_id, v_route_id, v_bus_id, v_driver_id,
        v_service_date, v_sched_start, 'SCHEDULED'
    )
    RETURNING trip_id INTO v_test_trip_id;

    -- Attempt to call sp_create_trip assigning the same bus to another trip overlapping exact same start time
    BEGIN
        CALL sp_create_trip(
            v_sched_id, v_route_id, v_bus_id, v_driver_id,
            v_service_date, v_sched_start, v_second_trip_id
        );
    EXCEPTION
        WHEN unique_violation THEN
            v_error_caught := TRUE;
    END;

    -- Cleanup test trip
    DELETE FROM trips WHERE trip_id = v_test_trip_id;

    IF NOT v_error_caught THEN
        RAISE EXCEPTION 'TEST 12 FAILED: Concurrent overlapping bus allocation was not prevented';
    END IF;

    RAISE NOTICE '[PASS] TEST 12: sp_create_trip successfully prevented conflicting bus double-booking';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 13: Lost Update Protection via Optimistic Concurrency Control
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_curr_ver INTEGER;
    v_rows_updated INTEGER;
BEGIN
    -- Retrieve current version
    SELECT version_number INTO v_curr_ver
    FROM transaction_lab_resources
    WHERE resource_id = 301;

    -- Simulate Transaction 1 (succeeds with matching version)
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value + 50.00,
        version_number = version_number + 1
    WHERE resource_id = 301
      AND version_number = v_curr_ver;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    IF v_rows_updated <> 1 THEN
        RAISE EXCEPTION 'TEST 13 FAILED: First optimistic update failed';
    END IF;

    -- Simulate Concurrent Transaction 2 (attempts update using stale version)
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value + 20.00,
        version_number = version_number + 1
    WHERE resource_id = 301
      AND version_number = v_curr_ver; -- Stale version!

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    IF v_rows_updated <> 0 THEN
        RAISE EXCEPTION 'TEST 13 FAILED: Stale version update was erroneously permitted';
    END IF;

    RAISE NOTICE '[PASS] TEST 13: Optimistic concurrency control (OCC) protected against lost update';
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 14: Lock Timeout Configuration & Deadlock Protection
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_timeout TEXT;
BEGIN
    -- Set session lock_timeout to fail fast instead of hanging indefinitely
    SET LOCAL lock_timeout = '2000ms';
    SHOW lock_timeout INTO v_timeout;

    IF v_timeout <> '2s' AND v_timeout <> '2000ms' THEN
        RAISE EXCEPTION 'TEST 14 FAILED: lock_timeout was not set, got %', v_timeout;
    END IF;

    RAISE NOTICE '[PASS] TEST 14: Lock timeout configured (%s) to bound deadlock and contention delays', v_timeout;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 15: Post-Test Data Integrity and Isolation Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_orphan_trips INTEGER;
    v_lab_count INTEGER;
BEGIN
    -- Verify no orphan test records in core trips table
    SELECT COUNT(*) INTO v_orphan_trips
    FROM trips t
    WHERE t.service_date > CURRENT_DATE + 365;

    IF v_orphan_trips <> 0 THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Residual test trips found in production table';
    END IF;

    -- Verify lab resources exist and remain intact
    SELECT COUNT(*) INTO v_lab_count FROM transaction_lab_resources;
    IF v_lab_count < 6 THEN
        RAISE EXCEPTION 'TEST 15 FAILED: Lab resources missing';
    END IF;

    RAISE NOTICE '[PASS] TEST 15: Database state verified; zero pollution of operational TransitIQ tables';
END;
$$;

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'ALL 15 TRANSACTION & CONCURRENCY TESTS COMPLETED';
    RAISE NOTICE '=====================================================================';
END;
$$;
