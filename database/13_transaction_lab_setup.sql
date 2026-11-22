-- =====================================================================
-- PROJECT: TransitIQ – Intelligent Public Transportation Management
-- FILE: database/13_transaction_lab_setup.sql
-- PURPOSE: Step 10 – Dedicated Isolated Transaction & Concurrency Lab Environment
-- TARGET DATABASE: transitiq_db (PostgreSQL 14+)
-- =====================================================================

-- This script establishes an isolated demonstration environment for testing
-- transactions, isolation levels, row-level locks, race conditions, and deadlocks
-- WITHOUT modifying or depending on the 17 core operational TransitIQ tables.

DO $$
BEGIN
    RAISE NOTICE '=====================================================================';
    RAISE NOTICE 'INITIALIZING TRANSITIQ TRANSACTION LAB ENVIRONMENT';
    RAISE NOTICE '=====================================================================';
END;
$$;

-- ---------------------------------------------------------------------
-- 1. LAB RESOURCE INVENTORY TABLE
-- Used for row-level locking, resource allocation, and race condition tests.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_lab_resources (
    resource_id BIGINT PRIMARY KEY,
    resource_name VARCHAR(100) NOT NULL UNIQUE,
    resource_type VARCHAR(50) NOT NULL CHECK (resource_type IN ('BUS', 'DRIVER', 'ACCOUNT', 'EQUIPMENT')),
    allocation_status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (allocation_status IN ('AVAILABLE', 'LOCKED', 'ALLOCATED', 'MAINTENANCE')),
    allocated_by VARCHAR(50),
    allocated_at TIMESTAMPTZ,
    numeric_value NUMERIC(12,2) DEFAULT 0.00 CHECK (numeric_value >= 0),
    version_number INTEGER NOT NULL DEFAULT 1 CHECK (version_number >= 1)
);

-- ---------------------------------------------------------------------
-- 2. LAB TRANSACTION LOG TABLE
-- Used for atomicity, savepoint, and batch failure demonstrations.
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS transaction_lab_logs (
    log_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    resource_id BIGINT,
    action_type VARCHAR(50) NOT NULL,
    description TEXT,
    logged_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------------------
-- 3. SEED ISOLATED LAB DEMONSTRATION DATA
-- ---------------------------------------------------------------------
INSERT INTO transaction_lab_resources (
    resource_id, resource_name, resource_type, allocation_status,
    allocated_by, allocated_at, numeric_value, version_number
)
VALUES
    (101, 'BUS-LAB-101', 'BUS', 'AVAILABLE', NULL, NULL, 0.00, 1),
    (102, 'BUS-LAB-102', 'BUS', 'AVAILABLE', NULL, NULL, 0.00, 1),
    (201, 'DRIVER-LAB-201', 'DRIVER', 'AVAILABLE', NULL, NULL, 0.00, 1),
    (202, 'DRIVER-LAB-202', 'DRIVER', 'AVAILABLE', NULL, NULL, 0.00, 1),
    (301, 'TRANSIT-CARD-301', 'ACCOUNT', 'AVAILABLE', NULL, NULL, 500.00, 1),
    (302, 'TRANSIT-CARD-302', 'ACCOUNT', 'AVAILABLE', NULL, NULL, 250.00, 1)
ON CONFLICT (resource_id) DO UPDATE SET
    allocation_status = EXCLUDED.allocation_status,
    allocated_by = EXCLUDED.allocated_by,
    allocated_at = EXCLUDED.allocated_at,
    numeric_value = EXCLUDED.numeric_value,
    version_number = EXCLUDED.version_number;

-- Clear any leftover lab logs from prior runs
TRUNCATE TABLE transaction_lab_logs;

DO $$
BEGIN
    RAISE NOTICE '[SUCCESS] Transaction Lab tables and records established successfully.';
    RAISE NOTICE 'Lab Tables created: transaction_lab_resources, transaction_lab_logs';
    RAISE NOTICE 'Operational TransitIQ tables remain 100%% untouched.';
END;
$$;
