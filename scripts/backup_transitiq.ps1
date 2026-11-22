<#
.SYNOPSIS
    TransitIQ Production Database Backup Utility.
.DESCRIPTION
    Performs logical backups of the TransitIQ PostgreSQL database using pg_dump.
    Supports Custom (-Fc), Plain SQL (-Fp), Schema-Only (-s), Data-Only (-a),
    and Compressed Directory formats with timestamped archives and error handling.
.PARAMETER DatabaseName
    Name of the source database to back up (Default: 'transitiq_db').
.PARAMETER Host
    Database server hostname (Default: 'localhost').
.PARAMETER Port
    Database server port (Default: 5432).
.PARAMETER Username
    Database superuser or backup role (Default: 'postgres').
.PARAMETER BackupDir
    Destination directory for backup archives (Default: '..\backups').
.PARAMETER BackupFormat
    Backup format to generate: 'Custom', 'Plain', 'SchemaOnly', 'DataOnly', 'All' (Default: 'All').
.EXAMPLE
    .\backup_transitiq.ps1 -BackupFormat Custom
    .\backup_transitiq.ps1 -DatabaseName transitiq_db -BackupDir "D:\TransitIQ_Backups" -BackupFormat All
#>

[CmdletBinding()]
param(
    [string]$DatabaseName = "transitiq_db",
    [string]$HostName = "localhost",
    [int]$Port = 5432,
    [string]$Username = "postgres",
    [string]$BackupDir = "",
    [ValidateSet("Custom", "Plain", "SchemaOnly", "DataOnly", "All")]
    [string]$BackupFormat = "All"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Resolve PostgreSQL binary path
$PgBinPath = "C:\Program Files\PostgreSQL\18\bin"
if (-not (Test-Path "$PgBinPath\pg_dump.exe")) {
    # Check PATH fallback
    $DumpCmd = Get-Command "pg_dump.exe" -ErrorAction SilentlyContinue
    if ($DumpCmd) {
        $PgDumpExe = $DumpCmd.Source
    } else {
        Write-Error "CRITICAL: pg_dump.exe not found at '$PgBinPath' or in system PATH."
        exit 1
    }
} else {
    $PgDumpExe = "$PgBinPath\pg_dump.exe"
}

# Resolve target backup directory
if ([string]::IsNullOrWhiteSpace($BackupDir)) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $TargetBackupDir = Join-Path (Split-Path -Parent $ScriptDir) "backups"
} else {
    $TargetBackupDir = (Resolve-Path -Path $BackupDir -ErrorAction SilentlyContinue)?.Path
    if (-not $TargetBackupDir) {
        $TargetBackupDir = $BackupDir
    }
}

if (-not (Test-Path $TargetBackupDir)) {
    New-Item -ItemType Directory -Path $TargetBackupDir -Force | Out-Null
    Write-Host "[INIT] Created backup directory: $TargetBackupDir" -ForegroundColor Cyan
}

$Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
Write-Host "=====================================================" -ForegroundColor Green
Write-Host "TRANSITIQLAB: DATABASE BACKUP ORCHESTRATOR" -ForegroundColor Green
Write-Host "Database  : $DatabaseName"
Write-Host "Host:Port : $HostName`:$Port"
Write-Host "User      : $Username"
Write-Host "Timestamp : $Timestamp"
Write-Host "Target Dir: $TargetBackupDir"
Write-Host "=====================================================" -ForegroundColor Green

# Function to execute and validate a pg_dump run
function Invoke-TransitDump {
    param(
        [string]$Description,
        [string]$FileName,
        [string[]]$Arguments
    )

    $OutputFile = Join-Path $TargetBackupDir $FileName
    Write-Host "`n>>> [START] Generating $Description..." -ForegroundColor Yellow
    Write-Host "    File: $OutputFile"

    $AllArgs = @(
        "-h", $HostName,
        "-p", $Port,
        "-U", $Username,
        "-d", $DatabaseName,
        "-f", $OutputFile
    ) + $Arguments

    $Process = Start-Process -FilePath $PgDumpExe -ArgumentList $AllArgs -NoNewWindow -Wait -PassThru

    if ($Process.ExitCode -eq 0 -and (Test-Path $OutputFile)) {
        $FileBytes = (Get-Item $OutputFile).Length
        $FilePretty = "{0:N2} KB" -f ($FileBytes / 1KB)
        Write-Host "[SUCCESS] $Description created successfully!" -ForegroundColor Green
        Write-Host "          Size: $FilePretty ($FileBytes bytes)" -ForegroundColor Green
        return $OutputFile
    } else {
        Write-Error "FAILED: $Description failed with exit code $($Process.ExitCode)"
        exit 1
    }
}

# 1. Custom Format Backup (-Fc): Compressed, re-orderable, supports selective restore
if ($BackupFormat -in @("Custom", "All")) {
    $CustomFile = "${DatabaseName}_custom_${Timestamp}.dump"
    Invoke-TransitDump -Description "Full Database Custom-Format Backup (-Fc)" `
        -FileName $CustomFile `
        -Arguments @("-F", "c", "-b", "-v", "--no-owner")
}

# 2. Plain SQL Format Backup (-Fp): Human-readable SQL script
if ($BackupFormat -in @("Plain", "All")) {
    $PlainFile = "${DatabaseName}_plain_${Timestamp}.sql"
    Invoke-TransitDump -Description "Plain-Text SQL Backup (-Fp)" `
        -FileName $PlainFile `
        -Arguments @("-F", "p", "--clean", "--if-exists", "--no-owner")
}

# 3. Schema-Only Backup (-s): DDL structures, indexes, views, functions, triggers
if ($BackupFormat -in @("SchemaOnly", "All")) {
    $SchemaFile = "${DatabaseName}_schema_only_${Timestamp}.sql"
    Invoke-TransitDump -Description "Schema-Only DDL Backup (-s)" `
        -FileName $SchemaFile `
        -Arguments @("-s", "--clean", "--if-exists", "--no-owner")
}

# 4. Data-Only Backup (-a): Tuple records and copy streams
if ($BackupFormat -in @("DataOnly", "All")) {
    $DataFile = "${DatabaseName}_data_only_${Timestamp}.sql"
    Invoke-TransitDump -Description "Data-Only Tuple Backup (-a)" `
        -FileName $DataFile `
        -Arguments @("-a", "--disable-triggers")
}

Write-Host "`n=====================================================" -ForegroundColor Green
Write-Host "ALL REQUESTED BACKUPS COMPLETED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "Destination: $TargetBackupDir"
Write-Host "=====================================================" -ForegroundColor Green
