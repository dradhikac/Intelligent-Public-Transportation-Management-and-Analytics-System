-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/22_security_tests.sql
-- PURPOSE: Step 11 – Automated Security & RBAC Test Suite (15 Test Cases)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- EXECUTION NOTICE:
--   This test suite runs inside anonymous PL/pgSQL blocks using exception
--   trapping. Expected security errors (INSUFFICIENT_PRIVILEGE 42501 and
--   RLS CHECK_VIOLATION 23514) are intercepted and verified, allowing the
--   entire harness to execute cleanly to completion without aborting.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: STARTING AUTOMATED SECURITY & RBAC TESTS';
    RAISE NOTICE '=====================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- TEST 1: Role Creation Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_missing_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_missing_count
    FROM (
        VALUES
            ('transit_admin'),
            ('transit_dispatcher'),
            ('transit_fleet_manager'),
            ('transit_analyst'),
            ('transit_auditor'),
            ('test_dispatcher'),
            ('test_dispatcher_2'),
            ('test_fleet_manager'),
            ('test_analyst'),
            ('test_auditor')
    ) AS expected(role_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = expected.role_name
    );

    IF v_missing_count = 0 THEN
        RAISE NOTICE '[PASS] TEST 1: All 5 group roles and 5 test users verified in pg_roles';
    ELSE
        RAISE EXCEPTION 'TEST 1 FAILED: % roles are missing from pg_roles', v_missing_count;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 2: Role Membership Inheritance Verification
-- ---------------------------------------------------------------------
DO $$
BEGIN
    IF pg_has_role('test_dispatcher', 'transit_dispatcher', 'MEMBER') AND
       pg_has_role('test_dispatcher_2', 'transit_dispatcher', 'MEMBER') AND
       pg_has_role('test_fleet_manager', 'transit_fleet_manager', 'MEMBER') AND
       pg_has_role('test_analyst', 'transit_analyst', 'MEMBER') AND
       pg_has_role('test_auditor', 'transit_auditor', 'MEMBER') THEN
        RAISE NOTICE '[PASS] TEST 2: Role membership and inheritance mappings verified successfully';
    ELSE
        RAISE EXCEPTION 'TEST 2 FAILED: Role membership validation failed';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 3: Dispatcher Authorized SELECT (Routes & Trips)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_routes_count BIGINT;
    v_trips_count BIGINT;
BEGIN
    SET ROLE test_dispatcher;
    SELECT COUNT(*) INTO v_routes_count FROM routes;
    SELECT COUNT(*) INTO v_trips_count FROM trips;
    RESET ROLE;

    RAISE NOTICE '[PASS] TEST 3: Dispatcher successfully queried routes (%) and trips (%)', v_routes_count, v_trips_count;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'TEST 3 FAILED: Dispatcher failed authorized SELECT: %', SQLERRM;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 4: Dispatcher Unauthorized Table Access Rejection (maintenance_records)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_count BIGINT;
BEGIN
    SET ROLE test_dispatcher;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM maintenance_records;
        RESET ROLE;
        RAISE EXCEPTION 'TEST 4 FAILED: Dispatcher was permitted to read maintenance_records!';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE '[PASS] TEST 4: Dispatcher SELECT on maintenance_records correctly rejected (42501)';
    END;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 5: Dispatcher Audit Modification Rejection (audit_logs UPDATE)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    SET ROLE test_dispatcher;
    BEGIN
        UPDATE audit_logs SET table_name = 'HACKED' WHERE audit_id = 1;
        RESET ROLE;
        RAISE EXCEPTION 'TEST 5 FAILED: Dispatcher was permitted to UPDATE audit_logs!';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE '[PASS] TEST 5: Dispatcher UPDATE on audit_logs correctly rejected (42501)';
    END;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 6: Fleet Manager Authorized Maintenance Access
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_maint_count BIGINT;
    v_bus_count BIGINT;
BEGIN
    SET ROLE test_fleet_manager;
    SELECT COUNT(*) INTO v_maint_count FROM maintenance_records;
    SELECT COUNT(*) INTO v_bus_count FROM buses;
    RESET ROLE;

    RAISE NOTICE '[PASS] TEST 6: Fleet Manager queried maintenance_records (%) and buses (%)', v_maint_count, v_bus_count;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'TEST 6 FAILED: Fleet manager failed authorized access: %', SQLERRM;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 7: Fleet Manager Unauthorized Passenger Counts Rejection
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_count BIGINT;
BEGIN
    SET ROLE test_fleet_manager;
    BEGIN
        SELECT COUNT(*) INTO v_count FROM passenger_counts;
        RESET ROLE;
        RAISE EXCEPTION 'TEST 7 FAILED: Fleet manager was permitted to read passenger_counts!';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE '[PASS] TEST 7: Fleet Manager SELECT on passenger_counts correctly rejected (42501)';
    END;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 8: Analyst Authorized Analytical View Access
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_fleet_rows BIGINT;
    v_route_rows BIGINT;
