-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/21_row_level_security.sql
-- PURPOSE: Step 11 – Row-Level Security (RLS) Policy Demonstration
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- ARCHITECTURE & LAB ISOLATION:
--   To avoid disrupting existing operational workflows or batch loaders,
--   this RLS demonstration uses an isolated lab table:
--     `security_lab_trip_access`
--
-- RLS POLICIES IMPLEMENTED:
--   1. SELECT POLICY: Dispatchers can only query their own assigned trip records.
--      Administrators can view all dispatcher records.
--   2. INSERT POLICY (WITH CHECK): Dispatchers can only create records under
--      their own authenticated identity (prevents identity spoofing).
--   3. UPDATE POLICY (USING + WITH CHECK): Dispatchers can only modify their
--      own records and cannot reassign records to another dispatcher.
--
-- IDENTITY MECHANICS (CURRENT_USER vs SESSION_USER):
--   - CURRENT_USER: Reflects the active execution identity (shifted via SET ROLE).
--   - SESSION_USER: Reflects the primary connection authorization.
--   By checking COALESCE matching against both, policies support both direct
--   logins and role-switched testing sessions (SET ROLE / SET SESSION AUTHORIZATION),
--   while respecting SECURITY DEFINER boundaries.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: INITIALIZING ROW-LEVEL SECURITY (RLS)';
    RAISE NOTICE '=====================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- 1. CREATE ISOLATED RLS LAB TABLE
-- ---------------------------------------------------------------------

DROP TABLE IF EXISTS security_lab_trip_access CASCADE;

CREATE TABLE security_lab_trip_access (
    access_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dispatcher_username VARCHAR(50) NOT NULL,
    trip_reference VARCHAR(50) NOT NULL,
    access_description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Grant DML permissions on the lab table to dispatcher and admin roles
GRANT SELECT, INSERT, UPDATE, DELETE ON security_lab_trip_access TO transit_dispatcher, transit_admin;

-- Grant sequence usage
DO $$
DECLARE
    v_seq_name TEXT;
BEGIN
    SELECT pg_get_serial_sequence('security_lab_trip_access', 'access_id') INTO v_seq_name;
    IF v_seq_name IS NOT NULL THEN
        EXECUTE format('GRANT USAGE, SELECT ON SEQUENCE %s TO transit_dispatcher, transit_admin', v_seq_name);
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- 2. SEED INITIAL TEST DATA FOR MULTIPLE DISPATCHERS
-- ---------------------------------------------------------------------

INSERT INTO security_lab_trip_access (dispatcher_username, trip_reference, access_description)
VALUES
    ('test_dispatcher',   'TRIP-REF-101-NORTH', 'North Zone Express Line Dispatch Order'),
    ('test_dispatcher',   'TRIP-REF-102-NORTH', 'North Zone Local Feeder Route Dispatch Order'),
    ('test_dispatcher_2', 'TRIP-REF-201-SOUTH', 'South Zone Coastal Express Dispatch Order'),
    ('test_dispatcher_2', 'TRIP-REF-202-SOUTH', 'South Zone Metro Shuttle Dispatch Order'),
    ('transit_admin',     'TRIP-REF-900-SYSTEM', 'Global System Audit & Emergency Re-route Order');


-- ---------------------------------------------------------------------
-- 3. ENABLE AND FORCE ROW-LEVEL SECURITY
-- ---------------------------------------------------------------------
-- FORCE ROW LEVEL SECURITY ensures that even the table owner (if non-superuser)
-- is subject to the security policies, preventing accidental policy bypass.
-- ---------------------------------------------------------------------

ALTER TABLE security_lab_trip_access ENABLE ROW LEVEL SECURITY;
ALTER TABLE security_lab_trip_access FORCE ROW LEVEL SECURITY;


-- ---------------------------------------------------------------------
-- 4. CONFIGURE RLS POLICIES
-- ---------------------------------------------------------------------

DROP POLICY IF EXISTS rls_trip_access_select ON security_lab_trip_access;
DROP POLICY IF EXISTS rls_trip_access_insert ON security_lab_trip_access;
DROP POLICY IF EXISTS rls_trip_access_update ON security_lab_trip_access;

-- 4.1 SELECT Policy: Tenant isolation by dispatcher username or administrator privilege
CREATE POLICY rls_trip_access_select ON security_lab_trip_access
    FOR SELECT
    TO transit_dispatcher, transit_admin
    USING (
        dispatcher_username IN (CURRENT_USER, SESSION_USER)
        OR pg_has_role(CURRENT_USER, 'transit_admin', 'MEMBER')
        OR pg_has_role(SESSION_USER, 'transit_admin', 'MEMBER')
        OR CURRENT_USER = 'postgres'
    );

-- 4.2 INSERT Policy with WITH CHECK: Prevents inserting records under another user's name
CREATE POLICY rls_trip_access_insert ON security_lab_trip_access
    FOR INSERT
    TO transit_dispatcher, transit_admin
    WITH CHECK (
        dispatcher_username IN (CURRENT_USER, SESSION_USER)
        OR pg_has_role(CURRENT_USER, 'transit_admin', 'MEMBER')
        OR pg_has_role(SESSION_USER, 'transit_admin', 'MEMBER')
        OR CURRENT_USER = 'postgres'
    );

-- 4.3 UPDATE Policy: Row must be owned by the user, and cannot be reassigned to another dispatcher
CREATE POLICY rls_trip_access_update ON security_lab_trip_access
    FOR UPDATE
    TO transit_dispatcher, transit_admin
    USING (
        dispatcher_username IN (CURRENT_USER, SESSION_USER)
        OR pg_has_role(CURRENT_USER, 'transit_admin', 'MEMBER')
        OR pg_has_role(SESSION_USER, 'transit_admin', 'MEMBER')
        OR CURRENT_USER = 'postgres'
    )
    WITH CHECK (
        dispatcher_username IN (CURRENT_USER, SESSION_USER)
        OR pg_has_role(CURRENT_USER, 'transit_admin', 'MEMBER')
        OR pg_has_role(SESSION_USER, 'transit_admin', 'MEMBER')
        OR CURRENT_USER = 'postgres'
    );

DO $$
BEGIN
    RAISE NOTICE '-----------------------------------------------------';
    RAISE NOTICE '[SUCCESS] Row-Level Security successfully configured:';
    RAISE NOTICE '  - Table: security_lab_trip_access (RLS ENABLED, FORCED)';
    RAISE NOTICE '  - Policy rls_trip_access_select: Isolates rows by CURRENT_USER/SESSION_USER';
    RAISE NOTICE '  - Policy rls_trip_access_insert: Enforces WITH CHECK identity validation';
    RAISE NOTICE '  - Policy rls_trip_access_update: Enforces USING + WITH CHECK consistency';
    RAISE NOTICE '=====================================================';
END;
$$;
