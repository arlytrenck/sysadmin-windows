<#
.SYNOPSIS
    Compresses a source folder to a timestamped zip archive and prunes old
    archives beyond a retention count.

.DESCRIPTION
    Backup-Rotate.ps1 creates a dated .zip of -Source in -Destination, then
    deletes the oldest archives in that destination beyond -Keep. Intended
    for scheduled use via Task Scheduler for simple file-level backups.

.PARAMETER Source
    Folder to back up.

.PARAMETER Destination
    Folder to write the timestamped archive into. Created if missing.

.PARAMETER Keep
    Number of archives to retain (default: 7). Oldest are deleted first.

.PARAMETER WhatIf
    Show what would happen without deleting anything.

.EXAMPLE
    .\Backup-Rotate.ps1 -Source D:\Data -Destination E:\Backups -Keep 14
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$Source,

    [Parameter(Mandatory)]
    [string]$Destination,

    [int]$Keep = 7
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Source)) {
    throw "Source path '$Source' does not exist."
}

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$hostname  = $env:COMPUTERNAME
$archiveName = "backup-$hostname-$timestamp.zip"
$archivePath = Join-Path $Destination $archiveName

Write-Host "Compressing '$Source' to '$archivePath'..."
if ($PSCmdlet.ShouldProcess($archivePath, "Create archive")) {
    Compress-Archive -Path (Join-Path $Source '*') -DestinationPath $archivePath -CompressionLevel Optimal
    Write-Host "Archive created: $archivePath"
}

# Retention: keep the newest $Keep archives matching this host's naming pattern
$existing = Get-ChildItem -Path $Destination -Filter "backup-$hostname-*.zip" |
    Sort-Object LastWriteTime -Descending

if ($existing.Count -gt $Keep) {
    $toRemove = $existing | Select-Object -Skip $Keep
    foreach ($file in $toRemove) {
        if ($PSCmdlet.ShouldProcess($file.FullName, "Remove old backup")) {
            Remove-Item $file.FullName -Force
            Write-Host "Removed old backup: $($file.Name)"
        }
    }
} else {
    Write-Host "Retention: $($existing.Count) archive(s) present, within limit of $Keep."
}

Write-Host "Done."

