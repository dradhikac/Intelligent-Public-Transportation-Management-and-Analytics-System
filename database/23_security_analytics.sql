-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/23_security_analytics.sql
-- PURPOSE: Step 11 – Security & RBAC Configuration Analytics Queries
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- DESCRIPTION:
--   Analytical DBA queries to audit database roles, memberships, table grants,
--   routine execution permissions, RLS status, and SECURITY DEFINER hardening.
-- =====================================================================

-- =====================================================================
-- 1. ROLE INVENTORY & ATTRIBUTES AUDIT
-- Purpose: Inspect all TransitIQ group roles and test login users,
--          verifying NOSUPERUSER and credential policies.
-- =====================================================================
SELECT
    r.rolname AS role_name,
    r.rolcanlogin AS can_login,
    r.rolsuper AS is_superuser,
    r.rolcreaterole AS can_create_role,
    r.rolcreatedb AS can_create_db,
    r.rolinherit AS inherits_privileges,
    r.rolreplication AS can_replicate,
    r.rolconnlimit AS connection_limit,
    CASE
        WHEN r.rolname LIKE 'transit_%' THEN 'Application Group Role'
        WHEN r.rolname LIKE 'test_%' THEN 'Test Login Account'
        ELSE 'System / Internal Role'
    END AS role_category
FROM pg_roles r
WHERE r.rolname IN (
    'transit_admin', 'transit_dispatcher', 'transit_fleet_manager',
    'transit_analyst', 'transit_auditor',
    'test_dispatcher', 'test_dispatcher_2', 'test_fleet_manager',
    'test_analyst', 'test_auditor'
)
ORDER BY role_category, r.rolname;


-- =====================================================================
-- 2. ROLE MEMBERSHIP HIERARCHY AUDIT
-- Purpose: Map parent group roles to their assigned member accounts.
-- =====================================================================
SELECT
    parent.rolname AS group_role,
    member.rolname AS member_user,
    admin_opt.admin_option AS can_grant_further
FROM pg_auth_members admin_opt
JOIN pg_roles parent ON admin_opt.roleid = parent.oid
JOIN pg_roles member ON admin_opt.member = member.oid
WHERE parent.rolname LIKE 'transit_%'
ORDER BY parent.rolname, member.rolname;


-- =====================================================================
-- 3. OPERATIONAL TABLE PRIVILEGES MATRIX
-- Purpose: Cross-tabulation of table permissions across TransitIQ roles.
-- =====================================================================
SELECT
    grantee,
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) AS granted_privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('transit_admin', 'transit_dispatcher', 'transit_fleet_manager', 'transit_analyst', 'transit_auditor', 'PUBLIC')
GROUP BY grantee, table_name
ORDER BY table_name, grantee;


-- =====================================================================
-- 4. ANALYTICAL VIEWS PERMISSION AUDIT
-- Purpose: Confirm view access is granted to analysts/dispatchers while
--          denied from unauthorized roles.
-- =====================================================================
SELECT
    table_name AS view_name,
    grantee,
    privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name LIKE 'vw_%'
  AND grantee IN ('transit_admin', 'transit_dispatcher', 'transit_fleet_manager', 'transit_analyst', 'transit_auditor')
ORDER BY view_name, grantee;


-- =====================================================================
-- 5. STORED PROCEDURES & FUNCTIONS EXECUTE PRIVILEGES
-- Purpose: Verify least-privilege routine execution grants.
-- =====================================================================
SELECT
    routine_name,
    routine_type,
    grantee,
    privilege_type
FROM information_schema.routine_privileges
WHERE specific_schema = 'public'
  AND grantee IN ('transit_admin', 'transit_dispatcher', 'transit_fleet_manager', 'transit_analyst', 'transit_auditor')
ORDER BY routine_name, grantee;


-- =====================================================================
-- 6. SECURITY DEFINER ROUTINES HARDENING AUDIT
-- Purpose: Ensure all SECURITY DEFINER functions have a locked search_path
--          to prevent search_path escalation vulnerabilities.
-- =====================================================================
SELECT
    p.proname AS function_name,
    pg_get_userbyid(p.proowner) AS function_owner,
    p.prosecdef AS is_security_definer,
    COALESCE(array_to_string(p.proconfig, ', '), 'UNRESTRICTED (VULNERABLE)') AS configuration_settings
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND (p.proname LIKE 'fn_%' OR p.proname LIKE 'sp_%')
ORDER BY is_security_definer DESC, p.proname;


-- =====================================================================
-- 7. ROW-LEVEL SECURITY (RLS) STATUS AUDIT
-- Purpose: List all tables in public schema with RLS enabled and forced.
-- =====================================================================
SELECT
    c.relname AS table_name,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced,
    pg_get_userbyid(c.relowner) AS table_owner
FROM pg_class c
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND (c.relname LIKE 'security_lab_%' OR c.relrowsecurity = TRUE)
ORDER BY c.relname;


-- =====================================================================
-- 8. ACTIVE ROW-LEVEL SECURITY POLICIES AUDIT
-- Purpose: Inspect all configured RLS policies, commands, and predicates.
-- =====================================================================
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual AS using_expression,
    with_check AS with_check_expression
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;


-- =====================================================================
-- 9. AUDIT LOG IMMUTABILITY & PROTECTION AUDIT
-- Purpose: Verify that NO application role possesses write/truncate rights
--          on the security-critical audit_logs table.
-- =====================================================================
SELECT
    grantee,
    privilege_type,
    is_grantable
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'audit_logs'
ORDER BY grantee, privilege_type;
