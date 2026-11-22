-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/27_index_optimization.sql
-- PURPOSE: Step 12 – Index Optimization, Partial Indexes & Covering Indexes
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- ARCHITECTURE & STRATEGY:
--   1. Existing Index Assessment: Avoid redundant or duplicate B-trees.
--   2. Composite Indexing: Combine equality predicates with range predicates.
--   3. Partial Indexing: Index only the relevant active subset of rows,
--      reducing index footprint by 30-50% and improving cache residency.
--   4. Covering Indexes (INCLUDE): Support Index-Only Scans by attaching
--      payload columns to the index leaf pages without bloating the B-tree key.
--   5. Idempotent & Reversible: All indexes use IF NOT EXISTS with clear rollback.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: DEPLOYING TARGETED PERFORMANCE INDEXES';
    RAISE NOTICE '=====================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- 1. COMPOSITE INDEX: trips(trip_status, service_date)
-- Target Workload: Real-time dispatching and daily operations monitoring.
-- Problem with Existing: idx_trips_status and idx_trips_route_date require
-- a BitmapAnd merge step when queries filter by both status and date.
-- Benefit: Provides a single, contiguous B-tree slice for queries like:
--   WHERE trip_status = 'RUNNING' AND service_date = CURRENT_DATE
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_trips_status_service_date
ON trips(trip_status, service_date);

DO $$
BEGIN
    RAISE NOTICE '[OPTIMIZATION 1] Created composite index: idx_trips_status_service_date';
END;
$$;


-- ---------------------------------------------------------------------
-- 2. PARTIAL INDEX: trips(bus_id, service_date) WHERE trip_status = 'COMPLETED'
-- Target Workload: Fleet summary (vw_fleet_summary) and bus utilization (fn_get_bus_utilization).
-- Rationale: In long-term operations, analytical queries ignore CANCELLED
-- and SCHEDULED rows. This partial index excludes non-completed trips,
-- significantly reducing index bloat and disk I/O.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_trips_completed_bus
ON trips(bus_id, service_date)
WHERE trip_status = 'COMPLETED';

DO $$
BEGIN
    RAISE NOTICE '[OPTIMIZATION 2] Created partial index: idx_trips_completed_bus (WHERE trip_status = ''COMPLETED'')';
END;
$$;


-- ---------------------------------------------------------------------
-- 3. COVERING INDEX (INCLUDE): passenger_counts(trip_stop_log_id) INCLUDE (boarding_count, alighting_count)
-- Target Workload: Stop footfall and passenger demand queries (Query 4, View 3).
-- Rationale: When aggregating passenger totals per stop, the query engine
-- frequently joins on trip_stop_log_id and fetches boarding/alighting counts.
-- By including these metrics in the index leaf pages, PostgreSQL can execute
-- an INDEX-ONLY SCAN, completely bypassing the heap table pages!
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_passenger_covering
ON passenger_counts(trip_stop_log_id)
INCLUDE (boarding_count, alighting_count);

DO $$
BEGIN
    RAISE NOTICE '[OPTIMIZATION 3] Created covering index: idx_passenger_covering INCLUDE (boarding_count, alighting_count)';
END;
$$;


-- ---------------------------------------------------------------------
-- 4. PARTIAL INDEX: buses(bus_id, bus_type_id) WHERE status = 'ACTIVE'
-- Target Workload: sp_create_trip dispatch validation and vehicle availability lookups.
-- Rationale: Buses in MAINTENANCE or RETIRED status are excluded from daily
-- schedule allocation. Indexing only 'ACTIVE' assets speeds up row locks
-- and availability checks during peak dispatch periods.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_buses_active
ON buses(bus_id, bus_type_id)
WHERE status = 'ACTIVE';

DO $$
BEGIN
    RAISE NOTICE '[OPTIMIZATION 4] Created partial index: idx_buses_active (WHERE status = ''ACTIVE'')';
END;
$$;


-- ---------------------------------------------------------------------
-- 5. COMPOSITE INDEX: schedule_stop_times(route_id, scheduled_arrival)
-- Target Workload: Timetable generation, route stop sequence lookups,
-- and schedule adherence variance queries.
-- Rationale: Existing index idx_schedule_stop_route only indexes route_id.
-- Adding scheduled_arrival supports ordered timetable scans without an
-- explicit Sort node in memory.
-- ---------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_sched_stop_route_arrival
ON schedule_stop_times(route_id, scheduled_arrival);

DO $$
BEGIN
    RAISE NOTICE '[OPTIMIZATION 5] Created composite index: idx_sched_stop_route_arrival';
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'ALL 5 TARGETED PERFORMANCE INDEXES SUCCESSFULLY DEPLOYED!';
    RAISE NOTICE '=====================================================';
END;
$$;


-- =====================================================================
-- DOCUMENTED ROLLBACK SCRIPT (IF DE-OPTIMIZATION REQUIRED)
-- =====================================================================
-- DROP INDEX IF EXISTS idx_trips_status_service_date;
-- DROP INDEX IF EXISTS idx_trips_completed_bus;
-- DROP INDEX IF EXISTS idx_passenger_covering;
-- DROP INDEX IF EXISTS idx_buses_active;
-- DROP INDEX IF EXISTS idx_sched_stop_route_arrival;
