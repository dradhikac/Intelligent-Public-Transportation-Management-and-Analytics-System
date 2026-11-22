-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/29_database_monitoring.sql
-- PURPOSE: Step 12 – Production DBA Performance & Health Monitoring
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- DESCRIPTION:
--   Comprehensive production monitoring queries inspecting active sessions,
--   lock contention, cache hit ratios, index effectiveness, table bloat,
--   and long-running transactions.
-- =====================================================================

-- =====================================================================
-- 1. ACTIVE SESSIONS & WAIT EVENT ANALYSIS (pg_stat_activity)
-- Purpose: Real-time inspection of active queries, execution durations,
--          and connection states.
-- =====================================================================
SELECT
    pid,
    usename,
    client_addr,
    application_name,
    state,
    wait_event_type,
    wait_event,
    ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - query_start))::NUMERIC, 2) AS query_duration_seconds,
    ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - xact_start))::NUMERIC, 2) AS xact_duration_seconds,
    LEFT(query, 100) AS current_query_snippet
FROM pg_stat_activity
WHERE datname = current_database()
  AND pid <> pg_backend_pid()
ORDER BY query_start ASC NULLS LAST;


-- =====================================================================
-- 2. LOCK CONTENTION & BLOCKED SESSIONS (pg_locks + pg_blocking_pids)
-- Purpose: Identify blocked transactions, lock modes, and the root blocker.
-- =====================================================================
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    pg_blocking_pids(blocked.pid) AS blocker_pids,
    blocked_activity.query AS blocked_query,
    blocker_activity.query AS blocker_query,
    ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - blocked.state_change))::NUMERIC, 2) AS waiting_seconds
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocked_activity ON blocked.pid = blocked_activity.pid
CROSS JOIN LATERAL unnest(pg_blocking_pids(blocked.pid)) AS blocker_pid
JOIN pg_stat_activity blocker_activity ON blocker_pid = blocker_activity.pid
WHERE array_length(pg_blocking_pids(blocked.pid), 1) > 0;


-- =====================================================================
-- 3. BUFFER CACHE HIT RATIO PER RELATION (pg_statio_user_tables)
-- Purpose: Measure if operational tables are cached in RAM or reading disk.
-- =====================================================================
SELECT
    relname AS table_name,
    heap_blks_read AS disk_blocks_read,
    heap_blks_hit AS buffer_blocks_hit,
    ROUND(
        100.0 * heap_blks_hit / NULLIF(heap_blks_hit + heap_blks_read, 0),
        2
    ) AS table_cache_hit_pct,
    idx_blks_hit AS index_blocks_hit,
    ROUND(
        100.0 * idx_blks_hit / NULLIF(idx_blks_hit + idx_blks_read, 0),
        2
    ) AS index_cache_hit_pct
FROM pg_statio_user_tables
WHERE schemaname = 'public'
ORDER BY heap_blks_read DESC;


-- =====================================================================
-- 4. TABLE BLOAT & VACUUM CADENCE (pg_stat_user_tables)
-- Purpose: Track dead tuples accumulation and verify autovacuum frequency.
-- =====================================================================
SELECT
    relname AS table_name,
    n_live_tup AS live_rows,
    n_dead_tup AS dead_rows,
    ROUND(
        100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0),
        2
    ) AS dead_row_pct,
    last_vacuum,
    last_autovacuum,
    vacuum_count,
    autovacuum_count
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY n_dead_tup DESC;


-- =====================================================================
-- 5. INDEX EFFICIENCY & SCAN UTILIZATION (pg_stat_user_indexes)
-- Purpose: Measure index scans vs table sequential scans.
-- =====================================================================
SELECT
    ui.relname AS table_name,
    ui.indexrelname AS index_name,
    ui.idx_scan AS index_scans,
    ui.idx_tup_read AS tuples_read,
    ui.idx_tup_fetch AS tuples_fetched,
    pg_size_pretty(pg_relation_size(ui.indexrelid)) AS index_size
FROM pg_stat_user_indexes ui
WHERE ui.schemaname = 'public'
ORDER BY ui.idx_scan DESC, ui.relname;


-- =====================================================================
-- 6. UNUSED INDEX CANDIDATE AUDIT
-- Purpose: Identify indexes with 0 scans (potential candidates for removal).
-- DBA NOTE: Only evaluate after collecting statistics over weeks of peak traffic!
-- =====================================================================
SELECT
    ui.relname AS table_name,
    ui.indexrelname AS unused_index_name,
    pg_size_pretty(pg_relation_size(ui.indexrelid)) AS wasted_disk_space
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE ui.schemaname = 'public'
  AND ui.idx_scan = 0
  AND NOT i.indisprimary
  AND NOT i.indisunique
ORDER BY pg_relation_size(ui.indexrelid) DESC;


-- =====================================================================
-- 7. DATABASE TRANSACTION COMMIT VS ROLLBACK HEALTH (pg_stat_database)
-- Purpose: Ensure rollback rates remain < 1-2% of total transaction volume.
-- =====================================================================
SELECT
    datname AS database_name,
    xact_commit AS committed_transactions,
    xact_rollback AS rolled_back_transactions,
    ROUND(
        100.0 * xact_rollback / NULLIF(xact_commit + xact_rollback, 0),
        3
    ) AS rollback_ratio_pct,
    pg_size_pretty(pg_database_size(datname)) AS total_database_size
FROM pg_stat_database
WHERE datname = current_database();


-- =====================================================================
-- 8. LONG-RUNNING / IDLE-IN-TRANSACTION SESSIONS ALERT
-- Purpose: Detect abandoned transactions holding open locks.
-- =====================================================================
SELECT
    pid,
    usename,
    state,
    ROUND(EXTRACT(EPOCH FROM (clock_timestamp() - state_change))::NUMERIC, 1) AS idle_duration_seconds,
    query AS last_statement
FROM pg_stat_activity
WHERE datname = current_database()
  AND state IN ('idle in transaction', 'idle in transaction (aborted)')
  AND (clock_timestamp() - state_change) > INTERVAL '30 seconds'
ORDER BY state_change ASC;
