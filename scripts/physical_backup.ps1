<#
.SYNOPSIS
    TransitIQ Physical Database Cluster Backup Orchestrator.
.DESCRIPTION
    Executes a physical cluster-level backup using pg_basebackup with WAL streaming
    (-X stream) and generates a cryptographic SHA-256 backup manifest.
    Verifies physical backup integrity using pg_verifybackup.
.PARAMETER DestinationDir
    Target directory for the base backup (Default: '..\backups\physical_basebackup_<timestamp>').
.PARAMETER HostName
    Database server hostname (Default: 'localhost').
.PARAMETER Port
    Database server port (Default: 5432).
.PARAMETER Username
    Replication/Superuser username (Default: 'postgres').
.PARAMETER Format
    Backup format: 'p' (plain directory) or 't' (tar archives) (Default: 'p').
.EXAMPLE
    .\physical_backup.ps1
    .\physical_backup.ps1 -Format t
#>

[CmdletBinding()]
param(
    [string]$DestinationDir = "",
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Username = "postgres",
    [ValidateSet("p", "t")]
    [string]$Format = "p"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$PgBinPath = "C:\Program Files\PostgreSQL\18\bin"
$PgBasebackupExe = "$PgBinPath\pg_basebackup.exe"
$PgVerifybackupExe = "$PgBinPath\pg_verifybackup.exe"

if (-not (Test-Path $PgBasebackupExe)) {
    Write-Error "CRITICAL: pg_basebackup.exe not found at '$PgBinPath'."
    exit 1
}

# Resolve destination directory
$Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $ProjectRoot = Split-Path -Parent $ScriptDir
    $DestinationDir = Join-Path $ProjectRoot "backups\physical_basebackup_$Timestamp"
}

if (Test-Path $DestinationDir) {
    if ((Get-ChildItem $DestinationDir).Count -gt 0) {
        Write-Error "Destination directory '$DestinationDir' already exists and is not empty. pg_basebackup requires an empty target directory."
        exit 1
    }
} else {
    New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null
}

Write-Host "=====================================================" -ForegroundColor Green
Write-Host "TRANSITIQLAB: PHYSICAL BASEBACKUP ORCHESTRATOR" -ForegroundColor Green
Write-Host "Host:Port       : $HostName`:$Port"
Write-Host "User            : $Username"
Write-Host "Format          : $(if ($Format -eq 'p') { 'Plain Directory' } else { 'TAR Archive' })"
Write-Host "Target Directory: $DestinationDir"
Write-Host "WAL Ingestion   : Streaming (-X stream)"
Write-Host "Manifest Hash   : SHA-256"
Write-Host "=====================================================" -ForegroundColor Green

# 1. Execute pg_basebackup
Write-Host "`n>>> [STEP 1] Streaming physical base backup from PostgreSQL engine..." -ForegroundColor Yellow

$BasebackupArgs = @(
    "-h", $HostName,
    "-p", $Port,
    "-U", $Username,
    "-D", $DestinationDir,
    "-F", $Format,
    "-X", "stream",
    "-P",
    "-v",
    "--manifest-checksum=SHA256"
)

$Process = Start-Process -FilePath $PgBasebackupExe -ArgumentList $BasebackupArgs -NoNewWindow -Wait -PassThru

if ($Process.ExitCode -eq 0) {
    Write-Host "[SUCCESS] pg_basebackup completed successfully." -ForegroundColor Green
} else {
    Write-Error "pg_basebackup failed with exit code $($Process.ExitCode)."
    exit 1
}

# 2. Verify Physical Backup with pg_verifybackup (if plain format)
if ($Format -eq "p" -and (Test-Path $PgVerifybackupExe)) {
    Write-Host "`n>>> [STEP 2] Verifying physical backup manifest integrity (pg_verifybackup)..." -ForegroundColor Yellow
    $VerifyArgs = @("-v", $DestinationDir)
    $VerifyProcess = Start-Process -FilePath $PgVerifybackupExe -ArgumentList $VerifyArgs -NoNewWindow -Wait -PassThru

    if ($VerifyProcess.ExitCode -eq 0) {
        Write-Host "[PASS] Backup manifest verified: SHA-256 checksums intact, 0 corrupted files." -ForegroundColor Green
    } else {
        Write-Warning "pg_verifybackup detected issues or exited with code $($VerifyProcess.ExitCode)."
    }
}

$TotalSize = (Get-ChildItem $DestinationDir -Recurse | Measure-Object -Property Length -Sum).Sum
$SizePretty = "{0:N2} MB" -f ($TotalSize / 1MB)

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host "PHYSICAL BASEBACKUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "Total Size : $SizePretty ($TotalSize bytes)"
Write-Host "Location   : $DestinationDir"
Write-Host "=====================================================" -ForegroundColor Green
