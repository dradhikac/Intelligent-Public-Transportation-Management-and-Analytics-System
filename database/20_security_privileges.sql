-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/20_security_privileges.sql
-- PURPOSE: Step 11 – Principle of Least Privilege (PoLP) Permissions Matrix
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- PRIVILEGE MODEL:
--   1. PUBLIC LOCKDOWN: Revoke default public schema grants.
--   2. SCHEMA PRIVILEGES: Explicit USAGE to TransitIQ roles only.
--   3. TABLE PRIVILEGES: Role-specific SELECT, INSERT, UPDATE, DELETE.
--   4. SEQUENCE PRIVILEGES: USAGE & SELECT for generated primary keys.
--   5. ROUTINE PRIVILEGES: EXECUTE on specific procedures & functions.
--   6. AUDIT IMMUTABILITY: No role (even admin) granted UPDATE/DELETE on audit_logs.
--   7. SECURITY DEFINER HARDENING: Explicit search_path = public, pg_temp.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: CONFIGURING ACCESS PRIVILEGES & POLP';
    RAISE NOTICE '=====================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- 1. PUBLIC SCHEMA LOCKDOWN
-- ---------------------------------------------------------------------
-- Revoke all default table, sequence, and routine privileges from PUBLIC
-- ---------------------------------------------------------------------

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;

-- Grant schema USAGE to application group roles
GRANT USAGE ON SCHEMA public TO
    transit_admin,
    transit_dispatcher,
    transit_fleet_manager,
    transit_analyst,
    transit_auditor;

DO $$
BEGIN
    RAISE NOTICE '[SUCCESS] Public lockdown applied; USAGE granted to application roles.';
END;
$$;


-- ---------------------------------------------------------------------
-- 2. HARDEN SECURITY DEFINER FUNCTIONS
-- ---------------------------------------------------------------------
-- Prevent search_path hijacking vulnerabilities in security-critical routines
-- ---------------------------------------------------------------------

ALTER FUNCTION fn_audit_changes() SET search_path = public, pg_temp;
ALTER FUNCTION fn_auto_classify_delay() SET search_path = public, pg_temp;
ALTER FUNCTION fn_sync_bus_maintenance_date() SET search_path = public, pg_temp;

DO $$
BEGIN
    RAISE NOTICE '[SUCCESS] Trigger functions hardened with search_path = public, pg_temp.';
END;
$$;


-- ---------------------------------------------------------------------
-- 3. ROLE: transit_admin (Application Administrator)
-- ---------------------------------------------------------------------
-- Full DML on operational objects; SELECT-only on audit_logs (audit immutability)
-- ---------------------------------------------------------------------

-- Table permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON
    bus_types,
    buses,
    maintenance_records,
    routes,
    stops,
    route_stops,
    drivers,
    schedules,
    operating_days,
    schedule_operating_days,
    schedule_stop_times,
    trips,
    trip_stop_logs,
    passenger_counts,
    delay_reasons,
    delay_records
TO transit_admin;

-- Audit logs are strictly read-only even for administrative roles
GRANT SELECT ON audit_logs TO transit_admin;

-- Analytical views
GRANT SELECT ON
    vw_fleet_summary,
    vw_route_performance,
    vw_passenger_demand,
    vw_delay_analysis,
    vw_driver_performance
TO transit_admin;

-- Sequence permissions
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO transit_admin;

-- Routine execution
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO transit_admin;


-- ---------------------------------------------------------------------
-- 4. ROLE: transit_dispatcher (Operations & Dispatch)
-- ---------------------------------------------------------------------
-- Read reference infrastructure; DML on operational trips & telemetry
-- ---------------------------------------------------------------------

-- Read-only reference data
GRANT SELECT ON
    bus_types,
    buses,
    drivers,
    routes,
    stops,
    route_stops,
    schedules,
    operating_days,
    schedule_operating_days,
    schedule_stop_times,
    delay_reasons
TO transit_dispatcher;

-- Operational DML permissions
GRANT SELECT, INSERT, UPDATE ON
    trips,
    trip_stop_logs,
    passenger_counts,
    delay_records
TO transit_dispatcher;

-- Sequence permissions for operational tables
DO $$
DECLARE
    v_seq RECORD;
BEGIN
    FOR v_seq IN (
        SELECT sequence_name
        FROM information_schema.sequences
        WHERE sequence_schema = 'public'
          AND sequence_name IN (
            'trips_trip_id_seq',
            'trip_stop_logs_trip_stop_log_id_seq',
            'passenger_counts_passenger_count_id_seq',
            'delay_records_delay_id_seq'
          )
    ) LOOP
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %I TO transit_dispatcher', v_seq.sequence_name);
    END LOOP;
END;
$$;

-- Stored procedure execution
GRANT EXECUTE ON PROCEDURE sp_create_trip(BIGINT, BIGINT, BIGINT, BIGINT, DATE, TIMESTAMPTZ, BIGINT) TO transit_dispatcher;
GRANT EXECUTE ON PROCEDURE sp_record_passenger_count(BIGINT, INTEGER, INTEGER) TO transit_dispatcher;
GRANT EXECUTE ON PROCEDURE sp_record_delay(BIGINT, BIGINT, INTEGER, TEXT, BIGINT) TO transit_dispatcher;