BEGIN
    SET ROLE test_analyst;
    SELECT COUNT(*) INTO v_fleet_rows FROM vw_fleet_summary;
    SELECT COUNT(*) INTO v_route_rows FROM vw_route_performance;
    RESET ROLE;

    RAISE NOTICE '[PASS] TEST 8: Analyst successfully queried vw_fleet_summary (%) and vw_route_performance (%)', v_fleet_rows, v_route_rows;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'TEST 8 FAILED: Analyst failed authorized view access: %', SQLERRM;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 9: Analyst Operational Table Write Rejection (INSERT on routes)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    SET ROLE test_analyst;
    BEGIN
        INSERT INTO routes (route_number, route_name, start_location, end_location, total_distance_km, estimated_duration_minutes)
        VALUES ('RX-999', 'Unauthorized Test', 'A', 'B', 10.0, 30);
        RESET ROLE;
        RAISE EXCEPTION 'TEST 9 FAILED: Analyst was permitted to INSERT into routes!';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE '[PASS] TEST 9: Analyst INSERT on routes correctly rejected (42501)';
    END;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 10: Auditor Audit Log Read Permission
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_audit_count BIGINT;
BEGIN
    SET ROLE test_auditor;
    SELECT COUNT(*) INTO v_audit_count FROM audit_logs;
    RESET ROLE;

    RAISE NOTICE '[PASS] TEST 10: Auditor successfully queried audit_logs (% records)', v_audit_count;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE EXCEPTION 'TEST 10 FAILED: Auditor failed authorized audit_logs read: %', SQLERRM;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 11: Auditor Audit Log Tampering Rejection (DELETE)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    SET ROLE test_auditor;
    BEGIN
        DELETE FROM audit_logs WHERE audit_id = 1;
        RESET ROLE;
        RAISE EXCEPTION 'TEST 11 FAILED: Auditor was permitted to DELETE from audit_logs!';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE '[PASS] TEST 11: Auditor DELETE on audit_logs correctly rejected (42501)';
    END;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 12: Public Role Lockdown Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_unsecured_grants INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_unsecured_grants
    FROM information_schema.role_table_grants
    WHERE grantee = 'PUBLIC'
      AND table_schema = 'public'
      AND privilege_type IN ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');

    IF v_unsecured_grants = 0 THEN
        RAISE NOTICE '[PASS] TEST 12: PUBLIC role lockdown verified (0 unauthorized DML table grants)';
    ELSE
        RAISE EXCEPTION 'TEST 12 FAILED: PUBLIC has % unauthorized write grants', v_unsecured_grants;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 13: Stored Procedure Execution Rights
-- ---------------------------------------------------------------------
DO $$
BEGIN
    -- Analyst should NOT have EXECUTE on sp_create_trip
    SET ROLE test_analyst;
    BEGIN
        CALL sp_create_trip(1, 1, 1, 1, CURRENT_DATE, CURRENT_TIMESTAMP, NULL);
        RESET ROLE;
        RAISE EXCEPTION 'TEST 13 FAILED: Analyst was permitted to execute sp_create_trip!';
    EXCEPTION WHEN insufficient_privilege THEN
        RESET ROLE;
        RAISE NOTICE '[PASS] TEST 13: Analyst execution of sp_create_trip correctly rejected (42501)';
    END;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 14: Row-Level Security Row Isolation
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_visible_d1 BIGINT;
    v_visible_d2 BIGINT;
BEGIN
    -- Session as test_dispatcher
    SET ROLE test_dispatcher;
    SELECT COUNT(*) INTO v_visible_d1 FROM security_lab_trip_access;

    -- Session as test_dispatcher_2
    SET ROLE test_dispatcher_2;
    SELECT COUNT(*) INTO v_visible_d2 FROM security_lab_trip_access;

    RESET ROLE;

    -- Both dispatchers should see exactly 2 rows (their own rows)
    IF v_visible_d1 = 2 AND v_visible_d2 = 2 THEN
        RAISE NOTICE '[PASS] TEST 14: RLS tenant isolation verified (Dispatcher 1 saw % rows, Dispatcher 2 saw % rows)',
            v_visible_d1, v_visible_d2;
    ELSE
        RAISE EXCEPTION 'TEST 14 FAILED: RLS visibility mismatch (D1=%, D2=%, expected 2 each)',
            v_visible_d1, v_visible_d2;
    END IF;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE;
END;
$$;


-- ---------------------------------------------------------------------
-- TEST 15: Row-Level Security Spoofing Prevention (WITH CHECK)
-- ---------------------------------------------------------------------
DO $$
BEGIN
    SET ROLE test_dispatcher;
    BEGIN
        -- Attempt to insert a record spoofing test_dispatcher_2
        INSERT INTO security_lab_trip_access (dispatcher_username, trip_reference, access_description)
        VALUES ('test_dispatcher_2', 'SPOOF-TRIP-999', 'Malicious Dispatch Injection');

        RESET ROLE;
        RAISE EXCEPTION 'TEST 15 FAILED: Dispatcher was permitted to insert spoofed identity record!';
    EXCEPTION
        WHEN check_violation OR insufficient_privilege THEN
            RESET ROLE;
            RAISE NOTICE '[PASS] TEST 15: RLS WITH CHECK policy blocked identity spoofing injection';
    END;
EXCEPTION WHEN OTHERS THEN
    RESET ROLE;
    RAISE;
END;
$$;

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'ALL 15 SECURITY & RBAC TESTS PASSED SUCCESSFULLY!';
    RAISE NOTICE '=====================================================';
END;
$$;
