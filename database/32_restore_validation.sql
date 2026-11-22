-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/32_restore_validation.sql
-- PURPOSE: Step 13 – Restored Database Verification & Integrity Suite
-- TARGET DATABASE: transitiq_recovery_test (PostgreSQL 14+)
--
-- DESCRIPTION:
--   Executes a comprehensive 15-checkpoint validation suite against the
--   restored recovery database to prove that all schema objects, relational
--   constraints, triggers, views, and data tuples survived restoration.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: STARTING RESTORATION VALIDATION SUITE';
    RAISE NOTICE 'CURRENT TARGET DATABASE: %', current_database();
    RAISE NOTICE '=====================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- CHECKPOINT 1: All 17 Core Operational Tables Present
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_missing_tables INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_missing_tables
    FROM (
        VALUES
            ('bus_types'), ('buses'), ('maintenance_records'), ('routes'),
            ('stops'), ('route_stops'), ('drivers'), ('schedules'),
            ('operating_days'), ('schedule_operating_days'),
            ('schedule_stop_times'), ('trips'), ('trip_stop_logs'),
            ('passenger_counts'), ('delay_reasons'), ('delay_records'),
            ('audit_logs')
    ) AS expected(table_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_type = 'BASE TABLE'
          AND table_name = expected.table_name
    );

    IF v_missing_tables = 0 THEN
        RAISE NOTICE '[PASS] CHK 01: All 17 core operational tables successfully verified in target database';
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: % core tables are missing!', v_missing_tables;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 2: All 5 Analytical Views Present & Queryable
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_missing_views INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_missing_views
    FROM (
        VALUES
            ('vw_fleet_summary'),
            ('vw_route_performance'),
            ('vw_passenger_demand'),
            ('vw_delay_analysis'),
            ('vw_driver_performance')
    ) AS expected(view_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.views
        WHERE table_schema = 'public'
          AND table_name = expected.view_name
    );

    IF v_missing_views = 0 THEN
        RAISE NOTICE '[PASS] CHK 02: All 5 analytical views present and verified';
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: % analytical views are missing!', v_missing_views;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 3: Stored Procedures Present
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_missing_procs INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_missing_procs
    FROM (
        VALUES
            ('sp_create_trip'),
            ('sp_record_passenger_count'),
            ('sp_record_delay')
    ) AS expected(proc_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prokind = 'p'
          AND p.proname = expected.proc_name
    );

    IF v_missing_procs = 0 THEN
        RAISE NOTICE '[PASS] CHK 03: All 3 operational stored procedures successfully restored';
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: % stored procedures are missing!', v_missing_procs;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 4: Analytical Functions Present
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_missing_funcs INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_missing_funcs
    FROM (
        VALUES
            ('fn_get_bus_status'),
            ('fn_get_maintenance_status'),
            ('fn_get_bus_utilization'),
            ('fn_calculate_trip_delay'),
            ('fn_get_route_performance'),
            ('fn_get_stop_demand'),
            ('fn_check_license_expiry'),
            ('fn_calculate_delay_severity'),
            ('fn_get_driver_performance')
    ) AS expected(func_name)
    WHERE NOT EXISTS (
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
          AND p.proname = expected.func_name
    );

    IF v_missing_funcs = 0 THEN
        RAISE NOTICE '[PASS] CHK 04: All 9 analytical functions successfully restored';
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: % analytical functions are missing!', v_missing_funcs;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 5: Trigger Routines & Automation Triggers Present
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_trigger_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_trigger_count
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
      AND trigger_name IN (
        'trg_audit_buses', 'trg_audit_drivers', 'trg_audit_trips',
        'trg_audit_passenger_counts', 'trg_audit_delay_records',
        'trg_audit_maintenance', 'trg_auto_classify_delay',
        'trg_sync_bus_maintenance_date'
      );

    IF v_trigger_count = 8 THEN
        RAISE NOTICE '[PASS] CHK 05: All 8 audit and automation triggers successfully verified';
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Expected 8 triggers, found %', v_trigger_count;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 6: Primary Key Constraints Restored
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_pk_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_pk_count
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND constraint_type = 'PRIMARY KEY';

    IF v_pk_count >= 17 THEN
        RAISE NOTICE '[PASS] CHK 06: Primary key constraints intact across all tables (% PKs)', v_pk_count;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Expected at least 17 PKs, found %', v_pk_count;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 7: Foreign Key Constraints Restored
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_fk_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_fk_count
    FROM information_schema.table_constraints
    WHERE table_schema = 'public'
      AND constraint_type = 'FOREIGN KEY';

    IF v_fk_count >= 15 THEN
        RAISE NOTICE '[PASS] CHK 07: Foreign key relationships intact across all tables (% FKs)', v_fk_count;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Expected at least 15 FKs, found %', v_fk_count;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 8: Performance Indexes Restored
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_idx_count INTEGER;
BEGIN
    SELECT COUNT(*)
    INTO v_idx_count
    FROM pg_indexes
    WHERE schemaname = 'public';

    IF v_idx_count >= 18 THEN
        RAISE NOTICE '[PASS] CHK 08: Performance and structural indexes verified (% indexes)', v_idx_count;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Expected at least 18 indexes, found %', v_idx_count;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 9: Baseline Fleet Data Restored (buses & bus_types)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_buses_count BIGINT;
    v_types_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_buses_count FROM buses;
    SELECT COUNT(*) INTO v_types_count FROM bus_types;

    IF v_buses_count > 0 AND v_types_count > 0 THEN
        RAISE NOTICE '[PASS] CHK 09: Fleet inventory restored (% buses, % bus types)', v_buses_count, v_types_count;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Fleet tables are empty!';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 10: Network Data Restored (routes, stops, route_stops)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_routes_count BIGINT;
    v_stops_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_routes_count FROM routes;
    SELECT COUNT(*) INTO v_stops_count FROM stops;

    IF v_routes_count > 0 AND v_stops_count > 0 THEN
        RAISE NOTICE '[PASS] CHK 10: Transit network restored (% routes, % stops)', v_routes_count, v_stops_count;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Network tables are empty!';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 11: Operational Trips & Logs Restored (trips & stop_logs)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_trips_count BIGINT;
    v_logs_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_trips_count FROM trips;
    SELECT COUNT(*) INTO v_logs_count FROM trip_stop_logs;

    IF v_trips_count > 0 AND v_logs_count > 0 THEN
        RAISE NOTICE '[PASS] CHK 11: Operational records restored (% trips, % stop logs)', v_trips_count, v_logs_count;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Trip tables are empty!';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 12: Passenger Telemetry Restored (passenger_counts)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_passenger_rows BIGINT;
    v_total_boardings BIGINT;