-- Operational function execution
GRANT EXECUTE ON FUNCTION fn_calculate_trip_delay(BIGINT) TO transit_dispatcher;
GRANT EXECUTE ON FUNCTION fn_calculate_delay_severity(INTEGER) TO transit_dispatcher;
GRANT EXECUTE ON FUNCTION fn_get_bus_status(BIGINT) TO transit_dispatcher;
GRANT EXECUTE ON FUNCTION fn_get_stop_demand(BIGINT) TO transit_dispatcher;
GRANT EXECUTE ON FUNCTION fn_get_route_performance(BIGINT) TO transit_dispatcher;
GRANT EXECUTE ON FUNCTION fn_check_license_expiry(BIGINT) TO transit_dispatcher;

-- Operational view access
GRANT SELECT ON
    vw_route_performance,
    vw_passenger_demand,
    vw_delay_analysis
TO transit_dispatcher;


-- ---------------------------------------------------------------------
-- 5. ROLE: transit_fleet_manager (Vehicle & Depot Maintenance)
-- ---------------------------------------------------------------------
-- Read bus inventory; Manage maintenance records and vehicle service status
-- ---------------------------------------------------------------------

-- Asset & maintenance tables
GRANT SELECT ON bus_types, routes TO transit_fleet_manager;
GRANT SELECT, UPDATE (status, last_service_date) ON buses TO transit_fleet_manager;
GRANT SELECT, INSERT, UPDATE ON maintenance_records TO transit_fleet_manager;

-- Sequence permission for maintenance
DO $$
DECLARE
    v_seq RECORD;
BEGIN
    FOR v_seq IN (
        SELECT sequence_name
        FROM information_schema.sequences
        WHERE sequence_schema = 'public'
          AND sequence_name = 'maintenance_records_maintenance_id_seq'
    ) LOOP
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %I TO transit_fleet_manager', v_seq.sequence_name);
    END LOOP;
END;
$$;

-- Maintenance functions
GRANT EXECUTE ON FUNCTION fn_get_bus_status(BIGINT) TO transit_fleet_manager;
GRANT EXECUTE ON FUNCTION fn_get_maintenance_status(BIGINT) TO transit_fleet_manager;
GRANT EXECUTE ON FUNCTION fn_get_bus_utilization(BIGINT) TO transit_fleet_manager;

-- Fleet analytical view
GRANT SELECT ON vw_fleet_summary TO transit_fleet_manager;


-- ---------------------------------------------------------------------
-- 6. ROLE: transit_analyst (Reporting & Business Intelligence)
-- ---------------------------------------------------------------------
-- Read-only access to analytical views and reference tables; zero write rights
-- ---------------------------------------------------------------------

-- View access
GRANT SELECT ON
    vw_fleet_summary,
    vw_route_performance,
    vw_passenger_demand,
    vw_delay_analysis,
    vw_driver_performance
TO transit_analyst;

-- Reference table read access for custom reporting queries
GRANT SELECT ON
    bus_types,
    buses,
    routes,
    stops,
    route_stops,
    drivers,
    schedules,
    operating_days,
    delay_reasons
TO transit_analyst;

-- Analytical function execution
GRANT EXECUTE ON FUNCTION fn_get_bus_status(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_get_maintenance_status(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_get_bus_utilization(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_calculate_trip_delay(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_get_route_performance(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_get_stop_demand(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_check_license_expiry(BIGINT) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_calculate_delay_severity(INTEGER) TO transit_analyst;
GRANT EXECUTE ON FUNCTION fn_get_driver_performance(BIGINT) TO transit_analyst;


-- ---------------------------------------------------------------------
-- 7. ROLE: transit_auditor (Compliance & Audit Logging)
-- ---------------------------------------------------------------------
-- Read-only access to audit_logs and operational reference tables
-- ---------------------------------------------------------------------

GRANT SELECT ON audit_logs TO transit_auditor;

-- Cross-reference read access for auditing operational events
GRANT SELECT ON
    buses,
    drivers,
    trips,
    maintenance_records,
    passenger_counts,
    delay_records
TO transit_auditor;

DO $$
BEGIN
    RAISE NOTICE '-----------------------------------------------------';
    RAISE NOTICE '[SUCCESS] Role-Based Access Control privileges applied:';
    RAISE NOTICE '  - transit_admin: Full DML on operational tables, Read-only audit_logs';
    RAISE NOTICE '  - transit_dispatcher: Operational DML + Dispatch procedures';
    RAISE NOTICE '  - transit_fleet_manager: Maintenance DML + Bus status updates';
    RAISE NOTICE '  - transit_analyst: Read-only on 5 Views + Analytical functions';
    RAISE NOTICE '  - transit_auditor: Read-only on audit_logs + Event cross-checks';
    RAISE NOTICE '=====================================================';
END;
$$;
