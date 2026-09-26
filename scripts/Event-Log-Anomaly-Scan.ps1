<#
.SYNOPSIS
    Flags an unusual spike in Error/Critical-level event log entries over
    a recent window, compared against a trailing baseline window.

.DESCRIPTION
    Rather than watching for specific known-bad event IDs, this compares
    the *rate* of Error/Critical entries in a recent window against an
    earlier baseline window of the same length, so it catches problems
    you didn't think to watch for in advance. Checks System and
    Application logs by default.

.NOTES
    Exit codes: 0 = no anomaly; 1 = anomalous error rate; 2 = a log could
    not be queried (unknown or unreadable), so the result is incomplete.

.PARAMETER WindowMinutes
    Size of both the recent and baseline windows, in minutes (default: 15).

.PARAMETER Multiplier
    Flag if recent-count >= Multiplier * baseline-count (default: 3).

.PARAMETER LogName
    Event log(s) to check (default: System, Application).

.EXAMPLE
    .\Event-Log-Anomaly-Scan.ps1 -WindowMinutes 30 -Multiplier 4
#>

[CmdletBinding()]
param(
    [int]$WindowMinutes = 15,
    [int]$Multiplier = 3,
    [string[]]$LogName = @('System', 'Application')
)

$now = Get-Date
$recentStart = $now.AddMinutes(-$WindowMinutes)
$baselineStart = $now.AddMinutes(-2 * $WindowMinutes)

$anomalyFound = $false
$queryFailed = $false

# Get-WinEvent reports "no matching events" as an error, which is the good
# case here and must read as zero. Every other failure (a misspelled log name,
# no permission to read Security) has to surface: swallowing all errors with
# SilentlyContinue would turn "could not look" into "nothing wrong".
function Get-ErrorEventCount {
    param([string]$Log, [datetime]$Start, [datetime]$End)
    try {
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName   = $Log
            Level     = 1, 2   # Critical, Error
            StartTime = $Start
            EndTime   = $End
        } -ErrorAction Stop)
        return $events.Count
    } catch {
        if ($_.FullyQualifiedErrorId -like 'NoMatchingEventsFound*' -or
            $_.Exception.Message -like 'No events were found*') {
            return 0
        }
        throw
    }
}

foreach ($log in $LogName) {
    Write-Host "=== $log log ==="

    try {
        $recentCount   = Get-ErrorEventCount -Log $log -Start $recentStart   -End $now
        $baselineCount = Get-ErrorEventCount -Log $log -Start $baselineStart -End $recentStart
    } catch {
        Write-Host "  [ERROR] Could not query this log: $($_.Exception.Message)"
        $queryFailed = $true
        Write-Host ""
        continue
    }

    Write-Host "  Recent window (last ${WindowMinutes}m):   $recentCount Error/Critical entries"
    Write-Host "  Baseline window (prior ${WindowMinutes}m): $baselineCount Error/Critical entries"

    $floor = 5
    if ($baselineCount -eq 0) {
        if ($recentCount -ge $floor) {
            Write-Host "  [ANOMALY] baseline was 0, recent window has $recentCount (>= floor of $floor)"
            $anomalyFound = $true
        } else {
            Write-Host "  OK (recent count below floor of $floor)"
        }
    } else {
        $threshold = $baselineCount * $Multiplier
        if ($recentCount -ge $threshold) {
            Write-Host "  [ANOMALY] recent count $recentCount >= ${Multiplier}x baseline ($threshold)"
            $anomalyFound = $true
        } else {
            Write-Host "  OK (below ${Multiplier}x baseline threshold of $threshold)"
        }
    }
    Write-Host ""
}

if ($queryFailed) {
    Write-Host "RESULT: one or more logs could not be queried, so this check is incomplete."
    exit 2
}
if ($anomalyFound) {
    Write-Host "RESULT: one or more logs show an anomalous error rate."
    exit 1
}
Write-Host "RESULT: no anomalies found."
exit 0
