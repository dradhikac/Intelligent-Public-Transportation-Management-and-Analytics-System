-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/10_triggers.sql
-- PURPOSE: Production Database Triggers & Event-Driven Automation
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- =====================================================================
-- 1. GENERIC AUDIT LOGGING FUNCTION
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION: fn_audit_changes
-- Purpose: Reusable row-level AFTER trigger function capturing INSERT,
-- UPDATE, and DELETE mutations into the audit_logs table.
-- Captures:
--   - table_name: Trigger source table
--   - record_id: Extracted primary key of affected record
--   - operation: 'INSERT', 'UPDATE', or 'DELETE'
--   - old_data: Previous state in JSONB (NULL on INSERT)
--   - new_data: New state in JSONB (NULL on DELETE)
--   - changed_at: Current timestamp
--   - changed_by: Active database session user
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_audit_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_record_id BIGINT;
    v_old_data JSONB := NULL;
    v_new_data JSONB := NULL;
BEGIN
    -- Prevent recursive auditing if accidentally attached to audit_logs
    IF TG_TABLE_NAME = 'audit_logs' THEN
        RETURN NULL;
    END IF;

    -- Extract OLD and NEW state as JSONB based on operation
    IF TG_OP = 'INSERT' THEN
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_data := to_jsonb(OLD);
        v_new_data := to_jsonb(NEW);
    ELSIF TG_OP = 'DELETE' THEN
        v_old_data := to_jsonb(OLD);
    END IF;

    -- Resolve record_id from the primary key column corresponding to the audited table
    v_record_id := CASE TG_TABLE_NAME
        WHEN 'buses'               THEN COALESCE((v_new_data->>'bus_id')::BIGINT, (v_old_data->>'bus_id')::BIGINT)
        WHEN 'drivers'             THEN COALESCE((v_new_data->>'driver_id')::BIGINT, (v_old_data->>'driver_id')::BIGINT)
        WHEN 'trips'               THEN COALESCE((v_new_data->>'trip_id')::BIGINT, (v_old_data->>'trip_id')::BIGINT)
        WHEN 'passenger_counts'    THEN COALESCE((v_new_data->>'passenger_count_id')::BIGINT, (v_old_data->>'passenger_count_id')::BIGINT)
        WHEN 'delay_records'       THEN COALESCE((v_new_data->>'delay_id')::BIGINT, (v_old_data->>'delay_id')::BIGINT)
        WHEN 'maintenance_records' THEN COALESCE((v_new_data->>'maintenance_id')::BIGINT, (v_old_data->>'maintenance_id')::BIGINT)
        ELSE NULL
    END;

    -- Insert audit entry into audit_logs table
    INSERT INTO audit_logs (
        table_name,
        record_id,
        operation,
        old_data,
        new_data,
        changed_at,
        changed_by
    )
    VALUES (
        TG_TABLE_NAME,
        v_record_id,
        TG_OP,
        v_old_data,
        v_new_data,
        CURRENT_TIMESTAMP,
        SESSION_USER
    );

    RETURN NULL; -- For AFTER row triggers, return value is ignored
END;
$$;


-- =====================================================================
-- 2. ATTACH AUDIT TRIGGERS TO 6 CORE TABLES
-- =====================================================================

-- Table 1: buses
DROP TRIGGER IF EXISTS trg_audit_buses ON buses;
CREATE TRIGGER trg_audit_buses
AFTER INSERT OR UPDATE OR DELETE ON buses
FOR EACH ROW
EXECUTE FUNCTION fn_audit_changes();

-- Table 2: drivers
DROP TRIGGER IF EXISTS trg_audit_drivers ON drivers;
CREATE TRIGGER trg_audit_drivers
AFTER INSERT OR UPDATE OR DELETE ON drivers
FOR EACH ROW
EXECUTE FUNCTION fn_audit_changes();

-- Table 3: trips
DROP TRIGGER IF EXISTS trg_audit_trips ON trips;
CREATE TRIGGER trg_audit_trips
AFTER INSERT OR UPDATE OR DELETE ON trips
FOR EACH ROW
EXECUTE FUNCTION fn_audit_changes();

