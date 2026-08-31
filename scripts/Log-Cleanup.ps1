<#
.SYNOPSIS
    Clears or backs up Windows Event Log entries older than a retention
    period, and optionally trims old .log files in a folder (e.g. IIS logs).

.PARAMETER LogNames
    Event log names to manage (default: Application, System, Security).

.PARAMETER RetentionDays
    Entries/files older than this many days are handled (default: 30).

.PARAMETER LogFolder
    Optional folder of flat .log files (e.g. IIS/W3SVC logs) to also prune.

.PARAMETER DryRun
    Report what would be removed without removing anything.

.EXAMPLE
    .\Log-Cleanup.ps1 -RetentionDays 60 -LogFolder 'C:\inetpub\logs\LogFiles\W3SVC1' -DryRun
#>

[CmdletBinding()]
param(
    [string[]]$LogNames = @('Application', 'System', 'Security'),
    [int]$RetentionDays = 30,
    [string]$LogFolder = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$cutoff = (Get-Date).AddDays(-$RetentionDays)

Write-Host "=== Windows Event Logs ==="
Write-Host "Note: Windows event logs are size-capped ring buffers, not something you"
Write-Host "prune by date in place. This exports entries older than $RetentionDays days"
Write-Host "(for archival) and reports counts; use log size/retention policy"
Write-Host "(wevtutil sl, or Group Policy) to control ongoing growth."
Write-Host ""

foreach ($logName in $LogNames) {
    try {
        $oldEvents = Get-WinEvent -LogName $logName -ErrorAction SilentlyContinue |
            Where-Object { $_.TimeCreated -lt $cutoff }
        $count = ($oldEvents | Measure-Object).Count
        Write-Host "$logName`: $count entries older than $RetentionDays days"

        if ($count -gt 0 -and -not $DryRun) {
            $exportPath = "C:\Windows\Temp\$logName-archive-$(Get-Date -Format yyyyMMdd).evtx"
            wevtutil epl $logName $exportPath "/q:*[System[TimeCreated[timediff(@SystemTime) >= $($RetentionDays * 86400000)]]]" 2>$null
            if (Test-Path $exportPath) {
                Write-Host "  Exported matching entries to $exportPath"
            }
        } elseif ($DryRun) {
            Write-Host "  (dry run — would export/archive these entries)"
        }
    } catch {
        Write-Warning "Could not process log '$logName': $_"
    }
}

if ($LogFolder) {
    Write-Host ""
    Write-Host "=== Flat log files under $LogFolder ==="
    if (-not (Test-Path $LogFolder)) {
        Write-Warning "Log folder '$LogFolder' not found."
    } else {
        $oldFiles = Get-ChildItem -Path $LogFolder -Filter '*.log' -Recurse -File |
            Where-Object { $_.LastWriteTime -lt $cutoff }
        foreach ($file in $oldFiles) {
            if ($DryRun) {
                Write-Host "Would remove: $($file.FullName) (last written $($file.LastWriteTime))"
            } else {
                Remove-Item $file.FullName -Force
                Write-Host "Removed: $($file.FullName)"
            }
        }
        Write-Host "$($oldFiles.Count) file(s) $(if ($DryRun) {'would be'} else {'were'}) removed."
    }
}

Write-Host ""
Write-Host "Done."

