# TransitIQ: Transaction Management and Concurrency Control Architecture

## 1. Executive Summary and Architecture Overview

In a metropolitan transit operation such as **TransitIQ**, hundreds of concurrent transactions interact with the operational database every second. Dispatchers assign buses and drivers to schedules, automatic vehicle location (AVL) telemetry systems record trip stop arrivals, fare validator turnstiles stream passenger boarding counts, and maintenance engineers log vehicle inspections.

Without robust transaction management and disciplined concurrency control, concurrent database access inevitably introduces data corruption, race conditions, overbooked vehicles, duplicate driver assignments, and phantom schedules.

This document establishes the transaction engineering principles, locking protocols, multi-version concurrency control (MVCC) behaviors, and isolation semantics implemented across the TransitIQ PostgreSQL 18 engine.

---

## 2. ACID Guarantees in TransitIQ

PostgreSQL guarantees the ACID properties through Write-Ahead Logging (WAL), snapshot-based Multi-Version Concurrency Control (MVCC), and a lock manager.

### 2.1 Atomicity
*All operations within a unit of work either complete successfully or leave the database in its pre-transaction state.*
- **TransitIQ Context**: When a trip is logged via `sp_log_trip_event`, the update to `trips.trip_status`, the insertion into `trip_stop_logs`, the recording of `passenger_counts`, and the automatic generation of `audit_logs` must succeed together. If any check or foreign key constraint fails, the entire transaction rolls back via `ROLLBACK`.
- **Implementation**: Managed via explicit transaction blocks (`BEGIN ... COMMIT / ROLLBACK`) and fine-grained `SAVEPOINT` rollbacks for partial failures without aborting the parent transaction.

### 2.2 Consistency
*Every transaction transitions the database from one valid state to another, maintaining all schema constraints, foreign keys, triggers, and business invariants.*
- **TransitIQ Context**: A bus cannot be scheduled if its maintenance is overdue; a driver cannot be assigned to overlapping trips; passenger counts cannot be negative.
- **Implementation**: Enforced by `CHECK` constraints, foreign keys (`REFERENCES`), unique indexes, and PL/pgSQL validation triggers.

### 2.3 Isolation
*Concurrent transactions execute without interfering with one another or observing incomplete intermediate states.*
- **TransitIQ Context**: A fleet analytics query calculating total route boarding figures while dispatchers insert real-time tap-in records must not see uncommitted boarding counts or half-completed trip stop logs.
- **Implementation**: Configured using PostgreSQL transaction isolation levels: `READ COMMITTED` (default), `REPEATABLE READ` (snapshot isolation), and `SERIALIZABLE` (serializable snapshot isolation).

### 2.4 Durability
*Once a transaction commits, its effects survive system crashes, power failures, or server restarts.*
- **TransitIQ Context**: Once a driver shift completion is committed, the updated `audit_logs` and trip records are written to PostgreSQL WAL before acknowledgment is returned to the client.
- **Implementation**: PostgreSQL Write-Ahead Log (WAL) with `fsync` flush guarantees.

---

## 3. PostgreSQL MVCC (Multi-Version Concurrency Control) Mechanics

PostgreSQL implements MVCC instead of shared read locks:
1. **Readers Never Block Writers**: A `SELECT` query reading `trips` or `passenger_counts` never blocks an `UPDATE` or `INSERT` on the same rows.
2. **Writers Never Block Readers**: An `UPDATE` or `DELETE` modifies rows by creating new tuple versions (with updated `xmin` / `xmax` transaction identifiers), allowing concurrent queries to continue reading the older visible tuple snapshot.
3. **Writers Block Writers**: Two concurrent transactions attempting to `UPDATE` or `DELETE` the same physical row will experience row-level lock contention. The second transaction pauses until the first transaction either `COMMIT`s or `ROLLBACK`s.

---

## 4. Transaction Isolation Levels in PostgreSQL 18

| Phenomenon / Anomaly | ANSI SQL Standard: Read Committed | PostgreSQL: Read Committed | ANSI SQL Standard: Repeatable Read | PostgreSQL: Repeatable Read | PostgreSQL: Serializable |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Dirty Read** | Permitted by standard | **Impossible** (PG MVCC) | Impossible | **Impossible** | **Impossible** |
| **Non-Repeatable Read** | Permitted | **Permitted** | Impossible | **Impossible** | **Impossible** |
| **Phantom Read** | Permitted | **Permitted** | Permitted | **Impossible** (Snapshot) | **Impossible** |
| **Lost Update** | Permitted | **Preventable via Locking** | Impossible (Throws 40001) | **Impossible (Throws 40001)** | **Impossible** |
| **Write Skew** | Permitted | **Permitted** | Permitted | **Permitted** | **Impossible (Throws 40001)** |

