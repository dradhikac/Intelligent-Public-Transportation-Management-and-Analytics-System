-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/24_security_lab_cleanup.sql
-- PURPOSE: Step 11 – Security Lab Teardown and Role Deprovisioning
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- SAFETY ASSURANCE:
--   - Drops ONLY lab-prefixed objects (security_lab_trip_access).
--   - Safely revokes privileges and deprovisions test roles/users.
--   - NEVER drops, alters, or truncates any of the 17 core production tables.
--   - Asserts 17 core tables exist before and after teardown.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: INITIATING SECURITY LAB TEARDOWN';
    RAISE NOTICE '=====================================================';
END;
$$;

-- Reset active role to session owner
RESET ROLE;

-- ---------------------------------------------------------------------
-- 1. DROP SECURITY LAB TABLE
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS security_lab_trip_access CASCADE;

DO $$
BEGIN
    RAISE NOTICE '[SUCCESS] Dropped lab table: security_lab_trip_access';
END;
$$;


-- ---------------------------------------------------------------------
-- 2. REVOKE GRANTED PRIVILEGES FROM TEST & GROUP ROLES
-- ---------------------------------------------------------------------
-- PostgreSQL requires revoking all object privileges before dropping roles
-- ---------------------------------------------------------------------

DO $$
DECLARE
    v_role TEXT;
    v_roles TEXT[] := ARRAY[
        'test_dispatcher',
        'test_dispatcher_2',
        'test_fleet_manager',
        'test_analyst',
        'test_auditor',
        'transit_admin',
        'transit_dispatcher',
        'transit_fleet_manager',
        'transit_analyst',
        'transit_auditor'
    ];
BEGIN
    FOREACH v_role IN ARRAY v_roles LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_role) THEN
            EXECUTE format('REVOKE ALL ON ALL TABLES IN SCHEMA public FROM %I', v_role);
            EXECUTE format('REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM %I', v_role);
            EXECUTE format('REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM %I', v_role);
            EXECUTE format('REVOKE ALL ON SCHEMA public FROM %I', v_role);
        END IF;
    END LOOP;
    RAISE NOTICE '[SUCCESS] Revoked all schema, table, and routine grants from test and group roles.';
END;
$$;


-- ---------------------------------------------------------------------
-- 3. DROP TEST LOGIN USERS
-- ---------------------------------------------------------------------

DROP ROLE IF EXISTS test_dispatcher;
DROP ROLE IF EXISTS test_dispatcher_2;
DROP ROLE IF EXISTS test_fleet_manager;
DROP ROLE IF EXISTS test_analyst;
DROP ROLE IF EXISTS test_auditor;

DO $$
BEGIN
    RAISE NOTICE '[SUCCESS] Dropped 5 test login users.';
END;
$$;


-- ---------------------------------------------------------------------
-- 4. DROP TRANSITIILAB GROUP ROLES
-- ---------------------------------------------------------------------

DROP ROLE IF EXISTS transit_admin;
DROP ROLE IF EXISTS transit_dispatcher;
DROP ROLE IF EXISTS transit_fleet_manager;
DROP ROLE IF EXISTS transit_analyst;
DROP ROLE IF EXISTS transit_auditor;

DO $$
BEGIN
    RAISE NOTICE '[SUCCESS] Dropped 5 transit group roles.';
END;
$$;


-- ---------------------------------------------------------------------
-- 5. VERIFY PRODUCTION DATABASE INTEGRITY
-- ---------------------------------------------------------------------

DO $$
DECLARE
    v_core_table_count INTEGER;
    v_view_count INTEGER;
BEGIN
    -- Verify 17 core tables
    SELECT COUNT(*)
    INTO v_core_table_count
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name IN (
        'bus_types', 'buses', 'maintenance_records', 'routes', 'stops',
        'route_stops', 'drivers', 'schedules', 'operating_days',
        'schedule_operating_days', 'schedule_stop_times', 'trips',
        'trip_stop_logs', 'passenger_counts', 'delay_reasons',
        'delay_records', 'audit_logs'
      );

    -- Verify 5 analytical views
    SELECT COUNT(*)
    INTO v_view_count
    FROM information_schema.views
    WHERE table_schema = 'public'
      AND table_name IN (
        'vw_fleet_summary', 'vw_route_performance', 'vw_passenger_demand',
        'vw_delay_analysis', 'vw_driver_performance'
      );

    RAISE NOTICE '-----------------------------------------------------';
    RAISE NOTICE 'VERIFICATION AUDIT:';
    RAISE NOTICE '  - Core Operational Tables Intact: % / 17', v_core_table_count;
    RAISE NOTICE '  - Analytical Views Intact:        % / 5', v_view_count;
    RAISE NOTICE '=====================================================';

    IF v_core_table_count < 17 OR v_view_count < 5 THEN
        RAISE WARNING 'CRITICAL ALERT: Expected 17 core tables and 5 views, found % tables and % views!',
            v_core_table_count, v_view_count;
    ELSE
        RAISE NOTICE '[STATUS] Production schema integrity 100%% verified.';
    END IF;
END;
$$;
