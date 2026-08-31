<#
.SYNOPSIS
    Read-only security review: local admin group membership, accounts with
    non-expiring passwords, listening services, firewall profile state,
    and recent failed logon attempts.

.DESCRIPTION
    Makes no changes to the system. Intended as a quick baseline check;
    review findings against your organization's actual policy.

.EXAMPLE
    .\Security-Audit.ps1 | Tee-Object -FilePath C:\Reports\security-audit.txt
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=== Local Administrators group membership ==="
Get-LocalGroupMember -Group 'Administrators' | Format-Table Name, ObjectClass, PrincipalSource -AutoSize |
    Out-String | Write-Host

Write-Host "=== Local accounts with passwords that never expire ==="
Get-LocalUser | Where-Object { $_.PasswordExpires -eq $null -and $_.Enabled } |
    Format-Table Name, Enabled, LastLogon -AutoSize | Out-String | Write-Host

Write-Host "=== Enabled accounts that have never logged on ==="
Get-LocalUser | Where-Object { $_.Enabled -and -not $_.LastLogon } |
    Format-Table Name, Enabled, PasswordLastSet -AutoSize | Out-String | Write-Host

Write-Host "=== Listening services (by owning process) ==="
Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, @{N='Process';E={(Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName}} |
    Sort-Object LocalPort -Unique | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== Windows Firewall profile status ==="
Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction -AutoSize |
    Out-String | Write-Host

Write-Host "=== Recent failed logon attempts (Security log, event 4625, last 24h) ==="
try {
    $since = (Get-Date).AddHours(-24)
    $failed = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4625; StartTime = $since } -ErrorAction Stop
    $failed | Select-Object TimeCreated,
        @{N='Account';E={$_.Properties[5].Value}},
        @{N='SourceIP';E={$_.Properties[19].Value}} |
        Format-Table -AutoSize | Out-String | Write-Host
    Write-Host "$($failed.Count) failed logon(s) in the last 24 hours."
} catch {
    Write-Host "No matching events found, or Security log requires elevation to read (run as Administrator)."
}

Write-Host ""
Write-Host "=== Windows Defender / antivirus status ==="
try {
    $av = Get-MpComputerStatus -ErrorAction Stop
    "{0,-30}: {1}" -f 'Real-time protection', $av.RealTimeProtectionEnabled | Write-Host
    "{0,-30}: {1}" -f 'Antivirus signature age (days)', $av.AntivirusSignatureAge | Write-Host
} catch {
    Write-Host "Get-MpComputerStatus not available (Defender may not be the active AV product)."
}

Write-Host ""
Write-Host "Done. This is a point-in-time snapshot, not a compliance report."

