<#
.SYNOPSIS
    Summarizes recent interactive logons, failed logons, and locked-out
    accounts from the Security event log.

.PARAMETER Count
    Number of recent entries to show per section (default: 20).

.PARAMETER Hours
    How far back to look, in hours (default: 24).

.DESCRIPTION
    Requires the Security event log to be readable (typically requires
    running as Administrator) and assumes default auditing of logon
    events (4624/4625) and account lockouts (4740) is enabled.

.EXAMPLE
    .\User-Activity-Report.ps1 -Hours 72 -Count 50
#>

[CmdletBinding()]
param(
    [int]$Count = 20,
    [int]$Hours = 24
)

$ErrorActionPreference = 'SilentlyContinue'
$since = (Get-Date).AddHours(-$Hours)

Write-Host "=== Currently logged on (interactive + RDP) sessions ==="
try {
    query user 2>$null
} catch {
    Write-Host "  (query user unavailable — no interactive sessions, or not supported on this SKU)"
}

Write-Host ""
Write-Host "=== Successful logons in the last $Hours hour(s) (event 4624, up to $Count) ==="
try {
    $logons = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624; StartTime = $since } -MaxEvents $Count -ErrorAction Stop
    $logons | Select-Object TimeCreated,
        @{N='Account'; E={$_.Properties[5].Value}},
        @{N='LogonType'; E={$_.Properties[8].Value}},
        @{N='SourceIP'; E={$_.Properties[18].Value}} |
        Format-Table -AutoSize | Out-String | Write-Host
} catch {
    Write-Host "  (no matching events, or Security log requires elevation)"
}

Write-Host "=== Failed logons in the last $Hours hour(s) (event 4625, up to $Count) ==="
try {
    $failed = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = $since } -MaxEvents $Count -ErrorAction Stop
    $failed | Select-Object TimeCreated,
        @{N='Account'; E={$_.Properties[5].Value}},
        @{N='SourceIP'; E={$_.Properties[19].Value}} |
        Format-Table -AutoSize | Out-String | Write-Host
} catch {
    Write-Host "  (no matching events, or Security log requires elevation)"
}

Write-Host "=== Account lockouts in the last $Hours hour(s) (event 4740, up to $Count) ==="
try {
    $lockouts = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4740; StartTime = $since } -MaxEvents $Count -ErrorAction Stop
    $lockouts | Select-Object TimeCreated,
        @{N='Account'; E={$_.Properties[0].Value}},
        @{N='CallerComputer'; E={$_.Properties[1].Value}} |
        Format-Table -AutoSize | Out-String | Write-Host
} catch {
    Write-Host "  (no lockouts found, or Security log requires elevation)"
}

Write-Host "Done."

