-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/12_audit_analytics.sql
-- PURPOSE: Audit Analytics Queries & Compliance Inspection
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- ---------------------------------------------------------------------
-- QUERY 1: Display the Latest 20 Audit Events Across All Tables
-- Purpose: Real-time operational audit log for system monitoring.
-- ---------------------------------------------------------------------
SELECT
    al.audit_id,
    al.changed_at,
    al.changed_by,
    al.table_name,
    al.record_id,
    al.operation,
    CASE al.operation
        WHEN 'INSERT' THEN al.new_data
        WHEN 'DELETE' THEN al.old_data
        WHEN 'UPDATE' THEN jsonb_build_object(
            'before', al.old_data,
            'after', al.new_data
        )
    END AS change_payload
FROM audit_logs al
ORDER BY al.changed_at DESC, al.audit_id DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- QUERY 2: Total Operations Count Grouped by Table Name
-- Purpose: Monitor table modification distribution across the system.
-- ---------------------------------------------------------------------
SELECT
    al.table_name,
    COUNT(al.audit_id) AS total_mutations,
    COUNT(CASE WHEN al.operation = 'INSERT' THEN 1 END) AS inserts_count,
    COUNT(CASE WHEN al.operation = 'UPDATE' THEN 1 END) AS updates_count,
    COUNT(CASE WHEN al.operation = 'DELETE' THEN 1 END) AS deletes_count,
    ROUND(
        100.0 * COUNT(al.audit_id) / NULLIF(SUM(COUNT(al.audit_id)) OVER (), 0),
        2
    ) AS mutation_share_pct
FROM audit_logs al
GROUP BY al.table_name
ORDER BY total_mutations DESC;


-- ---------------------------------------------------------------------
-- QUERY 3: Global Operation Breakdown (INSERT vs UPDATE vs DELETE)
-- Purpose: High-level database mutation summary.
-- ---------------------------------------------------------------------
SELECT
    al.operation,
    COUNT(al.audit_id) AS operation_count,
    ROUND(
        100.0 * COUNT(al.audit_id) / NULLIF(SUM(COUNT(al.audit_id)) OVER (), 0),
        2
    ) AS operation_percentage,
    MIN(al.changed_at) AS earliest_logged_event,
    MAX(al.changed_at) AS latest_logged_event
FROM audit_logs al
GROUP BY al.operation
ORDER BY operation_count DESC;


-- ---------------------------------------------------------------------
-- QUERY 4: Complete Change History of a Particular Bus
-- Purpose: Reconstruct the lifecycle audit trail of a specific vehicle asset.
-- Replace ':target_bus_id' with desired bus_id (e.g. 1).
-- ---------------------------------------------------------------------
SELECT
    al.audit_id,
    al.changed_at,
    al.changed_by,
    al.operation,
    al.record_id AS bus_id,
    COALESCE(al.new_data->>'registration_number', al.old_data->>'registration_number') AS registration_number,
    al.old_data->>'status' AS previous_status,
    al.new_data->>'status' AS current_status,
    al.old_data->>'last_service_date' AS previous_service_date,
    al.new_data->>'last_service_date' AS new_service_date
FROM audit_logs al
WHERE al.table_name = 'buses'
  AND al.record_id = (SELECT b.bus_id FROM buses b LIMIT 1)
ORDER BY al.changed_at ASC, al.audit_id ASC;


-- ---------------------------------------------------------------------
-- QUERY 5: Modification History of a Particular Driver
-- Purpose: Audit employment, roster, and compliance adjustments for a driver.
-- Replace target driver query with desired ID.
-- ---------------------------------------------------------------------
SELECT
    al.audit_id,
    al.changed_at,
    al.changed_by,
    al.operation,
    al.record_id AS driver_id,
    COALESCE(al.new_data->>'employee_code', al.old_data->>'employee_code') AS employee_code,
    al.old_data->>'status' AS previous_status,
    al.new_data->>'status' AS current_status,
    al.old_data->>'license_expiry_date' AS previous_license_expiry,
    al.new_data->>'license_expiry_date' AS new_license_expiry
FROM audit_logs al
WHERE al.table_name = 'drivers'
  AND al.record_id = (SELECT d.driver_id FROM drivers d LIMIT 1)
ORDER BY al.changed_at ASC, al.audit_id ASC;


-- ---------------------------------------------------------------------
-- QUERY 6: Identify the Latest Passenger Count Changes and Delta Adjustments
-- Purpose: Audit passenger telemetry corrections and sensor reconciliations.
-- ---------------------------------------------------------------------
SELECT
    al.audit_id,
    al.changed_at,
    al.changed_by,
    al.operation,
    al.record_id AS passenger_count_id,
    COALESCE(al.new_data->>'trip_stop_log_id', al.old_data->>'trip_stop_log_id')::BIGINT AS trip_stop_log_id,
    (al.old_data->>'boarding_count')::INTEGER AS old_boardings,
    (al.new_data->>'boarding_count')::INTEGER AS new_boardings,
    (
        (al.new_data->>'boarding_count')::INTEGER -
        (al.old_data->>'boarding_count')::INTEGER
    ) AS boarding_adjustment_delta,
    (al.old_data->>'alighting_count')::INTEGER AS old_alightings,
    (al.new_data->>'alighting_count')::INTEGER AS new_alightings
FROM audit_logs al
WHERE al.table_name = 'passenger_counts'
ORDER BY al.changed_at DESC, al.audit_id DESC
LIMIT 20;


-- ---------------------------------------------------------------------
-- QUERY 7: Display All Delay Record Modifications and Severity Transitions
-- Purpose: Track modifications to operational delay incidents.
-- ---------------------------------------------------------------------
SELECT
    al.audit_id,
    al.changed_at,
    al.changed_by,
    al.operation,
    al.record_id AS delay_id,
    COALESCE(al.new_data->>'trip_stop_log_id', al.old_data->>'trip_stop_log_id')::BIGINT AS trip_stop_log_id,
    (al.old_data->>'delay_seconds')::INTEGER AS old_delay_seconds,
    (al.new_data->>'delay_seconds')::INTEGER AS new_delay_seconds,
    al.old_data->>'severity' AS previous_severity,
    al.new_data->>'severity' AS current_severity,
    COALESCE(al.new_data->>'remarks', al.old_data->>'remarks') AS remarks
FROM audit_logs al
WHERE al.table_name = 'delay_records'
ORDER BY al.changed_at DESC, al.audit_id DESC
LIMIT 20;

-- =====================================================================
-- END OF AUDIT ANALYTICS SCRIPT
-- =====================================================================
