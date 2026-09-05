<#
.SYNOPSIS
    Confirms the Windows Time service (W32Time) is running and synchronized,
    and reports the current offset from its time source. Clock drift
    quietly breaks Kerberos (5-minute skew limit by default), TLS
    validation, and cross-host log correlation long before anyone notices.

.PARAMETER ThresholdMs
    Warn if the reported offset exceeds this many milliseconds
    (default: 1000 — Kerberos itself tolerates up to 5 minutes, but
    anything past a second usually means the source is unreachable or
    the service is unhealthy).

.EXAMPLE
    .\Time-Sync-Check.ps1 -ThresholdMs 500

.NOTES
    Exit codes: 0 = synchronized and within threshold, 1 = not
    synchronized or offset exceeds the threshold, 2 = W32Time not running
    / could not be queried.
#>

[CmdletBinding()]
param(
    [int]$ThresholdMs = 1000
)

$svc = Get-Service -Name W32Time -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne 'Running') {
    Write-Warning "W32Time service is not running (status: $($svc.Status))."
    exit 2
}

Write-Host "=== w32tm /query /status ==="
$statusRaw = & w32tm /query /status 2>&1
$statusRaw | Write-Host

if ($LASTEXITCODE -ne 0) {
    Write-Warning "w32tm /query /status failed — host may not be configured for NTP."
    exit 2
}

$flagged = $false

$offsetLine = $statusRaw | Where-Object { $_ -match 'Phase Offset' } | Select-Object -First 1
if (-not $offsetLine) {
    Write-Warning "Could not find a 'Phase Offset' line in w32tm output."
    exit 2
}

# e.g. "Phase Offset: 0.0312500s"
if ($offsetLine -match '([\-0-9.]+)s') {
    $offsetMs = [math]::Abs([double]$matches[1]) * 1000
    Write-Host ""
    Write-Host ("Offset: {0:N1}ms (threshold {1}ms)" -f $offsetMs, $ThresholdMs)
    if ($offsetMs -gt $ThresholdMs) {
        Write-Host "FLAG: offset exceeds threshold"
        $flagged = $true
    }
} else {
    Write-Warning "Could not parse offset from: $offsetLine"
    $flagged = $true
}

Write-Host ""
Write-Host "=== w32tm /query /peers ==="
& w32tm /query /peers 2>&1 | Write-Host

Write-Host ""
if ($flagged) {
    Write-Host "RESULT: time sync problem detected."
    exit 1
}
Write-Host "RESULT: synchronized and within threshold."
exit 0
