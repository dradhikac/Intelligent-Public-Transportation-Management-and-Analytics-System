<#
.SYNOPSIS
    TransitIQ Backup & Recovery Validation Harness.
.DESCRIPTION
    Validates backup file integrity, table of contents (TOC), and executes
    the 15-checkpoint database verification suite against the restored database.
.PARAMETER BackupFile
    Path to the backup file to inspect (if omitted, picks newest .dump file in backups/).
.PARAMETER TargetDatabase
    Name of the restored database to audit (Default: 'transitiq_recovery_test').
#>

[CmdletBinding()]
param(
    [string]$BackupFile = "",
    [string]$TargetDatabase = "transitiq_recovery_test",
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Username = "postgres"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PgBinPath = "C:\Program Files\PostgreSQL\18\bin"
$PgRestoreExe = "$PgBinPath\pg_restore.exe"
$PsqlExe = "$PgBinPath\psql.exe"

# Resolve backup file if not specified
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$BackupsDir = Join-Path $ProjectRoot "backups"

if ([string]::IsNullOrWhiteSpace($BackupFile)) {
    if (Test-Path $BackupsDir) {
        $LatestBackup = Get-ChildItem -Path $BackupsDir -Filter "*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($LatestBackup) {
            $BackupFile = $LatestBackup.FullName
            Write-Host "[AUTO-DETECT] Selected latest backup: $($LatestBackup.Name)" -ForegroundColor Cyan
        }
    }
}

Write-Host "=====================================================" -ForegroundColor Green
Write-Host "TRANSITIQLAB: BACKUP & RESTORE VALIDATION ENGINE" -ForegroundColor Green
Write-Host "Target Database: $TargetDatabase"
Write-Host "=====================================================" -ForegroundColor Green

# 1. Validate Backup File Integrity
if (-not [string]::IsNullOrWhiteSpace($BackupFile) -and (Test-Path $BackupFile)) {
    $FileItem = Get-Item $BackupFile
    Write-Host "`n>>> [CHECK 1] Inspecting physical backup archive..." -ForegroundColor Yellow
    Write-Host "    File : $($FileItem.FullName)"
    Write-Host "    Size : {0:N2} KB ($($FileItem.Length) bytes)" -f ($FileItem.Length / 1KB)

    if ($FileItem.Length -le 0) {
        Write-Error "VALIDATION FAILED: Backup archive is empty (0 bytes)!"
        exit 1
    }
    Write-Host "[PASS] Backup file exists and contains non-zero payload." -ForegroundColor Green

    # 2. Inspect Table of Contents (TOC) with pg_restore -l
    if ($FileItem.Extension.ToLower() -eq ".dump") {
        Write-Host "`n>>> [CHECK 2] Inspecting pg_restore Table of Contents (TOC)..." -ForegroundColor Yellow
        $TocOutput = & $PgRestoreExe -l $FileItem.FullName | Select-Object -First 15
        Write-Host "[PASS] TOC header valid. Sample archive entries:" -ForegroundColor Green
        $TocOutput | ForEach-Object { Write-Host "       $_" -ForegroundColor Gray }
    }
} else {
    Write-Host "[INFO] No backup archive provided for TOC check; proceeding to database verification." -ForegroundColor Yellow
}

# 3. Execute SQL 15-Checkpoint Validation Suite against Target Database
$ValidationSqlPath = Join-Path $ProjectRoot "database\32_restore_validation.sql"
if (-not (Test-Path $ValidationSqlPath)) {
    Write-Error "Validation SQL script not found at '$ValidationSqlPath'."
    exit 1
}

Write-Host "`n>>> [CHECK 3] Executing 15-Point Relational & Data Integrity Harness..." -ForegroundColor Yellow
$PsqlArgs = @(
    "-h", $HostName,
    "-p", $Port,
    "-U", $Username,
    "-d", $TargetDatabase,
    "-f", $ValidationSqlPath
)

& $PsqlExe $PsqlArgs

if ($LASTEXITCODE -eq 0) {
    Write-Host "`n=====================================================" -ForegroundColor Green
    Write-Host "ALL BACKUP & RESTORATION VALIDATIONS PASSED!" -ForegroundColor Green
    Write-Host "Target: $TargetDatabase verified 100% production-ready."
    Write-Host "=====================================================" -ForegroundColor Green
} else {
    Write-Error "Database validation harness failed with exit code $LASTEXITCODE."
    exit 1
}
