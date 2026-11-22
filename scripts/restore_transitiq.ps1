<#
.SYNOPSIS
    TransitIQ Database Disaster Recovery & Restore Utility.
.DESCRIPTION
    Safely restores a TransitIQ backup into a dedicated target recovery database
    (Default: 'transitiq_recovery_test').
    CRITICAL SAFETY PROTOCOL: Strictly rejects restoring over the operational
    production database 'transitiq_db' to prevent catastrophic data overwrite.
.PARAMETER BackupFile
    Path to the backup file (.dump custom format or .sql plain text).
.PARAMETER TargetDatabase
    Name of the isolated recovery database (Default: 'transitiq_recovery_test').
.PARAMETER HostName
    Database server hostname (Default: 'localhost').
.PARAMETER Port
    Database server port (Default: 5432).
.PARAMETER Username
    Database user (Default: 'postgres').
.PARAMETER Table
    Optional single table name for selective table recovery (-t).
.PARAMETER RecreateDatabase
    Switch to drop and recreate the recovery database before restoration.
.EXAMPLE
    .\restore_transitiq.ps1 -BackupFile "..\backups\transitiq_db_custom_20261122.dump"
    .\restore_transitiq.ps1 -BackupFile "..\backups\transitiq_db_custom_20261122.dump" -Table "trips"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BackupFile,

    [string]$TargetDatabase = "transitiq_recovery_test",
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Username = "postgres",
    [string]$Table = "",
    [switch]$RecreateDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------
# CRITICAL SAFETY GATE: PREVENT ACCIDENTAL PRODUCTION OVERWRITE
# ---------------------------------------------------------------------
if ($TargetDatabase -eq "transitiq_db") {
    Write-Error "CRITICAL SAFETY VIOLATION: Cannot restore over production database 'transitiq_db'. Choose an isolated recovery target like 'transitiq_recovery_test'."
    exit 1
}

# Resolve binaries
$PgBinPath = "C:\Program Files\PostgreSQL\18\bin"
$PgRestoreExe = "$PgBinPath\pg_restore.exe"
$PsqlExe = "$PgBinPath\psql.exe"

if (-not (Test-Path $PgRestoreExe) -or -not (Test-Path $PsqlExe)) {
    Write-Error "PostgreSQL 18 binaries not found at '$PgBinPath'."
    exit 1
}

# Resolve backup file
if (-not (Test-Path $BackupFile)) {
    Write-Error "Backup file not found at path: '$BackupFile'"
    exit 1
}
$BackupFullPath = (Resolve-Path $BackupFile).Path
$FileExtension = [System.IO.Path]::GetExtension($BackupFullPath).ToLower()

Write-Host "=====================================================" -ForegroundColor Green
Write-Host "TRANSITIQLAB: DATABASE RESTORATION UTILITY" -ForegroundColor Green
Write-Host "Target DB : $TargetDatabase (ISOLATED RECOVERY TARGET)"
Write-Host "Source File: $BackupFullPath"
Write-Host "Selective : $(if ($Table) { "Single Table: $Table" } else { "Full Database" })"
Write-Host "=====================================================" -ForegroundColor Green

# 1. Provision target recovery database if needed
Write-Host "`n>>> [STEP 1] Checking target database existence..." -ForegroundColor Yellow
$CheckDbArgs = @("-h", $HostName, "-p", $Port, "-U", $Username, "-d", "postgres", "-t", "-c", "SELECT 1 FROM pg_database WHERE datname = '$TargetDatabase';")
$DbExistsOutput = & $PsqlExe $CheckDbArgs

if ($RecreateDatabase -and ($DbExistsOutput -match "1")) {
    Write-Host "[ACTION] Dropping existing recovery database '$TargetDatabase'..." -ForegroundColor Cyan
    $DropArgs = @("-h", $HostName, "-p", $Port, "-U", $Username, "-d", "postgres", "-c", "DROP DATABASE $TargetDatabase WITH (FORCE);")
    & $PsqlExe $DropArgs | Out-Null
    $DbExistsOutput = ""
}

if (-not ($DbExistsOutput -match "1")) {
    Write-Host "[ACTION] Creating clean recovery database '$TargetDatabase'..." -ForegroundColor Cyan
    $CreateArgs = @("-h", $HostName, "-p", $Port, "-U", $Username, "-d", "postgres", "-c", "CREATE DATABASE $TargetDatabase;")
    & $PsqlExe $CreateArgs | Out-Null
    Write-Host "[SUCCESS] Recovery database '$TargetDatabase' created." -ForegroundColor Green
} else {
    Write-Host "[INFO] Recovery database '$TargetDatabase' exists." -ForegroundColor Cyan
}

# 2. Execute Restoration based on file format
Write-Host "`n>>> [STEP 2] Initiating database restore..." -ForegroundColor Yellow

if ($FileExtension -in @(".dump", ".tar", ".bak") -or $FileExtension -eq "") {
    Write-Host "    Format: PostgreSQL Custom Format (pg_restore)" -ForegroundColor Cyan
    $RestoreArgs = @(
        "-h", $HostName,
        "-p", $Port,
        "-U", $Username,
        "-d", $TargetDatabase,
        "-v",
        "--no-owner"
    )

    if (-not [string]::IsNullOrWhiteSpace($Table)) {
        Write-Host "    Applying Selective Table Filter: -t $Table" -ForegroundColor Magenta
        $RestoreArgs += @("-t", $Table)
    }

    $RestoreArgs += $BackupFullPath

    $Process = Start-Process -FilePath $PgRestoreExe -ArgumentList $RestoreArgs -NoNewWindow -Wait -PassThru

    # pg_restore exit code 0 = clean, 1 = warnings (e.g. non-critical duplicate notices)
    if ($Process.ExitCode -in @(0, 1)) {
        Write-Host "[SUCCESS] pg_restore completed successfully (Exit Code: $($Process.ExitCode))." -ForegroundColor Green
    } else {
        Write-Error "pg_restore failed with exit code $($Process.ExitCode)."
        exit 1
    }
} elseif ($FileExtension -eq ".sql") {
    Write-Host "    Format: Plain-Text SQL Script (psql)" -ForegroundColor Cyan
    $PsqlRestoreArgs = @(
        "-h", $HostName,
        "-p", $Port,
        "-U", $Username,
        "-d", $TargetDatabase,
        "-f", $BackupFullPath
    )

    $Process = Start-Process -FilePath $PsqlExe -ArgumentList $PsqlRestoreArgs -NoNewWindow -Wait -PassThru
    if ($Process.ExitCode -eq 0) {
        Write-Host "[SUCCESS] Plain SQL restore completed successfully." -ForegroundColor Green
    } else {
        Write-Error "psql restore failed with exit code $($Process.ExitCode)."
        exit 1
    }
} else {
    Write-Error "Unsupported backup file extension: '$FileExtension'"
    exit 1
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host "DATABASE RESTORATION COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "Target Database: $TargetDatabase"
Write-Host "Next Step      : Run .\validate_backup.ps1 to verify data integrity"
Write-Host "=====================================================" -ForegroundColor Green