-- Table 4: passenger_counts
DROP TRIGGER IF EXISTS trg_audit_passenger_counts ON passenger_counts;
CREATE TRIGGER trg_audit_passenger_counts
AFTER INSERT OR UPDATE OR DELETE ON passenger_counts
FOR EACH ROW
EXECUTE FUNCTION fn_audit_changes();

-- Table 5: delay_records
DROP TRIGGER IF EXISTS trg_audit_delay_records ON delay_records;
CREATE TRIGGER trg_audit_delay_records
AFTER INSERT OR UPDATE OR DELETE ON delay_records
FOR EACH ROW
EXECUTE FUNCTION fn_audit_changes();

-- Table 6: maintenance_records
DROP TRIGGER IF EXISTS trg_audit_maintenance ON maintenance_records;
CREATE TRIGGER trg_audit_maintenance
AFTER INSERT OR UPDATE OR DELETE ON maintenance_records
FOR EACH ROW
EXECUTE FUNCTION fn_audit_changes();


-- =====================================================================
-- 3. AUTOMATIC DELAY SEVERITY CLASSIFICATION TRIGGER
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION: fn_auto_classify_delay
-- Purpose: BEFORE INSERT OR UPDATE trigger function on delay_records.
-- Validates delay_seconds and automatically sets severity using fn_calculate_delay_severity().
-- Enforces integrity even during direct raw SQL inserts.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_auto_classify_delay()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- 1. Validate delay_seconds parameter
    IF NEW.delay_seconds IS NULL THEN
        RAISE EXCEPTION 'delay_seconds cannot be NULL in delay_records'
            USING ERRCODE = 'null_value_not_allowed';
    END IF;

    IF NEW.delay_seconds < 0 THEN
        RAISE EXCEPTION 'Delay duration cannot be negative: % seconds', NEW.delay_seconds
            USING ERRCODE = 'check_violation';
    END IF;

    -- 2. Call existing business function to classify delay severity
    NEW.severity := fn_calculate_delay_severity(NEW.delay_seconds);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_classify_delay ON delay_records;
CREATE TRIGGER trg_auto_classify_delay
BEFORE INSERT OR UPDATE OF delay_seconds ON delay_records
FOR EACH ROW
EXECUTE FUNCTION fn_auto_classify_delay();


-- =====================================================================
-- 4. MAINTENANCE AUTOMATION TRIGGER
-- =====================================================================

-- ---------------------------------------------------------------------
-- FUNCTION: fn_sync_bus_maintenance_date
-- Purpose: Synchronize buses.last_service_date based on the latest completed
-- maintenance record. Safely handles completions, updates, reversals, and deletions.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_sync_bus_maintenance_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_bus_id BIGINT;
    v_latest_completed_date DATE;
BEGIN
    -- Determine target bus ID (handles INSERT, UPDATE, and DELETE)
    v_bus_id := COALESCE(NEW.bus_id, OLD.bus_id);

    -- Find the true latest completed maintenance date for this bus
    SELECT MAX(mr.maintenance_date)
    INTO v_latest_completed_date
    FROM maintenance_records mr
    WHERE mr.bus_id = v_bus_id
      AND mr.maintenance_status = 'COMPLETED';

    -- Update bus last_service_date to match the actual true latest completed date
    UPDATE buses
    SET last_service_date = v_latest_completed_date
    WHERE bus_id = v_bus_id;

    -- If bus_id was updated to a different bus, also sync the previous bus
    IF TG_OP = 'UPDATE' AND OLD.bus_id IS DISTINCT FROM NEW.bus_id THEN
        SELECT MAX(mr.maintenance_date)
        INTO v_latest_completed_date
        FROM maintenance_records mr
        WHERE mr.bus_id = OLD.bus_id
          AND mr.maintenance_status = 'COMPLETED';

        UPDATE buses
        SET last_service_date = v_latest_completed_date
        WHERE bus_id = OLD.bus_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_bus_maintenance_date ON maintenance_records;
CREATE TRIGGER trg_sync_bus_maintenance_date
AFTER INSERT OR UPDATE OF maintenance_status, maintenance_date, bus_id OR DELETE ON maintenance_records
FOR EACH ROW
EXECUTE FUNCTION fn_sync_bus_maintenance_date();

-- =====================================================================
-- END OF TRIGGERS SCRIPT
-- =====================================================================
