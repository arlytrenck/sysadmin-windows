<#
.SYNOPSIS
    Scans for, and optionally installs, Windows Updates, logging the
    outcome to a file.

.DESCRIPTION
    Wraps the PSWindowsUpdate module (installed automatically if missing
    and internet-connected) to provide a scriptable update workflow
    suitable for scheduled maintenance windows.

.PARAMETER Install
    Actually install available updates. Without this, only scans and lists.

.PARAMETER RebootIfNeeded
    Reboot automatically if an installed update requires it.

.PARAMETER LogPath
    Where to write the log (default: C:\Windows\Temp\windows-update.log).

.EXAMPLE
    .\Windows-Update.ps1 -Install -RebootIfNeeded
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Install,
    [switch]$RebootIfNeeded,
    [string]$LogPath = 'C:\Windows\Temp\windows-update.log'
)

$ErrorActionPreference = 'Stop'

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $LogPath -Value $line
}

if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Log "PSWindowsUpdate module not found; attempting to install from PSGallery."
    if ($PSCmdlet.ShouldProcess('PSWindowsUpdate', 'Install module')) {
        Install-Module -Name PSWindowsUpdate -Force -Scope AllUsers -ErrorAction Stop
    }
}

Import-Module PSWindowsUpdate

Write-Log "Scanning for available updates..."
$updates = Get-WindowsUpdate -ErrorAction SilentlyContinue

if (-not $updates -or $updates.Count -eq 0) {
    Write-Log "No updates available."
    exit 0
}

Write-Log "Found $($updates.Count) update(s):"
foreach ($u in $updates) {
    Write-Log "  - $($u.KB)  $($u.Title)"
}

if (-not $Install) {
    Write-Log "Scan-only mode (pass -Install to apply). Exiting."
    exit 0
}

if ($PSCmdlet.ShouldProcess("$($updates.Count) update(s)", "Install")) {
    Write-Log "Installing updates..."
    $result = Install-WindowsUpdate -AcceptAll -AutoReboot:$false -IgnoreReboot -Confirm:$false -Verbose 4>&1
    $result | ForEach-Object { Write-Log "  $_" }

    $rebootRequired = Get-WURebootStatus -Silent
    if ($rebootRequired) {
        Write-Log "A reboot is required to complete installation."
        if ($RebootIfNeeded) {
            Write-Log "Rebooting now (-RebootIfNeeded was set)."
            Restart-Computer -Force
        } else {
            Write-Log "Reboot NOT performed (pass -RebootIfNeeded to reboot automatically)."
        }
    } else {
        Write-Log "No reboot required."
    }
}

Write-Log "Done."

