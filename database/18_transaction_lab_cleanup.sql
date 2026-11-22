-- ============================================================================
-- TRANSITIQLAB: Transaction and Concurrency Cleanup
-- File: database/18_transaction_lab_cleanup.sql
-- Description: Safely tears down all experimental lab objects and fixtures
--              created for transaction management, ACID, and concurrency testing.
--
-- IMPORTANT SAFETY GUARANTEE:
--   This script strictly targets ONLY lab-prefixed tables:
--     - transaction_lab_logs
--     - transaction_lab_resources
--   It NEVER drops, alters, truncates, or modifies any of the 17 core
--   production TransitIQ tables, indexes, triggers, or views.
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: INITIATING EXPERIMENTAL TEARDOWN';
    RAISE NOTICE '=====================================================';
END;
$$;

-- Drop foreign key dependents first
DROP TABLE IF EXISTS transaction_lab_logs CASCADE;
DROP TABLE IF EXISTS transaction_lab_resources CASCADE;

DO $$
DECLARE
    v_core_table_count INTEGER;
BEGIN
    -- Verify that all 17 core production tables remain completely intact
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

    RAISE NOTICE '-----------------------------------------------------';
    RAISE NOTICE '[SUCCESS] Teardown complete.';
    RAISE NOTICE '  - transaction_lab_logs: DROPPED';
    RAISE NOTICE '  - transaction_lab_resources: DROPPED';
    RAISE NOTICE '-----------------------------------------------------';
    RAISE NOTICE '  - Core production tables verified intact: % / 17', v_core_table_count;
    RAISE NOTICE '=====================================================';

    IF v_core_table_count < 17 THEN
        RAISE WARNING 'CRITICAL WARNING: Expected 17 core tables, found only %', v_core_table_count;
    END IF;
END;
$$;
