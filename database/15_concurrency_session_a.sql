-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/15_concurrency_session_a.sql
-- PURPOSE: Step 10 – Two-Session Concurrency Demonstrations (SESSION A)
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- INSTRUCTIONS FOR PGADMIN 4:
-- 1. Open pgAdmin 4 and connect to transitiq_db.
-- 2. Open Query Tool Window 1 (Title: SESSION A). Open this file.
-- 3. Open Query Tool Window 2 (Title: SESSION B). Open database/16_concurrency_session_b.sql.
-- 4. Follow the numbered steps sequentially across Session A and Session B.

-- =====================================================================
-- SCENARIO 1: ROW-LEVEL LOCKING (SELECT ... FOR UPDATE)
-- Demonstrates how a row lock blocks concurrent conflicting updates.
-- =====================================================================

-- STEP A1: Start transaction in Session A and lock Bus 101
BEGIN;
SELECT resource_id, resource_name, allocation_status
FROM transaction_lab_resources
WHERE resource_id = 101
FOR UPDATE;

-- Notice: An Exclusive Row Lock is now held on resource 101 by Session A.
-- NOW GO TO SESSION B (STEP B1): Session B will attempt to update resource 101 and will WAIT.

-- STEP A2: Inspect your locked row, perform the update, and COMMIT
UPDATE transaction_lab_resources
SET allocation_status = 'ALLOCATED', allocated_by = 'Dispatcher_Alpha'
WHERE resource_id = 101;

COMMIT;
-- Notice: Upon COMMIT, Session A releases the lock. Watch Session B immediately unblock!


-- =====================================================================
-- SCENARIO 2: NON-BLOCKING LOCKS (NOWAIT AND SKIP LOCKED)
-- Demonstrates fail-fast and queue-skipping concurrency patterns.
-- =====================================================================

-- STEP A3: Acquire and hold lock on Resource 101
BEGIN;
SELECT resource_id, resource_name
FROM transaction_lab_resources
WHERE resource_id = 101
FOR UPDATE;

-- NOW GO TO SESSION B (STEP B2):
-- Session B will attempt `FOR UPDATE NOWAIT` (fails fast with 55P03).
-- Then Session B will attempt `SKIP LOCKED` (skips row 101 and locks row 102 instantly).

-- STEP A4: Release the lock
ROLLBACK;


-- =====================================================================
-- SCENARIO 3: LOST UPDATE DEMONSTRATION & PROTECTION
-- Demonstrates how concurrent naive read-modify-writes cause data loss,
-- and how atomic expressions protect data consistency.
-- =====================================================================

-- STEP A5: Reset Account 301 balance to Rs 500.00
UPDATE transaction_lab_resources SET numeric_value = 500.00, version_number = 1 WHERE resource_id = 301;

-- STEP A6: Session A reads current balance (Rs 500.00) into application memory
BEGIN;
SELECT numeric_value FROM transaction_lab_resources WHERE resource_id = 301;
-- Application logic: wants to deposit Rs 100.00 (calculates 500 + 100 = 600 in memory)

-- NOW GO TO SESSION B (STEP B3): Session B will read Rs 500 and deposit Rs 50 (500 + 50 = 550) and COMMIT.

-- STEP A7: Session A writes its stale calculated value (Rs 600.00)
-- Without concurrency control, this overwrites Session B's deposit of Rs 50!
UPDATE transaction_lab_resources
SET numeric_value = 600.00
WHERE resource_id = 301;
COMMIT;

-- Verify the lost update: Balance is 600.00 instead of 650.00 (Session B's deposit was LOST!)
SELECT resource_id, numeric_value AS lost_update_result FROM transaction_lab_resources WHERE resource_id = 301;

-- STEP A8: PROPER SOLUTION (Atomic in-database calculation)
-- Reset and demonstrate correct atomic execution
UPDATE transaction_lab_resources SET numeric_value = 500.00 WHERE resource_id = 301;

BEGIN;
-- Atomic update: directly references the database column
UPDATE transaction_lab_resources
SET numeric_value = numeric_value + 100.00
WHERE resource_id = 301;
COMMIT;


-- =====================================================================
-- SCENARIO 4: DEADLOCK DETECTION AND AUTOMATIC RESOLUTION
-- Demonstrates mutual circular blocking and PostgreSQL's deadlock detector.
-- =====================================================================

-- Ensure both lab resources are available
UPDATE transaction_lab_resources SET allocation_status = 'AVAILABLE' WHERE resource_id IN (101, 201);

-- STEP A9: Session A acquires lock on Resource 1 (Bus 101)
BEGIN;
SELECT resource_id, resource_name FROM transaction_lab_resources WHERE resource_id = 101 FOR UPDATE;

-- NOW GO TO SESSION B (STEP B4): Session B will lock Resource 2 (Driver 201).

-- STEP A10: Session A now requests lock on Resource 2 (Driver 201)
-- Session A enters WAITING state because Session B holds Driver 201.
SELECT resource_id, resource_name FROM transaction_lab_resources WHERE resource_id = 201 FOR UPDATE;

-- NOW GO TO SESSION B (STEP B5): Session B will request Resource 1 (Bus 101).
-- This creates a circular dependency:
-- Session A waits for B, Session B waits for A.
-- PostgreSQL detects the deadlock and aborts one transaction with SQLSTATE 40P01.

-- STEP A11: Cleanup/Rollback if Session A was the aborted victim or survived
ROLLBACK;


-- =====================================================================
-- SCENARIO 5: NON-REPEATABLE READS VS SNAPSHOT ISOLATION
-- Demonstrates difference between READ COMMITTED and REPEATABLE READ.
-- =====================================================================

-- Reset Fare Card 301 balance
UPDATE transaction_lab_resources SET numeric_value = 500.00 WHERE resource_id = 301;

-- Part 1: READ COMMITTED (Non-Repeatable Read occurs)
BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED;
-- Query 1 in Session A sees 500.00
SELECT resource_id, numeric_value AS query1_balance FROM transaction_lab_resources WHERE resource_id = 301;

-- NOW GO TO SESSION B (STEP B6): Session B will update Card 301 to 750.00 and COMMIT.

-- Query 2 in Session A (SAME transaction) now sees 750.00! (Result changed mid-transaction)
SELECT resource_id, numeric_value AS query2_balance FROM transaction_lab_resources WHERE resource_id = 301;
COMMIT;

-- Part 2: REPEATABLE READ (Snapshot is stable)
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
-- Query 1 in Session A sees 750.00
SELECT resource_id, numeric_value AS snap1_balance FROM transaction_lab_resources WHERE resource_id = 301;

-- NOW GO TO SESSION B (STEP B7): Session B will update Card 301 to 900.00 and COMMIT.

-- Query 2 in Session A still sees 750.00! Snapshot isolation preserves consistency!
SELECT resource_id, numeric_value AS snap2_balance FROM transaction_lab_resources WHERE resource_id = 301;
COMMIT;

-- After COMMIT, new query sees the committed 900.00:
SELECT resource_id, numeric_value AS final_balance FROM transaction_lab_resources WHERE resource_id = 301;