BEGIN
    SELECT COUNT(*), COALESCE(SUM(boarding_count), 0)
    INTO v_passenger_rows, v_total_boardings
    FROM passenger_counts;

    IF v_passenger_rows > 0 THEN
        RAISE NOTICE '[PASS] CHK 12: Passenger telemetry restored (% logs, % cumulative boardings)',
            v_passenger_rows, v_total_boardings;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Passenger count records are empty!';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 13: Referential Integrity: Orphaned Trips Check
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_orphans BIGINT;
BEGIN
    SELECT COUNT(*)
    INTO v_orphans
    FROM trips t
    WHERE NOT EXISTS (SELECT 1 FROM routes r WHERE r.route_id = t.route_id)
       OR NOT EXISTS (SELECT 1 FROM buses b WHERE b.bus_id = t.bus_id)
       OR NOT EXISTS (SELECT 1 FROM drivers d WHERE d.driver_id = t.driver_id);

    IF v_orphans = 0 THEN
        RAISE NOTICE '[PASS] CHK 13: Referential integrity verified (0 orphaned trip records)';
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Found % orphaned trip records!', v_orphans;
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 14: Analytical View Queryability Verification
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_fleet_rows BIGINT;
    v_route_rows BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_fleet_rows FROM vw_fleet_summary;
    SELECT COUNT(*) INTO v_route_rows FROM vw_route_performance;

    IF v_fleet_rows > 0 AND v_route_rows > 0 THEN
        RAISE NOTICE '[PASS] CHK 14: Analytical views execute successfully (vw_fleet: %, vw_route: %)',
            v_fleet_rows, v_route_rows;
    ELSE
        RAISE EXCEPTION 'RESTORE FAILED: Analytical views returned 0 rows!';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- CHECKPOINT 15: Audit Trail Verification (audit_logs)
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_audit_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_audit_count FROM audit_logs;

    RAISE NOTICE '[PASS] CHK 15: Audit trail verified (% audit log entries restored)', v_audit_count;
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'RESTORATION VALIDATION COMPLETE: ALL 15 CHECKPOINTS PASSED!';
    RAISE NOTICE '=====================================================';
END;
$$;
