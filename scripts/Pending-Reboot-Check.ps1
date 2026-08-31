<#
.SYNOPSIS
    Detects whether a Windows host is waiting on a reboot to finish
    applying an update.

.DESCRIPTION
    Checks the standard set of registry locations Windows uses to signal
    a pending reboot:
      - Component-Based Servicing (CBS) RebootPending
      - Windows Update Auto Update RebootRequired
      - PendingFileRenameOperations (a file couldn't be replaced while in
        use, and will be renamed into place on next boot)
      - SCCM/ConfigMgr client reboot-pending WMI property, if present

.EXAMPLE
    .\Pending-Reboot-Check.ps1

.OUTPUTS
    Exit code 0 if no reboot indicators found, 1 if a reboot is pending.
#>

[CmdletBinding()]
param()

$indicators = @()

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') {
    $indicators += 'Component-Based Servicing: RebootPending key present'
}

if (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') {
    $indicators += 'Windows Update: Auto Update RebootRequired key present'
}

$pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name 'PendingFileRenameOperations' -ErrorAction SilentlyContinue
if ($pfro -and $pfro.PendingFileRenameOperations) {
    $indicators += "Session Manager: PendingFileRenameOperations has $($pfro.PendingFileRenameOperations.Count) entries"
}

$cbsRebootInProgress = Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing' -Name 'RebootInProgress' -ErrorAction SilentlyContinue
if ($cbsRebootInProgress) {
    $indicators += 'Component-Based Servicing: RebootInProgress flag set'
}

# ConfigMgr client, if installed, tracks its own reboot-pending state
try {
    $ccmClientUtil = [wmiclass]'ROOT\ccm\ClientSDK:CCM_ClientUtilities'
    $ccmStatus = $ccmClientUtil.DetermineIfRebootPending()
    if ($ccmStatus -and ($ccmStatus.RebootPending -or $ccmStatus.IsHardRebootPending)) {
        $indicators += 'ConfigMgr client: DetermineIfRebootPending() reports a pending reboot'
    }
} catch {
    # ConfigMgr client not installed or WMI namespace unavailable - not an error
}

Write-Host "=== Pending reboot indicators ==="
if ($indicators.Count -eq 0) {
    Write-Host "None found. No reboot appears to be pending."
    exit 0
} else {
    foreach ($i in $indicators) {
        Write-Host "  [FLAG] $i"
    }
    Write-Host ""
    Write-Host "RESULT: reboot recommended ($($indicators.Count) indicator(s) found)."
    exit 1
}
