<#
.SYNOPSIS
    Checks Windows Defender's protection status and flags common
    misconfigurations: disabled real-time protection, stale signatures,
    or no recent scan.

.PARAMETER MaxSignatureAgeDays
    Flag if antivirus/antispyware signatures are older than this many
    days (default: 3).

.PARAMETER MaxScanAgeDays
    Flag if the last quick or full scan is older than this many days
    (default: 7).

.EXAMPLE
    .\Defender-Status-Check.ps1 -MaxSignatureAgeDays 2 -MaxScanAgeDays 10

.NOTES
    If a third-party AV product is installed and has registered itself as
    the active antimalware provider, Windows Defender's real-time
    protection is normally disabled by design - this script only reports
    Defender's own state, it doesn't attempt to detect or evaluate a
    third-party product.
#>

[CmdletBinding()]
param(
    [int]$MaxSignatureAgeDays = 3,
    [int]$MaxScanAgeDays = 7
)

$flagged = 0

try {
    $status = Get-MpComputerStatus -ErrorAction Stop
} catch {
    Write-Host "Could not query Windows Defender status: $($_.Exception.Message)"
    Write-Host "(Get-MpComputerStatus requires the Defender PowerShell module, present by default on Windows 10/11 and Server 2016+.)"
    exit 2
}

Write-Host "=== Real-time protection ==="
if ($status.RealTimeProtectionEnabled) {
    Write-Host "  OK: real-time protection is enabled"
} else {
    Write-Host "  [FLAG] real-time protection is DISABLED"
    $flagged++
}

Write-Host ""
Write-Host "=== Signature age ==="
$sigAge = $status.AntivirusSignatureAge
Write-Host "  Antivirus signature age: $sigAge day(s)"
if ($sigAge -gt $MaxSignatureAgeDays) {
    Write-Host "  [FLAG] signatures are older than $MaxSignatureAgeDays day(s)"
    $flagged++
} else {
    Write-Host "  OK"
}

Write-Host ""
Write-Host "=== Last scan ==="
$lastQuick = $status.QuickScanEndTime
$lastFull = $status.FullScanEndTime
$mostRecent = @($lastQuick, $lastFull) | Where-Object { $_ } | Sort-Object -Descending | Select-Object -First 1

if ($mostRecent) {
    $scanAgeDays = (New-TimeSpan -Start $mostRecent -End (Get-Date)).Days
    Write-Host "  Most recent scan: $mostRecent ($scanAgeDays day(s) ago)"
    if ($scanAgeDays -gt $MaxScanAgeDays) {
        Write-Host "  [FLAG] last scan is older than $MaxScanAgeDays day(s)"
        $flagged++
    } else {
        Write-Host "  OK"
    }
} else {
    Write-Host "  [FLAG] no scan history found"
    $flagged++
}

Write-Host ""
Write-Host "=== Other status flags ==="
Write-Host "  AntivirusEnabled:        $($status.AntivirusEnabled)"
Write-Host "  BehaviorMonitorEnabled:  $($status.BehaviorMonitorEnabled)"
Write-Host "  IoavProtectionEnabled:   $($status.IoavProtectionEnabled)  (scan of files from internet)"
Write-Host "  OnAccessProtectionEnabled: $($status.OnAccessProtectionEnabled)"
if (-not $status.AntivirusEnabled -or -not $status.BehaviorMonitorEnabled) {
    $flagged++
}

Write-Host ""
if ($flagged -gt 0) {
    Write-Host "RESULT: $flagged item(s) flagged above."
    exit 1
} else {
    Write-Host "RESULT: nothing flagged."
    exit 0
}
