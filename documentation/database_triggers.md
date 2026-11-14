# TransitIQ – Database Triggers & Automated Operations Documentation

**Project**: TransitIQ – Intelligent Public Transportation Management and Analytics System  
**Engine**: PostgreSQL 18 (Compatible with PostgreSQL 14+)  
**Database**: `transitiq_db`  
**Module**: Event-Driven Database Triggers & Automated Auditing  
**Scripts**:
- `database/10_triggers.sql` (Audit and automation triggers)
- `database/11_trigger_tests.sql` (15 automated test suites)
- `database/12_audit_analytics.sql` (Audit inspection and analytics queries)

---

## 1. Trigger Fundamentals & Architecture

### What is a Database Trigger?
A **database trigger** is a special procedure automatically invoked by the PostgreSQL engine whenever a specific data modification event (`INSERT`, `UPDATE`, `DELETE`, or `TRUNCATE`) occurs on a target table or view. Triggers allow TransitIQ to enforce business invariants, capture point-in-time audit trails, and synchronize interrelated entities without relying solely on application-level code.

### BEFORE vs AFTER Triggers

| Feature | `BEFORE` Triggers | `AFTER` Triggers |
| :--- | :--- | :--- |
| **Execution Point** | Fires *before* the proposed row mutation is written to the table or checked against constraints. | Fires *after* the row mutation is committed to the table buffer and verified by constraints. |
| **Data Modification** | Can inspect and **modify `NEW` record values** in place before write (e.g. assigning calculated severity). | Cannot modify `NEW` or `OLD`. The row write is already completed. |
| **Return Requirement** | Must return `NEW` (to proceed), `NULL` (to silently cancel the operation), or raise an exception. | Return value is ignored (conventionally `RETURN NULL;`). |
| **TransitIQ Use Case** | `trg_auto_classify_delay`: Automatically calculates `NEW.severity` before writing to `delay_records`. | `trg_audit_*`: Captures final committed `OLD` and `NEW` row states into `audit_logs`. |

### Row-Level vs Statement-Level Triggers
- **Row-Level (`FOR EACH ROW`)**: Executes once for *every individual row* affected by the query. Essential for row-level auditing, capturing before/after JSONB snapshots, and row-level data validation.
- **Statement-Level (`FOR EACH STATEMENT`)**: Executes once per SQL statement regardless of how many rows are touched. Ideal for batch summary logging or security alerts.
- *TransitIQ Standard*: All audit and classification triggers in TransitIQ are **Row-Level (`FOR EACH ROW`)** to preserve full forensic data fidelity.

---

## 2. Trigger Execution Lifecycle in PostgreSQL

```text
Incoming SQL Statement (e.g. INSERT INTO delay_records)
   │
   ▼
1. BEFORE Statement Triggers fire
   │
   ▼
2. FOR EACH ROW:
   ├─► Execute BEFORE Row Triggers (trg_auto_classify_delay)
   │   └─ Validates delay_seconds, calls fn_calculate_delay_severity(), sets NEW.severity
   │
   ├─► Check Table Constraints (NOT NULL, CHECK, UNIQUE, FOREIGN KEY)
   │
   ├─► Write Row to Table Storage
   │
   └─► Execute AFTER Row Triggers (trg_audit_delay_records)
       └─ Calls fn_audit_changes(), extracts PK, saves JSONB to audit_logs
   │
   ▼
3. Check Deferrable Constraints
   │
   ▼
4. AFTER Statement Triggers fire
   │
   ▼
Transaction Commit / End
```

---

## 3. Generic Audit Function (`fn_audit_changes`)

### Design Architecture
Instead of writing duplicate trigger functions for each table, TransitIQ employs a single, consolidated **Generic Audit Function** (`fn_audit_changes()`).

```sql
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
    -- Prevent recursive auditing
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

    -- Dynamic Primary Key Resolution
    v_record_id := CASE TG_TABLE_NAME
        WHEN 'buses'               THEN COALESCE((v_new_data->>'bus_id')::BIGINT, (v_old_data->>'bus_id')::BIGINT)
        WHEN 'drivers'             THEN COALESCE((v_new_data->>'driver_id')::BIGINT, (v_old_data->>'driver_id')::BIGINT)
        WHEN 'trips'               THEN COALESCE((v_new_data->>'trip_id')::BIGINT, (v_old_data->>'trip_id')::BIGINT)
        WHEN 'passenger_counts'    THEN COALESCE((v_new_data->>'passenger_count_id')::BIGINT, (v_old_data->>'passenger_count_id')::BIGINT)
        WHEN 'delay_records'       THEN COALESCE((v_new_data->>'delay_id')::BIGINT, (v_old_data->>'delay_id')::BIGINT)
        WHEN 'maintenance_records' THEN COALESCE((v_new_data->>'maintenance_id')::BIGINT, (v_old_data->>'maintenance_id')::BIGINT)
        ELSE NULL
    END;

    INSERT INTO audit_logs (
        table_name, record_id, operation,
        old_data, new_data, changed_at, changed_by
    )
    VALUES (
        TG_TABLE_NAME, v_record_id, TG_OP,
        v_old_data, v_new_data, CURRENT_TIMESTAMP, SESSION_USER
    );

    RETURN NULL;
END;
$$;
```