### 4.1 Read Committed (Default)
- Each query within the transaction sees a snapshot of data committed **before the query began**, not before the transaction began.
- Consequence: Running the same `SELECT` twice inside the same transaction may return different rows if another transaction committed changes in between (Non-Repeatable Read).

### 4.2 Repeatable Read
- The transaction takes a single snapshot at the start of its **first non-transaction-control statement**. All statements in the transaction see data as of that initial snapshot.
- Phantom reads are prevented: inserting new rows in a concurrent transaction will not appear in subsequent `SELECT` calls.
- Concurrent updates to the same row abort with error `40001: could not serialize access due to concurrent update`.

### 4.3 Serializable (SSI)
- True serializability using Serializable Snapshot Isolation (SSI).
- Detects read-write anti-dependency cycles using non-blocking SIREAD predicate locks.
- Prevents write skew and phantom anomalies without pessimistic table locking. If a cycle is detected, one transaction is aborted with `40001: could not serialize access due to read/write dependencies among transactions`.

---

## 5. Explicit Row-Level Locking Strategies

When building high-concurrency systems, relying solely on isolation levels is insufficient. TransitIQ uses explicit row locking to serialize critical resource modifications:

```sql
-- 1. Exclusive row lock for modification (prevents all other reads-for-update and writes)
SELECT * FROM buses WHERE bus_id = 101 FOR UPDATE;

-- 2. Non-key update lock (allows concurrent foreign-key validations / FOR KEY SHARE)
SELECT * FROM buses WHERE bus_id = 101 FOR NO KEY UPDATE;

-- 3. Non-blocking acquisition (fails immediately with 55P03 if locked)
SELECT * FROM buses WHERE bus_id = 101 FOR UPDATE NOWAIT;

-- 4. Queue / worker processing (skips locked rows, enabling multi-worker parallelism)
SELECT * FROM trips WHERE trip_status = 'SCHEDULED' 
ORDER BY trip_id FOR UPDATE SKIP LOCKED LIMIT 1;
```

---

## 6. Interactive Dual-Session Concurrency Lab (pgAdmin 4)

To observe row locks, lock queues, non-blocking lock skips, lost update prevention, deadlocks, and serializable conflict aborts, run the dual-session SQL scripts in pgAdmin 4.

### 6.1 Setup Instructions
1. Open **pgAdmin 4** and connect to `transitiq_db` on `localhost:5432`.
2. Open a Query Tool window and execute `database/13_transaction_lab_setup.sql`.
3. Open **two independent Query Tool windows** side-by-side:
   - **Window 1 (Session A)**: Open `database/15_concurrency_session_a.sql`.
   - **Window 2 (Session B)**: Open `database/16_concurrency_session_b.sql`.

### 6.2 Step-by-Step Scenario Execution

```mermaid
sequenceDiagram
    autonumber
    actor DispatcherA as Window 1 (Session A)
    actor DispatcherB as Window 2 (Session B)
    participant DB as PostgreSQL 18 (transitiq_db)

    Note over DispatcherA, DispatcherB: Scenario 1: Row Locking & Lock Contention
    DispatcherA->>DB: BEGIN; SELECT ... FOR UPDATE (Resource 1)
    DB-->>DispatcherA: Row locked exclusively
    DispatcherB->>DB: BEGIN; UPDATE Resource 1 ...
    Note right of DispatcherB: BLOCKED! Waiting for Session A
    DispatcherA->>DB: COMMIT;
    DB-->>DispatcherB: Lock released, UPDATE completes
    DispatcherB->>DB: COMMIT;

    Note over DispatcherA, DispatcherB: Scenario 2: Non-Blocking NOWAIT vs SKIP LOCKED
    DispatcherA->>DB: BEGIN; SELECT ... WHERE res_code='RES-BUS-001' FOR UPDATE
    DB-->>DispatcherA: Locked
    DispatcherB->>DB: SELECT ... FOR UPDATE NOWAIT
    DB-->>DispatcherB: ERROR 55P03: could not obtain lock
    DispatcherB->>DB: SELECT ... FOR UPDATE SKIP LOCKED
    DB-->>DispatcherB: Returns RES-BUS-002 immediately!

    Note over DispatcherA, DispatcherB: Scenario 3: Deadlock (40P01)
    DispatcherA->>DB: BEGIN; UPDATE Resource 1 ...
    DispatcherB->>DB: BEGIN; UPDATE Resource 2 ...
    DispatcherA->>DB: UPDATE Resource 2 ... (Blocked waiting for B)
    DispatcherB->>DB: UPDATE Resource 1 ... (Deadlock cycle detected!)
    DB-->>DispatcherB: ERROR 40P01: deadlock detected
    DispatcherA->>DB: Unblocked, UPDATE completes
```

