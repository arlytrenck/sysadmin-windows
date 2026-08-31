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

foreach ($log in $LogName) {
    Write-Host "=== $log log ==="

    try {
        $recentCount = (Get-WinEvent -FilterHashtable @{
            LogName   = $log
            Level     = 1, 2   # Critical, Error
            StartTime = $recentStart
            EndTime   = $now
        } -ErrorAction SilentlyContinue | Measure-Object).Count

        $baselineCount = (Get-WinEvent -FilterHashtable @{
            LogName   = $log
            Level     = 1, 2
            StartTime = $baselineStart
            EndTime   = $recentStart
        } -ErrorAction SilentlyContinue | Measure-Object).Count
    } catch {
        Write-Host "  Could not query this log: $($_.Exception.Message)"
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

if ($anomalyFound) {
    Write-Host "RESULT: one or more logs show an anomalous error rate."
    exit 1
} else {
    Write-Host "RESULT: no anomalies found."
    exit 0
}
