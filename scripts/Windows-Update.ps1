<#
.SYNOPSIS
    Scans for, and optionally installs, Windows Updates, logging the
    outcome to a file.

.DESCRIPTION
    Wraps the PSWindowsUpdate module (installed automatically if missing
    and internet-connected) to provide a scriptable update workflow
    suitable for scheduled maintenance windows.

    The module version is pinned rather than left to float to "whatever
    PSGallery has today". An unattended -Force install of an unpinned
    module is a supply-chain surface on a server: a new release lands on
    every host the next time this runs, with no review and no way to
    reproduce which version acted on an older run's log. Bump
    -ModuleVersion deliberately, on your own schedule, after checking the
    release notes.

.PARAMETER Install
    Actually install available updates. Without this, only scans and lists.

.PARAMETER RebootIfNeeded
    Reboot automatically if an installed update requires it.

.PARAMETER LogPath
    Where to write the log (default: C:\Windows\Temp\windows-update.log).

.PARAMETER ModuleVersion
    Exact PSWindowsUpdate version to require (default: 2.2.1.5, latest on
    PSGallery as of this writing). Installed with -RequiredVersion if not
    already present at that version, and imported with -RequiredVersion so
    a newer or older copy on the host is never picked up silently.

.NOTES
    Exit codes: 0 = scan clean or installs succeeded; 1 = one or more
    updates failed to install; 2 = the update scan itself failed.

.EXAMPLE
    .\Windows-Update.ps1 -Install -RebootIfNeeded

.EXAMPLE
    .\Windows-Update.ps1 -ModuleVersion 2.2.1.4 -Install
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Install,
    [switch]$RebootIfNeeded,
    [string]$LogPath = 'C:\Windows\Temp\windows-update.log',
    [string]$ModuleVersion = '2.2.1.5'
)

$ErrorActionPreference = 'Stop'
$installFailed = $false

$logDir = Split-Path -Parent $LogPath
if ($logDir -and -not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Host $line
    Add-Content -Path $script:LogPath -Value $line
}

$pinned = Get-Module -ListAvailable -Name PSWindowsUpdate |
    Where-Object { $_.Version -eq $ModuleVersion }

if (-not $pinned) {
    Write-Log "PSWindowsUpdate $ModuleVersion not found; installing from PSGallery."
    if ($PSCmdlet.ShouldProcess("PSWindowsUpdate $ModuleVersion", 'Install module')) {
        # Windows PowerShell 5.1 can default to TLS 1.0/1.1 here, which the
        # PSGallery refuses, and the failure reads as "unable to resolve package
        # source". Add TLS 1.2 without dropping whatever else is enabled.
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        Install-Module -Name PSWindowsUpdate -RequiredVersion $ModuleVersion -Force -Scope AllUsers -ErrorAction Stop
    }
}

Import-Module -Name PSWindowsUpdate -RequiredVersion $ModuleVersion -ErrorAction Stop

Write-Log "Scanning for available updates..."
# Not SilentlyContinue: a failed scan (Windows Update service down, no route to
# the update source) would otherwise look identical to "no updates available"
# and exit 0.
try {
    $updates = @(Get-WindowsUpdate -ErrorAction Stop)
} catch {
    Write-Log "Update scan failed: $($_.Exception.Message)"
    exit 2
}

if ($updates.Count -eq 0) {
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

    # Install-WindowsUpdate reports per-update outcomes and does not throw when
    # one fails, so read them rather than assuming the run worked.
    $failedUpdates = @($result | Where-Object { $_.PSObject.Properties['Result'] -and $_.Result -eq 'Failed' })
    if ($failedUpdates.Count -gt 0) {
        Write-Log "$($failedUpdates.Count) update(s) failed to install: $(($failedUpdates | ForEach-Object { $_.KB }) -join ', ')"
        $installFailed = $true
    }

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
if ($installFailed) { exit 1 }

