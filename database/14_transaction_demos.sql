-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/14_transaction_demos.sql
-- PURPOSE: Step 10 – ACID Properties, Transaction Control & Isolation Demos
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- =====================================================================
-- DEMO 1: ACID PROPERTIES IN TRANSITIQ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ATOMICITY: All operations succeed or none are committed.
-- Scenario: Commuter fare deduction and faregate entry log.
-- If the card balance update succeeds but the gate entry log fails
-- (or vice versa), the entire transaction rolls back.
-- ---------------------------------------------------------------------
-- A. Successful Atomic Unit:
BEGIN;
    -- Step 1: Deduct 25.00 fare from transit card account 301
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 25.00
    WHERE resource_id = 301;

    -- Step 2: Record audit log for gate entry
    INSERT INTO transaction_lab_logs (resource_id, action_type, description)
    VALUES (301, 'FARE_DEDUCT', 'Boarding tap-in at Central Terminal: Rs 25.00');
COMMIT;

-- Verify both records committed together
SELECT resource_id, numeric_value FROM transaction_lab_resources WHERE resource_id = 301;
SELECT * FROM transaction_lab_logs WHERE resource_id = 301 ORDER BY log_id DESC LIMIT 1;


-- ---------------------------------------------------------------------
-- 2. CONSISTENCY: Constraints remain strictly satisfied.
-- Scenario: Attempting to deduct more than the available card balance.
-- The CHECK constraint (numeric_value >= 0) stops an overdraft.
-- ---------------------------------------------------------------------
BEGIN;
    -- Card 302 balance is Rs 250.00. Attempting to deduct Rs 300.00.
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 300.00
    WHERE resource_id = 302;
    -- ERROR: check constraint "transaction_lab_resources_numeric_value_check" violated
ROLLBACK;

-- Verify card 302 balance was preserved at Rs 250.00
SELECT resource_id, numeric_value FROM transaction_lab_resources WHERE resource_id = 302;


-- ---------------------------------------------------------------------
-- 3. ISOLATION: Concurrent uncommitted changes are invisible to others.
-- Changes made inside this transaction block remain private until COMMIT.
-- ---------------------------------------------------------------------
BEGIN;
    UPDATE transaction_lab_resources
    SET allocation_status = 'LOCKED', allocated_by = 'Dispatcher_Alpha'
    WHERE resource_id = 101;

    -- In this session, status is 'LOCKED':
    SELECT resource_id, allocation_status, allocated_by
    FROM transaction_lab_resources WHERE resource_id = 101;
ROLLBACK; -- Discard changes; other sessions never saw intermediate 'LOCKED' state


-- ---------------------------------------------------------------------
-- 4. DURABILITY: Committed changes survive system reboot or restart.
-- Once COMMIT returns, changes have been flushed to the Write-Ahead Log (WAL).
-- ---------------------------------------------------------------------
BEGIN;
    UPDATE transaction_lab_resources
    SET allocation_status = 'ALLOCATED', allocated_by = 'System_Startup'
    WHERE resource_id = 102;
COMMIT;
-- Even if the server crashes right now, WAL replay during crash recovery guarantees persistence.


-- =====================================================================
-- DEMO 2: BEGIN, COMMIT AND ROLLBACK IN ACTION
-- =====================================================================

-- ---------------------------------------------------------------------
-- A. Multi-Operation Commited Transaction
-- ---------------------------------------------------------------------
BEGIN;
    -- Allocate Bus 101
    UPDATE transaction_lab_resources
    SET allocation_status = 'ALLOCATED', allocated_by = 'Dispatcher_North', allocated_at = CURRENT_TIMESTAMP
    WHERE resource_id = 101;

    -- Allocate Driver 201
    UPDATE transaction_lab_resources
    SET allocation_status = 'ALLOCATED', allocated_by = 'Dispatcher_North', allocated_at = CURRENT_TIMESTAMP
    WHERE resource_id = 201;

    -- Insert Dispatch Log
    INSERT INTO transaction_lab_logs (resource_id, action_type, description)
    VALUES (101, 'DISPATCH_PAIR', 'Allocated Bus 101 with Driver 201 for Express Run');
COMMIT;

-- Verify committed allocations
SELECT resource_id, resource_name, allocation_status, allocated_by
FROM transaction_lab_resources WHERE resource_id IN (101, 201);


-- ---------------------------------------------------------------------
-- B. Multi-Operation Rolled Back Transaction
-- ---------------------------------------------------------------------
BEGIN;
    -- Attempt allocation
    UPDATE transaction_lab_resources
    SET allocation_status = 'MAINTENANCE', allocated_by = 'Depot_Mechanic'
    WHERE resource_id = 101;

    -- Inspector decides bus does not need maintenance today -> Discard
ROLLBACK;

-- Verify state remained 'ALLOCATED' (previous committed state preserved)
SELECT resource_id, resource_name, allocation_status, allocated_by
FROM transaction_lab_resources WHERE resource_id = 101;