### 6.3 Cleanup
Once interactive verification is finished, execute `database/18_transaction_lab_cleanup.sql` in any query window.

---

## 7. Automated Test Suite (`database/17_transaction_tests.sql`)

The automated test harness runs 15 automated validation test cases in an isolated anonymous PL/pgSQL block:

1. **TEST 1: ACID Atomicity (COMMIT)**: Validates full persistence of atomic multi-table inserts.
2. **TEST 2: ACID Atomicity (ROLLBACK)**: Confirms complete discard of uncommitted changes.
3. **TEST 3: ACID Consistency (CHECK)**: Asserts that invalid states (negative capacities) throw constraint violations.
4. **TEST 4: ACID Durability (WAL Simulated)**: Verifies committed records remain accessible in subsequent blocks.
5. **TEST 5: Partial Rollback via SAVEPOINT**: Verifies successful rollback to savepoint while keeping earlier operations.
6. **TEST 6: Multiple Nested SAVEPOINTs**: Validates multi-level branching and selective rollback.
7. **TEST 7: Exception Recovery (25P02)**: Tests trapping errors in `EXCEPTION` blocks, resetting transaction state cleanly.
8. **TEST 8: Explicit Row Locking (FOR UPDATE)**: Asserts exclusive row lock acquisition.
9. **TEST 9: Non-Key Locking (FOR NO KEY UPDATE)**: Verifies non-key update lock behavior.
10. **TEST 10: Non-Blocking Lock (NOWAIT)**: Validates fast error raising under contention.
11. **TEST 11: Queue Processing (SKIP LOCKED)**: Confirms concurrent worker lock skipping.
12. **TEST 12: Isolation Level - READ COMMITTED**: Asserts standard query-level snapshot visibility.
13. **TEST 13: Isolation Level - REPEATABLE READ**: Tests snapshot isolation and concurrent update detection (40001).
14. **TEST 14: Isolation Level - SERIALIZABLE (SSI)**: Tests SSI conflict detection.
15. **TEST 15: Deadlock Error Handling Simulation (40P01)**: Asserts application-level deadlock catch and retry logic.

---

## 8. Database Administration & Performance Tuning

### 8.1 Key Configuration Parameters for Concurrency
To ensure optimal performance and prevent indefinite transaction blocking:

```ini
# postgresql.conf

# Time before PostgreSQL checks for and breaks deadlock cycles
deadlock_timeout = 1000ms          # Default 1s; recommended 500ms - 1s in high-throughput OLTP

# Max time any statement can wait to acquire a lock
lock_timeout = 5000ms              # Prevents rogue queries from holding lock queues indefinitely

# Max execution duration for any individual statement
statement_timeout = 30000ms        # 30s timeout protects against runaway analytical joins in OLTP

# Max idle time inside an uncommitted transaction block
idle_in_transaction_session_timeout = 60000ms # 1 min timeout terminates abandoned client connections
```

### 8.2 Application-Level Deadlock Retry Protocol
Applications calling TransitIQ stored procedures or executing multi-row updates should implement exponential backoff retry loops targeting `SQLSTATE 40P01` and `SQLSTATE 40001`:

```
MAX_RETRIES = 3
BASE_DELAY_MS = 50

for attempt in 1..MAX_RETRIES:
    try:
        execute_transaction()
        break
    catch DatabaseError as err:
        if err.sqlstate in ('40P01', '40001') and attempt < MAX_RETRIES:
            jittered_sleep(BASE_DELAY_MS * (2 ^ attempt))
            continue
        raise err
```
