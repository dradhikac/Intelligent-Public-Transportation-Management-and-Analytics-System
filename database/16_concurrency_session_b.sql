-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/16_concurrency_session_b.sql
-- PURPOSE: Step 10 – Two-Session Concurrency Demonstrations (SESSION B)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- INSTRUCTIONS FOR PGADMIN 4:
-- 1. Open pgAdmin 4 and connect to transitiq_db.
-- 2. This is Query Tool Window 2 (Title: SESSION B).
-- 3. Execute the corresponding steps in coordination with Session A.

-- =====================================================================
-- SCENARIO 1: ROW-LEVEL LOCKING (LOCK WAIT DEMONSTRATION)
-- =====================================================================

-- STEP B1: Attempt to allocate Bus 101 while Session A holds the lock
-- RUN THIS AFTER STEP A1 HAS EXECUTED IN SESSION A:
BEGIN;
UPDATE transaction_lab_resources
SET allocation_status = 'ALLOCATED', allocated_by = 'Dispatcher_Beta'
WHERE resource_id = 101;

-- Notice: This statement will PAUSE/HANG in pgAdmin ("Executing query...").
-- It is blocked waiting for Session A's exclusive lock to be released.
-- RETURN TO SESSION A AND RUN STEP A2 (COMMIT).
-- As soon as Session A commits, this query finishes executing!
COMMIT;

-- Verify that Session B's allocation succeeded after Session A finished:
SELECT resource_id, resource_name, allocation_status, allocated_by
FROM transaction_lab_resources WHERE resource_id = 101;


-- =====================================================================
-- SCENARIO 2: NON-BLOCKING LOCKS (NOWAIT AND SKIP LOCKED)
-- =====================================================================

-- STEP B2: Run this while Session A is holding the lock in Step A3
BEGIN;

-- Attempt 1: NOWAIT fails immediately instead of blocking the user or application thread
-- SELECT resource_id FROM transaction_lab_resources WHERE resource_id = 101 FOR UPDATE NOWAIT;
-- ==> Yields: ERROR: could not obtain lock on row in relation "transaction_lab_resources" (SQLSTATE 55P03)

-- Attempt 2: SKIP LOCKED bypasses the locked row and grabs the next available bus!
SELECT resource_id, resource_name, allocation_status
FROM transaction_lab_resources
WHERE resource_type = 'BUS' AND allocation_status <> 'ALLOCATED'
ORDER BY resource_id
FOR UPDATE SKIP LOCKED
LIMIT 1;
-- Notice: Row 101 was locked by Session A, so PostgreSQL smoothly skipped it and returned Row 102!
COMMIT;


-- =====================================================================
-- SCENARIO 3: LOST UPDATE DEMONSTRATION
-- =====================================================================

-- STEP B3: Run this after Session A has read 500.00 in Step A6
-- Session B reads current balance (500.00) and adds 50.00
BEGIN;
SELECT numeric_value FROM transaction_lab_resources WHERE resource_id = 301;

UPDATE transaction_lab_resources
SET numeric_value = 550.00
WHERE resource_id = 301;
COMMIT;
-- Now return to Session A and run Step A7.


-- =====================================================================
-- SCENARIO 4: DEADLOCK TRIGGER DEMONSTRATION
-- =====================================================================

-- STEP B4: Run this after Session A has locked Resource 1 in Step A9.
-- Session B acquires lock on Resource 2 (Driver 201)
BEGIN;
SELECT resource_id, resource_name FROM transaction_lab_resources WHERE resource_id = 201 FOR UPDATE;

-- NOW RETURN TO SESSION A AND RUN STEP A10 (Session A requests Driver 201 and hangs).

-- STEP B5: Session B now requests Resource 1 (Bus 101).
-- Circular lock wait created: Session A waits on B, Session B waits on A!
SELECT resource_id, resource_name FROM transaction_lab_resources WHERE resource_id = 101 FOR UPDATE;

-- RESULT OBSERVED IN PGADMIN:
-- After approx 1 second (deadlock_timeout), PostgreSQL detects the circular wait:
-- "ERROR: deadlock detected" (SQLSTATE 40P01)
-- "DETAIL: Process XXX waits for ShareLock on transaction ...; blocked by process YYY."

-- Step B5b: Rollback the aborted transaction in Session B
ROLLBACK;


-- =====================================================================
-- SCENARIO 5: ISOLATION LEVEL UPDATES (COORDINATION WITH SESSION A)
-- =====================================================================

-- STEP B6: Update Card 301 during Session A's READ COMMITTED transaction
BEGIN;
UPDATE transaction_lab_resources SET numeric_value = 750.00 WHERE resource_id = 301;
COMMIT;
-- Now return to Session A Part 1 query 2.

-- STEP B7: Update Card 301 during Session A's REPEATABLE READ transaction
BEGIN;
UPDATE transaction_lab_resources SET numeric_value = 900.00 WHERE resource_id = 301;
COMMIT;
-- Now return to Session A Part 2 query 2.


-- =====================================================================
-- SCENARIO 6: SERIALIZATION FAILURE (SQLSTATE 40001) IN SERIALIZABLE
-- =====================================================================

-- When two concurrent transactions read overlapping sets and perform updates,
-- SERIALIZABLE detects an anti-dependency cycle and aborts one transaction.

-- Step B8a: Session B begins SERIALIZABLE
BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE;
-- Read accounts
SELECT SUM(numeric_value) FROM transaction_lab_resources WHERE resource_type = 'ACCOUNT';

-- Deduct from Card 302
UPDATE transaction_lab_resources SET numeric_value = numeric_value - 50.00 WHERE resource_id = 302;
COMMIT;
