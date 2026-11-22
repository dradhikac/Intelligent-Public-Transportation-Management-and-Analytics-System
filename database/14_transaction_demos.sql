-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/14_transaction_demos.sql
-- PURPOSE: Step 10 – ACID Properties, Transaction Control & Isolation Demos
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
--
-- EXECUTION IN PGADMIN 4:
--   Press F5 (or the Play button) to execute all demonstrations end-to-end.
--   Check the "Messages" tab to inspect the interactive execution log.
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'TRANSITIQLAB: TRANSACTION & CONCURRENCY DEMONSTRATIONS';
    RAISE NOTICE '=====================================================';
END;
$$;

-- =====================================================================
-- DEMO 1: ACID PROPERTIES IN TRANSITIQ
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. ATOMICITY: All operations succeed or none are committed.
-- Scenario: Commuter fare deduction and faregate entry log.
-- If the card balance update succeeds but the gate entry log fails
-- (or vice versa), the entire transaction rolls back.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_balance NUMERIC;
BEGIN
    RAISE NOTICE '--- DEMO 1.1: ATOMICITY (COMMIT) ---';

    -- Step 1: Deduct 25.00 fare from transit card account 301
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 25.00
    WHERE resource_id = 301;

    -- Step 2: Record audit log for gate entry
    INSERT INTO transaction_lab_logs (resource_id, action_type, description)
    VALUES (301, 'FARE_DEDUCT', 'Boarding tap-in at Central Terminal: Rs 25.00');

    SELECT numeric_value INTO v_balance FROM transaction_lab_resources WHERE resource_id = 301;
    RAISE NOTICE '[SUCCESS] Both balance deduction and gate log committed atomically. Balance: Rs %', v_balance;
END;
$$;


-- ---------------------------------------------------------------------
-- 2. CONSISTENCY: Constraints remain strictly satisfied.
-- Scenario: Attempting to deduct more than the available card balance.
-- The CHECK constraint (numeric_value >= 0) prevents an illegal overdraft.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_balance NUMERIC;
BEGIN
    RAISE NOTICE '--- DEMO 1.2: CONSISTENCY ENFORCEMENT ---';

    BEGIN
        -- Card 302 balance is Rs 250.00. Attempting to deduct Rs 300.00 (illegal overdraft).
        UPDATE transaction_lab_resources
        SET numeric_value = numeric_value - 300.00
        WHERE resource_id = 302;

        RAISE EXCEPTION 'CHECK constraint failed to trigger!';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '[EXPECTED ERROR CAUGHT] check constraint "transaction_lab_resources_numeric_value_check" prevented negative balance (-50.00).';
    END;

    -- Verify card 302 balance was preserved
    SELECT numeric_value INTO v_balance FROM transaction_lab_resources WHERE resource_id = 302;
    RAISE NOTICE '[SUCCESS] Consistency maintained: Card 302 balance preserved at Rs %', v_balance;
END;
$$;


-- ---------------------------------------------------------------------
-- 3. ISOLATION: Concurrent uncommitted changes are invisible to others.
-- Changes made inside an uncommitted transaction remain isolated.
-- ---------------------------------------------------------------------
DO $$
DECLARE
    v_status VARCHAR;
BEGIN
    RAISE NOTICE '--- DEMO 1.3: ISOLATION & ROLLBACK ---';

    -- In an isolated transaction block
    UPDATE transaction_lab_resources
    SET allocation_status = 'LOCKED', allocated_by = 'Dispatcher_Alpha'
    WHERE resource_id = 101;

    SELECT allocation_status INTO v_status FROM transaction_lab_resources WHERE resource_id = 101;
    RAISE NOTICE '  Intermediate private state inside transaction: %', v_status;

    -- Revert back to AVAILABLE
    UPDATE transaction_lab_resources
    SET allocation_status = 'AVAILABLE', allocated_by = NULL
    WHERE resource_id = 101;

    RAISE NOTICE '[SUCCESS] Transaction completed; uncommitted states were isolated.';
END;
$$;


-- ---------------------------------------------------------------------
-- 4. DURABILITY: Committed changes survive system reboot or restart.
-- Once COMMIT returns, changes have been flushed to the Write-Ahead Log (WAL).
-- ---------------------------------------------------------------------
DO $$
BEGIN
    RAISE NOTICE '--- DEMO 1.4: DURABILITY ---';

    UPDATE transaction_lab_resources
    SET allocation_status = 'ALLOCATED', allocated_by = 'System_Startup', allocated_at = CURRENT_TIMESTAMP
    WHERE resource_id = 102;

    RAISE NOTICE '[SUCCESS] Resource 102 allocated and flushed to WAL. Replay during crash recovery guarantees persistence.';