-- =====================================================================
-- DEMO 3: SAVEPOINTS (PARTIAL ROLLBACK IN BATCH PROCESSING)
-- =====================================================================

-- Real-World Use Case: A transit fare server processes a batch of 3 ticket deductions.
-- Record 1 succeeds.
-- Record 2 attempts an illegal negative deduction (fails).
-- The system rolls back only to the savepoint before Record 2, allowing
-- Record 1 and Record 3 to commit successfully without restarting the whole batch.

BEGIN;
    -- Operation 1: Deduct Rs 50 from Card 301
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 50.00
    WHERE resource_id = 301;

    SAVEPOINT sp_after_op1;

    -- Operation 2: Illegal deduction (attempting to set negative value)
    -- In a real batch pipeline, before causing an unrecoverable failure,
    -- or when recovering in a PL/pgSQL subtransaction:
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 2000.00
    WHERE resource_id = 302; -- Would violate check constraint if not validated

    -- Revert Operation 2 without aborting Operation 1
    ROLLBACK TO SAVEPOINT sp_after_op1;

    -- Operation 3: Deduct valid Rs 30 from Card 302
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 30.00
    WHERE resource_id = 302;

    -- Commit Operation 1 and Operation 3
COMMIT;

-- Verify results: Card 301 deducted by 50, Card 302 deducted by 30
SELECT resource_id, resource_name, numeric_value
FROM transaction_lab_resources WHERE resource_id IN (301, 302);


-- =====================================================================
-- DEMO 4: CONTROLLED TRANSACTION FAILURE AND RECOVERY
-- =====================================================================

-- When a SQL error occurs in PostgreSQL, the transaction enters an aborted state:
-- "ERROR: current transaction is aborted, commands ignored until end of transaction block"
-- (SQLSTATE 25P02). All subsequent commands are rejected until ROLLBACK is executed.

BEGIN;
    -- Step 1: Valid statement
    UPDATE transaction_lab_resources
    SET allocation_status = 'LOCKED'
    WHERE resource_id = 101;

    -- Step 2: Statement causing constraint violation
    -- INSERT into lab resources with negative numeric_value
    -- INSERT INTO transaction_lab_resources (resource_id, resource_name, resource_type, numeric_value)
    -- VALUES (999, 'INVALID-RES', 'BUS', -100.00);
    -- ==> Causes ERROR: 23514 check constraint violation

    -- Step 3: Any query here will fail with SQLSTATE 25P02
    -- SELECT * FROM transaction_lab_resources; -- FAILS: transaction is aborted!

    -- Step 4: Issue ROLLBACK to clean up aborted state
ROLLBACK;

-- Now session is back in a healthy, clean state:
SELECT 'Session restored to clean state' AS status;


-- =====================================================================
-- DEMO 5: POSTGRESQL TRANSACTION ISOLATION LEVELS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Level 1: READ COMMITTED (Default in PostgreSQL)
-- Each statement sees only data committed before that statement began.
-- Consecutive SELECTs within the same transaction can see different results
-- if another transaction commits in between (Non-Repeatable Read).
-- ---------------------------------------------------------------------
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
    SELECT resource_id, resource_name, allocation_status FROM transaction_lab_resources WHERE resource_id = 101;
    -- If Session B updates and commits resource 101 here,
    -- the next SELECT in this same transaction will see the updated value!
COMMIT;


-- ---------------------------------------------------------------------
-- Level 2: REPEATABLE READ
-- Transaction sees a static snapshot of the database taken at the start of the transaction's
-- first query. Consecutive SELECTs always return identical results.
-- NOTE: Unlike standard ANSI SQL, PostgreSQL's MVCC implementation of REPEATABLE READ
-- ALSO PREVENTS PHANTOM READS!
-- However, if this transaction attempts to UPDATE a row that another concurrent
-- transaction modified and committed, PostgreSQL aborts with:
-- "ERROR: could not serialize access due to concurrent update" (SQLSTATE 40001).
-- ---------------------------------------------------------------------
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    SELECT resource_id, resource_name, numeric_value FROM transaction_lab_resources WHERE resource_id = 301;
    -- Subsequent SELECTs will always return the exact same snapshot, even if Session B commits an update.
COMMIT;


-- ---------------------------------------------------------------------
-- Level 3: SERIALIZABLE (Serializable Snapshot Isolation - SSI)
-- Guarantees that any concurrent set of committed transactions produces the
-- exact same outcome as if they executed strictly one after another (serially).
-- Uses SIREAD (predicate) locks in memory.
-- If PostgreSQL detects a dangerous rw-antidependency cycle, it aborts one transaction with:
-- "ERROR: could not serialize access due to read/write dependencies among transactions" (SQLSTATE 40001).
-- The application must catch 40001 and retry the transaction.
-- ---------------------------------------------------------------------
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
    SELECT SUM(numeric_value) AS total_ledger FROM transaction_lab_resources WHERE resource_type = 'ACCOUNT';
COMMIT;
