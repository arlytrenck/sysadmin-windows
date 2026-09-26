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
        # Filter server-side on EndTime rather than pulling the whole log into
        # the pipeline to count; this matches how every other script here
        # queries the event log, and a large Security log makes the difference.
        $count = (Get-WinEvent -FilterHashtable @{ LogName = $logName; EndTime = $cutoff } -ErrorAction SilentlyContinue |
            Measure-Object).Count
        Write-Host "$logName`: $count entries older than $RetentionDays days"

        if ($count -gt 0 -and -not $DryRun) {
            $exportPath = Join-Path $env:windir "Temp\$logName-archive-$(Get-Date -Format yyyyMMdd).evtx"
            # /ow:true: the name is per-day, so a second run the same day would
            # otherwise fail on the existing file - and the Test-Path below
            # would then report yesterday-morning's export as this run's.
            wevtutil epl $logName $exportPath "/q:*[System[TimeCreated[timediff(@SystemTime) >= $($RetentionDays * 86400000)]]]" /ow:true 2>$null
            if ($LASTEXITCODE -eq 0 -and (Test-Path $exportPath)) {
                Write-Host "  Exported matching entries to $exportPath"
            } else {
                Write-Warning "  wevtutil could not export '$logName' (exit $LASTEXITCODE); nothing archived."
            }
        } elseif ($DryRun) {
            Write-Host "  (dry run - would export/archive these entries)"
        }
    } catch {
        Write-Warning "Could not process log '$logName': $_"
    }
}

if ($LogFolder) {
    Write-Host ""
    Write-Host "=== Flat log files under $LogFolder ==="
    if (-not (Test-Path -LiteralPath $LogFolder)) {
        Write-Warning "Log folder '$LogFolder' not found."
    } else {
        # -Filter '*.log' also matches 8.3 short names, so it returns things
        # like "web.logfile" and "old.log_bak". This branch deletes, so the
        # extension is checked exactly.
        $oldFiles = @(Get-ChildItem -LiteralPath $LogFolder -Filter '*.log' -Recurse -File |
            Where-Object { $_.Extension -eq '.log' -and $_.LastWriteTime -lt $cutoff })
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

