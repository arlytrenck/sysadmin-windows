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

    # Below 1 the retention pass would delete the archive it just wrote.
    [ValidateRange(1, [int]::MaxValue)]
    [int]$Keep = 7
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source path '$Source' does not exist."
}

# An archive written inside the folder being archived would be swept into the
# next run's zip, and grow it a little more every night.
$srcFull = (Resolve-Path -LiteralPath $Source).ProviderPath.TrimEnd('\') + '\'
$dstFull = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Destination).TrimEnd('\') + '\'
if ($dstFull.StartsWith($srcFull, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Destination '$Destination' is inside Source '$Source'; the archive would include itself."
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
# The extension test is not redundant: -Filter also matches 8.3 short names, so
# "backup-HOST-*.zip" picks up "backup-HOST-1.zipx", and this loop deletes.
$existing = @(Get-ChildItem -LiteralPath $Destination -Filter "backup-$hostname-*.zip" -File |
    Where-Object { $_.Extension -eq '.zip' } |
    Sort-Object LastWriteTime -Descending)

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

