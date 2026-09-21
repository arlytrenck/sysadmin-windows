<#
.SYNOPSIS
    Summarizes recent interactive logons, failed logons, and locked-out
    accounts from the Security event log.

.PARAMETER Count
    Number of recent entries to show per section (default: 20).

.PARAMETER Hours
    How far back to look, in hours (default: 24).

.PARAMETER AllLogonTypes
    Include every successful logon. By default only interactive (2),
    unlock (7), remote-desktop (10) and cached-interactive (11) logons are
    listed: on a server the newest 4624 events are otherwise almost all
    service and network logons by machine accounts, which crowds out the
    people the report is meant to show.

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
    [int]$Hours = 24,
    [switch]$AllLogonTypes
)

$ErrorActionPreference = 'SilentlyContinue'
$since = (Get-Date).AddHours(-$Hours)

Write-Host "=== Currently logged on (interactive + RDP) sessions ==="
try {
    query user 2>$null
} catch {
    Write-Host "  (query user unavailable - no interactive sessions, or not supported on this SKU)"
}

Write-Host ""
Write-Host "=== Successful $(if ($AllLogonTypes) { '' } else { 'interactive ' })logons in the last $Hours hour(s) (event 4624, up to $Count) ==="
try {
    $typeNames = @{ 2 = 'Interactive'; 3 = 'Network'; 4 = 'Batch'; 5 = 'Service'; 7 = 'Unlock'; 8 = 'NetworkCleartext'; 9 = 'NewCredentials'; 10 = 'RemoteInteractive'; 11 = 'CachedInteractive' }
    if ($AllLogonTypes) {
        $logons = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624; StartTime = $since } -ErrorAction Stop
    } else {
        $ms = [int64]($Hours * 3600 * 1000)
        $xpath = "*[System[(EventID=4624) and TimeCreated[timediff(@SystemTime) <= $ms]]] and " +
                 "*[EventData[Data[@Name='LogonType']=2 or Data[@Name='LogonType']=7 or Data[@Name='LogonType']=10 or Data[@Name='LogonType']=11]]"
        $logons = Get-WinEvent -LogName Security -FilterXPath $xpath -ErrorAction Stop
    }
    # The window manager and font-driver host log on as virtual accounts each
    # time a session starts; they are not people.
    $logons | Where-Object { $_.Properties[6].Value -notmatch '^(Window Manager|Font Driver Host)$' } |
        Select-Object -First $Count TimeCreated,
            @{N='Account'; E={$_.Properties[5].Value}},
            @{N='LogonType'; E={ $t = [int]$_.Properties[8].Value; if ($typeNames.ContainsKey($t)) { "$t ($($typeNames[$t]))" } else { "$t" } }},
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

