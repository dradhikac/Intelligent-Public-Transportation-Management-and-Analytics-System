# TransitIQ: Database Security and Role-Based Access Control Architecture

## 1. Executive Security Architecture

In a critical municipal transportation management system like **TransitIQ**, database security must defend against operational error, credential exposure, unauthorized data exfiltration, identity spoofing, and audit tampering.

The TransitIQ security model is constructed on four foundational pillars:
1. **Role-Based Access Control (RBAC)**: Segregating administrative, operational, maintenance, analytical, and compliance responsibilities into distinct group roles.
2. **Principle of Least Privilege (PoLP)**: Locking down default public access and granting only explicit, minimal schema, table, sequence, and routine privileges.
3. **Row-Level Security (RLS)**: Enforcing fine-grained multi-tenant record isolation using PostgreSQL-native policies with strict `WITH CHECK` validation.
4. **Audit Immutability & Routine Hardening**: Enforcing read-only protection on audit trails and securing `SECURITY DEFINER` routines against `search_path` hijacking.

```mermaid
flowchart TD
    subgraph Users ["Client Connections (LOGIN Users)"]
        D1["test_dispatcher"]
        D2["test_dispatcher_2"]
        FM["test_fleet_manager"]
        DA["test_analyst"]
        AU["test_auditor"]
    end

    subgraph Roles ["Application Group Roles (NOLOGIN)"]
        RD["transit_dispatcher"]
        RFM["transit_fleet_manager"]
        RDA["transit_analyst"]
        RAU["transit_auditor"]
        RAD["transit_admin"]
    end

    subgraph Objects ["Secured Database Assets"]
        OPS["Operational Tables (trips, logs, delay, passenger)"]
        REF["Reference Tables (routes, stops, schedules, drivers)"]
        MAINT["Maintenance Records & Buses"]
        VIEWS["Analytical Views (vw_fleet_summary, vw_route_perf...)"]
        AUDIT["audit_logs (Immutability Enforced)"]
        RLS_TAB["security_lab_trip_access (RLS FORCED)"]
    end

    D1 -->|MEMBER OF| RD
    D2 -->|MEMBER OF| RD
    FM -->|MEMBER OF| RFM
    DA -->|MEMBER OF| RDA
    AU -->|MEMBER OF| RAU

    RD -->|SELECT, INSERT, UPDATE| OPS
    RD -->|SELECT| REF
    RD -->|RLS Isolated Access| RLS_TAB

    RFM -->|SELECT, INSERT, UPDATE| MAINT
    RFM -->|UPDATE (status, last_service_date)| MAINT

    RDA -->|SELECT ONLY| VIEWS
    RDA -->|SELECT ONLY| REF

    RAU -->|SELECT ONLY| AUDIT
    RAU -->|SELECT Cross-checks| OPS

    RAD -->|DML| OPS
    RAD -->|DML| REF
    RAD -->|DML| MAINT
    RAD -->|SELECT ONLY| AUDIT
```

---

## 2. Role Hierarchy and Inheritance Architecture

PostgreSQL unifies users and groups into the concept of **Roles**. TransitIQ strictly separates **NOLOGIN Group Roles** (which hold permission grants) from **LOGIN User Accounts** (which authenticate and inherit permissions).

### 2.1 Group Roles (`NOLOGIN`, `INHERIT`)
| Role Name | Category | Scope & Responsibility |
| :--- | :--- | :--- |
| `transit_admin` | Administrative | Manages application objects, performs schema migrations, and configures operational parameters. **Not a PostgreSQL superuser**. |
| `transit_dispatcher` | Operational | Schedules trips, manages stop logs, records passenger boardings, logs service delays, and monitors route performance. |
| `transit_fleet_manager` | Fleet & Depot | Manages bus assets, inspects vehicle condition, updates service dates, and schedules maintenance work orders. |
| `transit_analyst` | BI & Reporting | Read-only access to consolidated analytical views and reporting functions. Zero write permissions to operational tables. |
| `transit_auditor` | Compliance | Read-only inspection of security audit trails (`audit_logs`) and cross-referencing operational events. Cannot alter or delete logs. |

### 2.2 Security Configuration of Test Accounts
All user accounts are provisioned with hardened defaults:
```sql
CREATE ROLE test_dispatcher WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION INHERIT;
```
- **No Superuser Rights**: No application account can bypass access checks or write-ahead logging.
- **No Creation Rights**: Application users cannot alter database structures, spawn new roles, or create databases.
- **Inheritance Enabled**: Privileges flow transparently from the assigned group role.

---

## 3. Least Privilege Permission Matrix

