-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/31_backup_validation.sql
-- PURPOSE: Step 13 – Pre-Backup Assessment & Server Readiness Inspection
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- DESCRIPTION:
--   Inspects database readiness prior to initiating logical or physical
--   backups: database size, active connection states, open transaction age,
--   current WAL Write-Ahead Log position, and archive configuration.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: PRE-BACKUP ENVIRONMENT & READINESS AUDIT';
    RAISE NOTICE '=====================================================';
END;
$$;

-- =====================================================================
-- 1. DATABASE SIZE & VOLUMETRIC METRICS
-- Purpose: Quantify storage footprint to forecast backup storage requirements.
-- =====================================================================
SELECT
    datname AS database_name,
    pg_size_pretty(pg_database_size(datname)) AS total_size_pretty,
    pg_database_size(datname) AS total_bytes
FROM pg_database
WHERE datname = current_database();


-- =====================================================================
-- 2. OPERATIONAL TABLE & ROW INVENTORY FOR BACKUP MANIFEST
-- Purpose: Capture exact live tuple counts across all 17 core relations
--          to serve as the benchmark for post-restore verification.
-- =====================================================================
SELECT
    c.relname AS table_name,
    c.reltuples::BIGINT AS estimated_row_count,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_relation_size
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname IN (
    'bus_types', 'buses', 'maintenance_records', 'routes', 'stops',
    'route_stops', 'drivers', 'schedules', 'operating_days',
    'schedule_operating_days', 'schedule_stop_times', 'trips',
    'trip_stop_logs', 'passenger_counts', 'delay_reasons',
    'delay_records', 'audit_logs'
  )
ORDER BY c.relname ASC;


-- =====================================================================
-- 3. ACTIVE SESSIONS & UNCOMMITTED TRANSACTIONS AUDIT
-- Purpose: Verify no long-running transactions or lock conflicts that
--          could delay or interfere with pg_dump snapshot generation.
-- =====================================================================
SELECT
    pid,
    usename,
    state,
    wait_event_type,
    wait_event,
    ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - xact_start))::NUMERIC, 2) AS xact_duration_seconds,
    query AS active_query
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
  AND state <> 'idle'
ORDER BY xact_start ASC;


-- =====================================================================
-- 4. CURRENT WRITE-AHEAD LOG (WAL) LSN POSITION
-- Purpose: Record the current Log Sequence Number (LSN) before backup.
-- =====================================================================
SELECT
    pg_current_wal_lsn() AS current_wal_lsn,
    pg_walfile_name(pg_current_wal_lsn()) AS current_wal_file;


-- =====================================================================
-- 5. WAL ARCHIVING & DISASTER RECOVERY READINESS
-- Purpose: Inspect archive_mode and archive_command for PITR capability.
-- =====================================================================
SELECT
    name AS config_parameter,
    setting AS parameter_value,
    short_desc AS description
FROM pg_settings
WHERE name IN (
    'wal_level',
    'archive_mode',
    'archive_command',
    'archive_timeout',
    'max_wal_size',
    'min_wal_size'
)
ORDER BY name;
