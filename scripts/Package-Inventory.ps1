<#
.SYNOPSIS
    Dumps installed software (registry-based inventory, plus winget if
    available) to a timestamped file, and optionally diffs against a
    previous baseline.

.PARAMETER OutputDir
    Directory to write the timestamped inventory file to (default: current
    directory).

.PARAMETER BaselineFile
    Previous inventory file to diff the new snapshot against.

.EXAMPLE
    .\Package-Inventory.ps1 -OutputDir C:\Reports -BaselineFile C:\Reports\packages-baseline.txt
#>

[CmdletBinding()]
param(
    [string]$OutputDir = '.',
    [string]$BaselineFile = ''
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $OutputDir "packages-$env:COMPUTERNAME-$timestamp.txt"

# Registry-based inventory covers both MSI and most non-MSI installers that
# register an uninstall entry (broader coverage than Win32_Product, which is
# slow and can trigger repair actions as a side effect — avoided here).
$uninstallKeys = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$packages = Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    Select-Object @{N='Name'; E={$_.DisplayName}}, @{N='Version'; E={$_.DisplayVersion}} |
    Sort-Object Name -Unique

$lines = $packages | ForEach-Object { "$($_.Name)`t$($_.Version)" }

if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "winget detected; note winget list output is not merged into this file automatically —"
    Write-Host "run 'winget export -o winget-packages.json' separately if you need winget's own manifest."
}

$lines | Set-Content -Path $outFile -Encoding UTF8
Write-Host "Wrote $($lines.Count) package entries to $outFile"

if ($BaselineFile) {
    if (-not (Test-Path $BaselineFile)) {
        throw "Baseline file '$BaselineFile' not found."
    }
    Write-Host ""
    Write-Host "=== Diff against $BaselineFile ==="
    $old = Get-Content $BaselineFile
    $new = Get-Content $outFile
    Compare-Object -ReferenceObject $old -DifferenceObject $new |
        ForEach-Object {
            if ($_.SideIndicator -eq '=>') { "added:   $($_.InputObject)" }
            else { "removed: $($_.InputObject)" }
        } | Write-Host
}