Default PostgreSQL permissions in `public` schema grant `CREATE` and routine execution to `PUBLIC`. TransitIQ explicitly executes a **Public Schema Lockdown**:

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
```

### Complete Object Permission Matrix

| Table / Object Name | `transit_admin` | `transit_dispatcher` | `transit_fleet_manager` | `transit_analyst` | `transit_auditor` |
| :--- | :---: | :---: | :---: | :---: | :---: |
| `bus_types` | ALL | SELECT | SELECT | SELECT | — |
| `buses` | ALL | SELECT | SELECT, UPDATE* | SELECT | SELECT |
| `maintenance_records` | ALL | — | SELECT, INSERT, UPDATE | — | SELECT |
| `routes` | ALL | SELECT | SELECT | SELECT | — |
| `stops` | ALL | SELECT | — | SELECT | — |
| `route_stops` | ALL | SELECT | — | SELECT | — |
| `drivers` | ALL | SELECT | — | SELECT | SELECT |
| `schedules` | ALL | SELECT | — | SELECT | — |
| `operating_days` | ALL | SELECT | — | SELECT | — |
| `schedule_operating_days` | ALL | SELECT | — | SELECT | — |
| `schedule_stop_times` | ALL | SELECT | — | — | — |
| `trips` | ALL | SELECT, INSERT, UPDATE | — | — | SELECT |
| `trip_stop_logs` | ALL | SELECT, INSERT, UPDATE | — | — | — |
| `passenger_counts` | ALL | SELECT, INSERT, UPDATE | — | — | SELECT |
| `delay_reasons` | ALL | SELECT | — | SELECT | — |
| `delay_records` | ALL | SELECT, INSERT, UPDATE | — | — | SELECT |
| `audit_logs` | **SELECT ONLY** | — | — | — | **SELECT ONLY** |
| **All 5 Analytical Views** | SELECT | SELECT (Partial) | SELECT (Fleet) | **SELECT ALL** | — |
| **Operational Procedures** | EXECUTE | EXECUTE | — | — | — |
| **Analytical Functions** | EXECUTE | EXECUTE | EXECUTE | EXECUTE | — |

*\*Note: `transit_fleet_manager` holds column-level UPDATE on `buses (status, last_service_date)` only.*

---

## 4. Audit Log Immutability Policy

Data integrity requires that audit records cannot be altered or purged by application roles:
1. **Write Prevention**: No application role (including `transit_admin`) holds `INSERT`, `UPDATE`, or `DELETE` grants on `audit_logs`.
2. **Trigger-Only Ingestion**: Inserts into `audit_logs` occur strictly via the `SECURITY DEFINER` trigger function `fn_audit_changes()`.
3. **Tampering Defense**: Direct `UPDATE` or `DELETE` attempts by users or dispatchers fail with `ERROR 42501: permission denied for table audit_logs`.

---

## 5. SECURITY DEFINER Hardening & search_path Protection

When a function executes as `SECURITY DEFINER`, it runs with the privileges of the function's owner (typically `postgres`). If the function does not lock its `search_path`, a malicious user can create a temporary table or function (e.g. `to_jsonb`) in a user-controlled schema, causing privilege escalation.

TransitIQ enforces explicit `search_path` lockdown on all trigger routines:
```sql
ALTER FUNCTION fn_audit_changes() SET search_path = public, pg_temp;
ALTER FUNCTION fn_auto_classify_delay() SET search_path = public, pg_temp;
ALTER FUNCTION fn_sync_bus_maintenance_date() SET search_path = public, pg_temp;
```

---

## 6. Row-Level Security (RLS) Architecture

Row-Level Security restricts the rows visible or modifiable in a table based on the executing user identity.

### 6.1 `CURRENT_USER` vs `SESSION_USER`
- **`SESSION_USER`**: The identity of the authenticated database client connection. It remains unchanged even if the session calls a `SECURITY DEFINER` routine.
- **`CURRENT_USER`**: The current contextual execution identity. It shifts temporarily to the owner when inside a `SECURITY DEFINER` function, or changes when executing `SET ROLE`.
- **TransitIQ Policy Rule**: To ensure full compatibility with both direct client logins and administrative `SET ROLE` testing harnesses, our policies evaluate:
  ```sql
  (dispatcher_username IN (CURRENT_USER, SESSION_USER)
   OR pg_has_role(CURRENT_USER, 'transit_admin', 'MEMBER')
   OR pg_has_role(SESSION_USER, 'transit_admin', 'MEMBER')
   OR CURRENT_USER = 'postgres')
  ```

### 6.2 `WITH CHECK` Integrity Defense
A dispatcher cannot insert a row containing another dispatcher's username (`dispatcher_username = 'test_dispatcher_2'`). The `WITH CHECK` clause validates incoming tuples, throwing:
```text
ERROR: 23514: new row violates row-level security policy for table "security_lab_trip_access"
```

### 6.3 `FORCE ROW LEVEL SECURITY`
In PostgreSQL, the table owner normally bypasses RLS policies. TransitIQ applies `FORCE ROW LEVEL SECURITY` so that the policies apply uniformly to owners and application roles alike.

---

## 7. Security Auditing: Application vs PostgreSQL Server

It is critical to distinguish between application-level audit logging and database engine auditing:

| Audit Layer | Scope | Mechanism in TransitIQ | Capabilities |
| :--- | :--- | :--- | :--- |
| **Application Audit Triggers** | DML on business tables | `audit_logs` + `fn_audit_changes()` | Captures `INSERT`, `UPDATE`, `DELETE`, previous/new JSONB payloads, timestamps, and usernames. Does not record `SELECT`. |
| **PostgreSQL Engine Logging** | Server & connection events | `log_connections`, `log_disconnections`, `log_min_messages` | Logs connection attempts, authentication failures, and syntax/permission errors in server logs. |
| **pgaudit Extension** *(Optional)* | Deep query-level auditing | PostgreSQL `pgaudit` extension | Captures read queries (`SELECT`) and DDL execution at the engine level for SOC2/HIPAA compliance. |

---

## 8. Database Administration & Production Guidelines

1. **Password Authentication**: Production passwords must be configured using `SCRAM-SHA-256`. Never commit credentials to version control.
2. **Network Protection**: Bind PostgreSQL only to private VPC interfaces (`listen_addresses = '10.x.x.x'`) or local sockets (`localhost`).
3. **Role Switching in pgAdmin**: In pgAdmin 4 Query Tool, execute `SET ROLE <role_name>;` to simulate permissions, followed by `RESET ROLE;` to return to administrative privilege.