### JSONB Audit Schema
The `audit_logs` table schema is strictly respected without altering columns:
- `audit_id`: `BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY`
- `table_name`: `VARCHAR(100)` (e.g. `'buses'`, `'trips'`, `'drivers'`)
- `record_id`: `BIGINT` (Extracted entity primary key)
- `operation`: `'INSERT'`, `'UPDATE'`, or `'DELETE'`
- `old_data`: `JSONB` (Previous state on UPDATE/DELETE, `NULL` on INSERT)
- `new_data`: `JSONB` (New state on INSERT/UPDATE, `NULL` on DELETE)
- `changed_at`: `TIMESTAMPTZ` (Current transaction timestamp)
- `changed_by`: `VARCHAR(100)` (Active database session user)

---

## 4. Audit Triggers on Core Tables

The generic audit function is attached to **6 mission-critical operational tables**:

| Table | Trigger Name | Timing & Event | Monitored Data |
| :--- | :--- | :--- | :--- |
| **`buses`** | `trg_audit_buses` | `AFTER INSERT OR UPDATE OR DELETE` | Status changes, reassignments, maintenance flag transitions |
| **`drivers`** | `trg_audit_drivers` | `AFTER INSERT OR UPDATE OR DELETE` | License renewals, availability status, profile edits |
| **`trips`** | `trg_audit_trips` | `AFTER INSERT OR UPDATE OR DELETE` | Trip scheduling, start/end timestamps, cancellations |
| **`passenger_counts`** | `trg_audit_passenger_counts` | `AFTER INSERT OR UPDATE OR DELETE` | Telemetry adjustments, boardings/alightings changes |
| **`delay_records`** | `trg_audit_delay_records` | `AFTER INSERT OR UPDATE OR DELETE` | Delay logging, duration updates, reason corrections |
| **`maintenance_records`** | `trg_audit_maintenance` | `AFTER INSERT OR UPDATE OR DELETE` | Repair logging, cost adjustments, status transitions |

All triggers use `DROP TRIGGER IF EXISTS ...; CREATE TRIGGER ...` to guarantee idempotent execution.

---

## 5. Automated Business Operations Triggers

### 1. Automatic Delay Severity Classification (`trg_auto_classify_delay`)
- **Table**: `delay_records`
- **Timing**: `BEFORE INSERT OR UPDATE OF delay_seconds`
- **Function**: `fn_auto_classify_delay()`
- **Mechanism**:
  1. Inspects `NEW.delay_seconds`.
  2. Rejects negative values with `check_violation`.
  3. Calls the existing business function `fn_calculate_delay_severity(NEW.delay_seconds)`.
  4. Directly mutates `NEW.severity` in place.
- **Benefit**: Ensures that whether data arrives via automated CAD/AVL pipelines, stored procedures (`sp_record_delay`), or direct raw SQL `INSERT` statements, the severity classification (`MINOR`, `MODERATE`, `SEVERE`) is mathematically guaranteed to be accurate and consistent.

### 2. Maintenance Service Date Synchronization (`trg_sync_bus_maintenance_date`)
- **Table**: `maintenance_records`
- **Timing**: `AFTER INSERT OR UPDATE OF maintenance_status, maintenance_date`
- **Function**: `fn_sync_bus_maintenance_date()`
- **Mechanism**:
  When a maintenance record is saved with `maintenance_status = 'COMPLETED'`, the trigger automatically synchronizes `buses.last_service_date = GREATEST(last_service_date, NEW.maintenance_date)`.
- **Benefit**: Eliminates desynchronization between historical repair logs and current fleet operational status.

---

## 6. Audit Analytics & Inspection (`database/12_audit_analytics.sql`)

The audit layer provides 7 pre-built queries to extract forensic insights:

1. **Latest 20 Audit Events**: Formatted log displaying timestamp, user, table, operation, and JSONB payload.
2. **Operations by Table**: Breakdown of insertions, updates, and deletions per table with percentage shares.
3. **Global Mutation Activity**: System-wide volume split between INSERT, UPDATE, and DELETE.
4. **Lifecycle Audit of a Bus**: Chronological log reconstructing a specific vehicle's status and service history.
5. **Driver History Audit**: Tracks driver status changes, roster adjustments, and license renewals.
6. **Passenger Count Adjustments**: Forensic delta analysis `(new_boardings - old_boardings)` auditing sensor data corrections.
7. **Delay Severity Transitions**: Monitors operational delay edits and severity adjustments.

---

## 7. Testing & Verification Plan (`database/11_trigger_tests.sql`)

The test suite covers **15 end-to-end automated scenarios**:
- **Tests 1–3**: Bus INSERT, UPDATE, and DELETE audit logging.
- **Tests 4–5**: Driver INSERT and UPDATE audit logging.
- **Tests 6–7**: Trip creation and status transition auditing.
- **Tests 8–9**: Passenger count insertion and update auditing.
- **Tests 10–12**: Auto-classification of delays across tiers (200s -> MINOR, 450s -> MODERATE, 750s -> SEVERE).
- **Test 13**: Automatic severity recalculation when updating delay seconds.
- **Test 14**: Rejection of negative delay duration by BEFORE trigger.
- **Test 15**: Maintenance record audit logging and automatic `buses.last_service_date` synchronization.

*All test scenarios clean up their temporary test records and audit entries, leaving the database state pristine.*
