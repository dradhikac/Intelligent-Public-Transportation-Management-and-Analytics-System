# TransitIQ: Database Backup, Recovery and Disaster Recovery Validation Report

**Author**: Senior PostgreSQL Database Administrator & Disaster Recovery Engineer  
**Date**: November 2026  
**Target Engine**: PostgreSQL 18.x on Windows  
**Primary Database**: `transitiq_db`  
**Test Recovery Database**: `transitiq_recovery_test`  
**Milestone**: Step 13 – Database Backup, Recovery and Disaster Recovery  

---

## 1. Executive Summary

This report establishes the disaster recovery readiness and validation results for **Step 13: Database Backup, Recovery and Disaster Recovery** of the TransitIQ database platform.

To rigorously demonstrate backup and recovery capabilities without compromising production integrity:
- **Zero Production Overwrite**: Restorations were strictly directed into an isolated target database (`transitiq_recovery_test`). The primary operational database `transitiq_db` was never overwritten or modified.
- **Dual-Stream Backup Architecture**: Both logical backups (`pg_dump` in custom, plain, schema-only, and data-only formats) and physical cluster backups (`pg_basebackup` with SHA-256 manifests) were developed and validated.
- **15-Checkpoint Relational Integrity Suite**: Restored objects, constraints, procedures, views, and data tuples were asserted via [32_restore_validation.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/32_restore_validation.sql).
- **Git Security Compliance**: All backup archives and temporary dump directories are strictly ignored in `.gitignore` to prevent committing live data or credentials to version control.

---

## 2. Inventory of DR Deliverables

| File Path | Deliverable Category | Purpose |
| :--- | :--- | :--- |
| `database/31_backup_validation.sql` | Pre-Backup Inspection | Audits database size, live tuple counts, active sessions, and WAL LSN positions. |
| `database/32_restore_validation.sql` | Post-Restore QA Suite | 15-checkpoint validation harness verifying restored tables, views, procedures, and referential integrity. |
| `scripts/backup_transitiq.ps1` | Logical Backup Script | Parameterized PowerShell script generating custom (`-Fc`), plain (`-Fp`), schema (`-s`), and data (`-a`) dumps. |
| `scripts/restore_transitiq.ps1` | Restore Orchestrator | Parameterized restore script with production-overwrite protection and selective table restore capability. |
| `scripts/validate_backup.ps1` | Validation Runner | Automates archive TOC inspection and runs the 15-checkpoint SQL verification suite. |
| `scripts/physical_backup.ps1` | Physical Backup Script | Executes `pg_basebackup` with WAL streaming (`-X stream`) and cryptographic SHA-256 manifest verification. |
| `documentation/backup_recovery.md` | Technical Reference | Deep dive into dump formats, selective table recovery, physical backups, and 5-step PITR procedures. |
| `documentation/disaster_recovery_plan.md` | DR Strategy Plan | Enterprise DR plan establishing RPO, RTO, GFS retention policies, runbooks, and incident matrices. |
| `documentation/backup_validation_report.md` | QA Validation Report | This DBA sign-off and verification documentation. |

---

## 3. Environment Inspection & Baseline Metrics

- **Database Engine**: PostgreSQL 18 running on `localhost:5432` (`postgresql-x64-18` Windows Service).
- **Binary Directory**: `C:\Program Files\PostgreSQL\18\bin` (`pg_dump.exe`, `pg_restore.exe`, `psql.exe`, `pg_basebackup.exe`, `pg_verifybackup.exe`).
- **Primary Database**: `transitiq_db` (~8.5 MB total database size including template relations).
- **Operational Data Footprint**: 17 core relational tables, 5 analytical views, 3 procedures, 9 functions, 8 triggers.
- **WAL Configuration**: `wal_level = replica`, WAL segment size = 16 MB.

---

## 4. Logical Backup Formats Generated & Evaluated

The automated backup orchestrator [backup_transitiq.ps1](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/scripts/backup_transitiq.ps1) produces four distinct backup formats under `backups/`:

| Backup Format | Flag | Filename Pattern | Compression | Characteristics |
| :--- | :---: | :--- | :---: | :--- |
| **Custom Format** | `-Fc` | `transitiq_db_custom_<timestamp>.dump` | ZLIB Built-in | Fast, flexible, supports parallel `-j` restore and selective `-t` extraction. **Standard DR choice**. |
| **Plain-Text SQL** | `-Fp` | `transitiq_db_plain_<timestamp>.sql` | None | Human-readable DDL + COPY commands. Ideal for auditing and schema migrations. |
| **Schema-Only** | `-s` | `transitiq_db_schema_only_<timestamp>.sql` | None | DDL structure of all 17 tables, views, and functions without tuple data. |
| **Data-Only** | `-a` | `transitiq_db_data_only_<timestamp>.sql` | None | Raw COPY streams with trigger disable flags for bulk seeding. |

---

## 5. 15-Checkpoint Restoration Validation Results (`32_restore_validation.sql`)

The restore suite was executed against the isolated target database `transitiq_recovery_test`:

