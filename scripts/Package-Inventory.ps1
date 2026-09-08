<#
.SYNOPSIS
    Dumps installed software to a timestamped file from the registry uninstall
    keys, and optionally diffs against a previous baseline.

.DESCRIPTION
    Reads the machine-wide uninstall keys plus the uninstall key of the user
    running the script. That last part matters for scheduled runs: a task
    running as SYSTEM sees SYSTEM's per-user software, not the console user's,
    so a baseline captured interactively will not line up with one captured by
    a task. Pass -SkipUserScope to inventory machine-wide entries only and get
    a result that is stable regardless of who runs it.

    winget is not merged into the output. If you want winget's own manifest,
    run 'winget export' separately.

.PARAMETER OutputDir
    Directory to write the timestamped inventory file to (default: current
    directory).

.PARAMETER BaselineFile
    Previous inventory file to diff the new snapshot against.

.PARAMETER SkipUserScope
    Ignore HKCU, so the inventory is identical no matter which account runs it.

.PARAMETER FailOnDrift
    Exit 1 when the diff against -BaselineFile is non-empty, so a scheduled
    task or monitoring check can alert on it.

.EXAMPLE
    .\Package-Inventory.ps1 -OutputDir C:\Reports -BaselineFile C:\Reports\packages-baseline.txt

.EXAMPLE
    .\Package-Inventory.ps1 -SkipUserScope -BaselineFile .\baseline.txt -FailOnDrift
#>

[CmdletBinding()]
param(
    [string]$OutputDir = '.',
    [string]$BaselineFile = '',
    [switch]$SkipUserScope,
    [switch]$FailOnDrift
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $OutputDir "packages-$env:COMPUTERNAME-$timestamp.txt"

# Registry-based inventory covers both MSI and most non-MSI installers that
# register an uninstall entry (broader coverage than Win32_Product, which is
# slow and can trigger repair actions as a side effect - avoided here).
$uninstallKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
if (-not $SkipUserScope) {
    $uninstallKeys += 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
}

# Dedupe on name AND version: the same product can legitimately have two
# versions installed, and collapsing on name alone silently drops one and
# picks the surviving version arbitrarily.
$lines = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    ForEach-Object { "$($_.DisplayName)`t$($_.DisplayVersion)" } |
    Sort-Object -Unique

$lines | Set-Content -Path $outFile -Encoding UTF8
Write-Host "Wrote $(@($lines).Count) package entries to $outFile"
if ($SkipUserScope) { Write-Host "(machine-wide scope only)" }

if (-not $BaselineFile) { exit 0 }

if (-not (Test-Path $BaselineFile)) {
    throw "Baseline file '$BaselineFile' not found."
}

# The timestamp only has second resolution, so two runs in the same second
# produce the same output path. If that path is the baseline, the new snapshot
# has already overwritten it and the diff would compare the file to itself.
if ((Resolve-Path $BaselineFile).Path -eq (Resolve-Path $outFile).Path) {
    throw "Baseline file and this run's output are the same file ($outFile). Diff would be meaningless."
}

Write-Host ""
Write-Host "=== Diff against $BaselineFile ==="
$old = @(Get-Content $BaselineFile)
$new = @(Get-Content $outFile)
$diff = @(Compare-Object -ReferenceObject $old -DifferenceObject $new)

if ($diff.Count -eq 0) {
    Write-Host "No change."
    exit 0
}

foreach ($d in $diff) {
    if ($d.SideIndicator -eq '=>') { Write-Host "added:   $($d.InputObject)" }
    else { Write-Host "removed: $($d.InputObject)" }
}
Write-Host "$($diff.Count) difference(s)."

if ($FailOnDrift) { exit 1 }
exit 0