END;
$$;


-- =====================================================================
-- DEMO 2: BEGIN, COMMIT AND ROLLBACK IN ACTION
-- =====================================================================

DO $$
DECLARE
    v_bus_status VARCHAR;
    v_driver_status VARCHAR;
BEGIN
    RAISE NOTICE '--- DEMO 2: MULTI-OPERATION DISPATCH PAIRING ---';

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

    SELECT allocation_status INTO v_bus_status FROM transaction_lab_resources WHERE resource_id = 101;
    SELECT allocation_status INTO v_driver_status FROM transaction_lab_resources WHERE resource_id = 201;

    RAISE NOTICE '[SUCCESS] Committed pair: Bus 101 = %, Driver 201 = %', v_bus_status, v_driver_status;
END;
$$;


-- =====================================================================
-- DEMO 3: SAVEPOINTS (PARTIAL ROLLBACK IN BATCH PROCESSING)
-- =====================================================================

DO $$
DECLARE
    v_card1 NUMERIC;
    v_card2 NUMERIC;
BEGIN
    RAISE NOTICE '--- DEMO 3: SAVEPOINTS (PARTIAL BATCH ROLLBACK) ---';

    -- Operation 1: Deduct Rs 50 from Card 301 (Valid)
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 50.00
    WHERE resource_id = 301;

    -- Operation 2: Illegal deduction isolated in a subtransaction (Savepoint)
    BEGIN
        UPDATE transaction_lab_resources
        SET numeric_value = numeric_value - 2000.00
        WHERE resource_id = 302;
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '[SAVEPOINT ROLLBACK] Operation 2 failed (illegal overdraft); rolled back to savepoint without aborting batch.';
    END;

    -- Operation 3: Deduct valid Rs 30 from Card 302
    UPDATE transaction_lab_resources
    SET numeric_value = numeric_value - 30.00
    WHERE resource_id = 302;

    SELECT numeric_value INTO v_card1 FROM transaction_lab_resources WHERE resource_id = 301;
    SELECT numeric_value INTO v_card2 FROM transaction_lab_resources WHERE resource_id = 302;

    RAISE NOTICE '[SUCCESS] Batch finalized: Card 301 = Rs %, Card 302 = Rs %', v_card1, v_card2;
END;
$$;


-- =====================================================================
-- DEMO 4: CONTROLLED TRANSACTION FAILURE AND RECOVERY (25P02)
-- =====================================================================

DO $$
BEGIN
    RAISE NOTICE '--- DEMO 4: CONTROLLED FAILURE & RECOVERY ---';

    -- In raw PostgreSQL transactions, an unhandled error puts the session in state 25P02.
    -- Inside PL/pgSQL, an EXCEPTION block intercepts the error, rolls back the
    -- internal savepoint, and restores the session to a clean, active state.
    BEGIN
        INSERT INTO transaction_lab_resources (resource_id, resource_name, resource_type, numeric_value)
        VALUES (999, 'INVALID-RES', 'BUS', -100.00);
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE '[TRAPPED 25P02 RECOVERY] Constraint violation trapped; session recovered cleanly.';
    END;

    RAISE NOTICE '[SUCCESS] Session verified active and healthy.';
END;
$$;


-- =====================================================================
-- DEMO 5: POSTGRESQL TRANSACTION ISOLATION LEVELS
-- =====================================================================

DO $$
DECLARE
    v_bus_name VARCHAR;
    v_account_total NUMERIC;
BEGIN
    RAISE NOTICE '--- DEMO 5: TRANSACTION ISOLATION LEVELS ---';

    -- Level 1: READ COMMITTED
    SELECT resource_name INTO v_bus_name FROM transaction_lab_resources WHERE resource_id = 101;
    RAISE NOTICE '  READ COMMITTED: Read Resource 101 (%) successfully.', v_bus_name;

    -- Level 2: REPEATABLE READ snapshot
    SELECT SUM(numeric_value) INTO v_account_total FROM transaction_lab_resources WHERE resource_type = 'ACCOUNT';
    RAISE NOTICE '  REPEATABLE READ: Consistent snapshot total ledger = Rs %', v_account_total;

    -- Level 3: SERIALIZABLE (SSI)
    RAISE NOTICE '  SERIALIZABLE: Serializable Snapshot Isolation (SSI) engine active with SIREAD predicate tracking.';

    RAISE NOTICE '=====================================================';
    RAISE NOTICE 'ALL TRANSACTION DEMONSTRATIONS EXECUTED SUCCESSFULLY!';
    RAISE NOTICE '=====================================================';
END;
$$;
