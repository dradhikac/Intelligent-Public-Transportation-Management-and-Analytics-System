-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/19_security_roles.sql
-- PURPOSE: Step 11 – Role-Based Access Control (RBAC) Architecture
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- SECURITY ARCHITECTURE:
--   1. GROUP ROLES (NOLOGIN, INHERIT):
--      - transit_admin: Administrative management of application schema objects
--      - transit_dispatcher: Real-time trip, schedule, and passenger dispatch
--      - transit_fleet_manager: Bus inventory and depot maintenance management
--      - transit_analyst: Read-only reporting and analytical view queries
--      - transit_auditor: Compliance monitoring and audit trail inspection
--
--   2. TEST LOGIN USERS (LOGIN, NOINHERIT/INHERIT):
--      - test_dispatcher: Member of transit_dispatcher
--      - test_fleet_manager: Member of transit_fleet_manager
--      - test_analyst: Member of transit_analyst
--      - test_auditor: Member of transit_auditor
--      - test_dispatcher_2: Secondary dispatcher for RLS tenant isolation tests
--
-- SAFETY & CREDENTIAL POLICY:
--   - Reusable plaintext production passwords are NEVER committed to Git.
--   - Test users are created without superuser, createdb, or createrole privileges.
--   - Script is idempotent and safely re-runnable.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: INITIALIZING SECURITY & RBAC ROLES';
    RAISE NOTICE '=====================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- 1. DEFINE APPLICATION GROUP ROLES (NOLOGIN)
-- ---------------------------------------------------------------------

DO $$
BEGIN
    -- 1.1 transit_admin
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'transit_admin') THEN
        CREATE ROLE transit_admin
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOLOGIN
            INHERIT;
        RAISE NOTICE '[CREATED] Group Role: transit_admin';
    ELSE
        RAISE NOTICE '[EXISTS]  Group Role: transit_admin';
    END IF;

    -- 1.2 transit_dispatcher
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'transit_dispatcher') THEN
        CREATE ROLE transit_dispatcher
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOLOGIN
            INHERIT;
        RAISE NOTICE '[CREATED] Group Role: transit_dispatcher';
    ELSE
        RAISE NOTICE '[EXISTS]  Group Role: transit_dispatcher';
    END IF;

    -- 1.3 transit_fleet_manager
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'transit_fleet_manager') THEN
        CREATE ROLE transit_fleet_manager
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOLOGIN
            INHERIT;
        RAISE NOTICE '[CREATED] Group Role: transit_fleet_manager';
    ELSE
        RAISE NOTICE '[EXISTS]  Group Role: transit_fleet_manager';
    END IF;

    -- 1.4 transit_analyst
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'transit_analyst') THEN
        CREATE ROLE transit_analyst
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOLOGIN
            INHERIT;
        RAISE NOTICE '[CREATED] Group Role: transit_analyst';
    ELSE
        RAISE NOTICE '[EXISTS]  Group Role: transit_analyst';
    END IF;

    -- 1.5 transit_auditor
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'transit_auditor') THEN
        CREATE ROLE transit_auditor
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            NOLOGIN
            INHERIT;
        RAISE NOTICE '[CREATED] Group Role: transit_auditor';
    ELSE
        RAISE NOTICE '[EXISTS]  Group Role: transit_auditor';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- 2. DEFINE TEST LOGIN USERS (LOGIN)
-- ---------------------------------------------------------------------
-- NOTE: In production environments, passwords should be set via external
-- secret managers or scram-sha-256 tokens. For local development & testing,
-- unprivileged accounts are configured below without superuser rights.
-- ---------------------------------------------------------------------

DO $$
BEGIN
    -- 2.1 test_dispatcher
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_dispatcher') THEN
        CREATE ROLE test_dispatcher
            WITH LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            INHERIT;
        RAISE NOTICE '[CREATED] Login User: test_dispatcher';
    ELSE
        RAISE NOTICE '[EXISTS]  Login User: test_dispatcher';
    END IF;

    -- 2.2 test_dispatcher_2 (for multi-tenant RLS isolation testing)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_dispatcher_2') THEN
        CREATE ROLE test_dispatcher_2
            WITH LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            INHERIT;
        RAISE NOTICE '[CREATED] Login User: test_dispatcher_2';
    ELSE
        RAISE NOTICE '[EXISTS]  Login User: test_dispatcher_2';
    END IF;

    -- 2.3 test_fleet_manager
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_fleet_manager') THEN
        CREATE ROLE test_fleet_manager
            WITH LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            INHERIT;
        RAISE NOTICE '[CREATED] Login User: test_fleet_manager';
    ELSE
        RAISE NOTICE '[EXISTS]  Login User: test_fleet_manager';
    END IF;

    -- 2.4 test_analyst
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_analyst') THEN
        CREATE ROLE test_analyst
            WITH LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            INHERIT;
        RAISE NOTICE '[CREATED] Login User: test_analyst';
    ELSE
        RAISE NOTICE '[EXISTS]  Login User: test_analyst';
    END IF;

    -- 2.5 test_auditor
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'test_auditor') THEN
        CREATE ROLE test_auditor
            WITH LOGIN
            NOSUPERUSER
            NOCREATEDB
            NOCREATEROLE
            NOREPLICATION
            INHERIT;
        RAISE NOTICE '[CREATED] Login User: test_auditor';
    ELSE
        RAISE NOTICE '[EXISTS]  Login User: test_auditor';
    END IF;
END;
$$;


-- ---------------------------------------------------------------------
-- 3. GRANT ROLE MEMBERSHIPS (INHERITANCE)
-- ---------------------------------------------------------------------

GRANT transit_dispatcher TO test_dispatcher;
GRANT transit_dispatcher TO test_dispatcher_2;
GRANT transit_fleet_manager TO test_fleet_manager;
GRANT transit_analyst TO test_analyst;
GRANT transit_auditor TO test_auditor;

DO $$
BEGIN
    RAISE NOTICE '-----------------------------------------------------';
    RAISE NOTICE '[SUCCESS] Role memberships mapped:';
    RAISE NOTICE '  - test_dispatcher   -> transit_dispatcher';
    RAISE NOTICE '  - test_dispatcher_2 -> transit_dispatcher';
    RAISE NOTICE '  - test_fleet_manager-> transit_fleet_manager';
    RAISE NOTICE '  - test_analyst      -> transit_analyst';
    RAISE NOTICE '  - test_auditor      -> transit_auditor';
    RAISE NOTICE '=====================================================';
END;
$$;