| Checkpoint ID | Verification Target | Assertion Criteria | Status |
| :---: | :--- | :--- | :---: |
| **CHK 01** | 17 Core Tables | All 17 operational tables verified present in `public` schema. | **PASS** |
| **CHK 02** | 5 Analytical Views | All 5 analytical views (`vw_*`) present and queryable. | **PASS** |
| **CHK 03** | Stored Procedures | `sp_create_trip`, `sp_record_passenger_count`, `sp_record_delay` restored. | **PASS** |
| **CHK 04** | Analytical Functions | All 9 functions (`fn_*`) restored with matching argument signatures. | **PASS** |
| **CHK 05** | Trigger Automation | All 8 audit and maintenance triggers verified in catalog. | **PASS** |
| **CHK 06** | Primary Keys | Primary keys verified across all 17 tables (17+ PK constraints). | **PASS** |
| **CHK 07** | Foreign Keys | Referential foreign keys verified across all tables (15+ FK constraints). | **PASS** |
| **CHK 08** | Performance Indexes | Performance B-tree, partial, and covering indexes verified (18+ indexes). | **PASS** |
| **CHK 09** | Fleet Inventory Data | Vehicle assets (`buses`, `bus_types`) verified restored. | **PASS** |
| **CHK 10** | Transit Network Data | Stops and route geometries (`routes`, `stops`, `route_stops`) restored. | **PASS** |
| **CHK 11** | Operational Trips | Dispatch records (`trips`, `trip_stop_logs`) verified restored. | **PASS** |
| **CHK 12** | Passenger Telemetry | Footfall counts (`passenger_counts`) verified restored. | **PASS** |
| **CHK 13** | Referential Integrity | Zero orphaned records detected across foreign key relationships. | **PASS** |
| **CHK 14** | View Queryability | Analytical views execute cleanly with non-zero query outputs. | **PASS** |
| **CHK 15** | Audit Trail Records | Security audit log history (`audit_logs`) verified restored. | **PASS** |

### Validation Harness Log Output
```text
NOTICE:  =====================================================
NOTICE:  TRANSITIQLAB: STARTING RESTORATION VALIDATION SUITE
NOTICE:  CURRENT TARGET DATABASE: transitiq_recovery_test
NOTICE:  =====================================================
NOTICE:  [PASS] CHK 01: All 17 core operational tables successfully verified in target database
NOTICE:  [PASS] CHK 02: All 5 analytical views present and verified
NOTICE:  [PASS] CHK 03: All 3 operational stored procedures successfully restored
NOTICE:  [PASS] CHK 04: All 9 analytical functions successfully restored
NOTICE:  [PASS] CHK 05: All 8 audit and automation triggers successfully verified
NOTICE:  [PASS] CHK 06: Primary key constraints intact across all tables (17 PKs)
NOTICE:  [PASS] CHK 07: Foreign key relationships intact across all tables (16 FKs)
NOTICE:  [PASS] CHK 08: Performance and structural indexes verified (23 indexes)
NOTICE:  [PASS] CHK 09: Fleet inventory restored (10 buses, 4 bus types)
NOTICE:  [PASS] CHK 10: Transit network restored (5 routes, 20 stops)
NOTICE:  [PASS] CHK 11: Operational records restored (14 trips, 60 stop logs)
NOTICE:  [PASS] CHK 12: Passenger telemetry restored (60 logs, 1423 cumulative boardings)
NOTICE:  [PASS] CHK 13: Referential integrity verified (0 orphaned trip records)
NOTICE:  [PASS] CHK 14: Analytical views execute successfully (vw_fleet: 10, vw_route: 5)
NOTICE:  [PASS] CHK 15: Audit trail verified (22 audit log entries restored)
NOTICE:  =====================================================
NOTICE:  RESTORATION VALIDATION COMPLETE: ALL 15 CHECKPOINTS PASSED!
NOTICE:  =====================================================
```

---

## 6. Point-in-Time Recovery (PITR) & Physical Backup Readiness

- **Physical Cluster Ingestion**: [physical_backup.ps1](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/scripts/physical_backup.ps1) automates `pg_basebackup` with `-X stream` WAL streaming.
- **Cryptographic Verification**: Integrates `pg_verifybackup` against the generated `backup_manifest`, computing SHA-256 checksums to verify block consistency.
- **Continuous Archiving Architecture**: The disaster recovery plan details continuous WAL spooling via `archive_command`, supporting Recovery Point Objectives (RPO) $\le 15 \text{ minutes}$.

---

## 7. Operational Data Safety Confirmation

- **Primary Database Intact**: `transitiq_db` was maintained online throughout all backup and restore testing without alteration or truncation.
- **Zero Schema Bleed**: Restore operations strictly targeted `transitiq_recovery_test`.
- **Git Security**: Backup files are prevented from entering version control via `.gitignore`.

---

## 8. PowerShell & pgAdmin 4 Execution Guide

### 8.1 Executing Logical Backups (PowerShell)
```powershell
# Set password for session (if not using .pgpass)
$env:PGPASSWORD = "your_postgres_password"

# Run full backup suite (Custom, Plain, Schema, Data)
cd d:\Intelligent-Public-Transportation-Management-and-Analytics-System\scripts
.\backup_transitiq.ps1 -BackupFormat All
```

### 8.2 Executing Safe Restoration Test (PowerShell)
```powershell
# Restores latest backup into isolated transitiq_recovery_test database
.\restore_transitiq.ps1 -BackupFile "..\backups\transitiq_db_custom_<timestamp>.dump" -RecreateDatabase
```

### 8.3 Executing Backup & Restoration Validation (PowerShell)
```powershell
# Runs TOC checks and the 15-checkpoint SQL validation suite
.\validate_backup.ps1 -TargetDatabase "transitiq_recovery_test"
```

### 8.4 In pgAdmin 4
- Open **pgAdmin 4** and connect to `transitiq_db` to run [31_backup_validation.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/31_backup_validation.sql).
- Switch the active database connection to `transitiq_recovery_test` to execute [32_restore_validation.sql](file:///d:/Intelligent-Public-Transportation-Management-and-Analytics-System/database/32_restore_validation.sql).
