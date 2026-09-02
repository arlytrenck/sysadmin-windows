<#
.SYNOPSIS
    Diffs two JSON snapshots produced by Export-Config-Snapshot.ps1 and reports
    what was added, removed, or changed between them.

.DESCRIPTION
    Read-only. Use it to review drift between a committed baseline and the
    current state, or between the snapshots taken before and after a change
    window. Compares the services, scheduledTasks, localGroups, firewall,
    windowsFeatures, hotfixes, and autoRun sections.

.PARAMETER Baseline
    Path to the older / known-good snapshot JSON.

.PARAMETER Current
    Path to the newer snapshot JSON. Defaults to the most recent
    config-*.json in the Baseline's directory.

.PARAMETER FailOnDrift
    Exit with code 1 if any differences are found (useful in CI / scheduled
    checks). Default exit code is always 0.

.EXAMPLE
    .\Compare-Config-Drift.ps1 -Baseline .\baseline.json -Current .\config-HOST-20260101-030000.json

.EXAMPLE
    .\Compare-Config-Drift.ps1 -Baseline .\snapshots\baseline.json -FailOnDrift
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Baseline,
    [string]$Current,
    [switch]$FailOnDrift
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Baseline)) { throw "Baseline not found: $Baseline" }

if (-not $Current) {
    $dir = Split-Path -Parent (Resolve-Path $Baseline)
    $Current = Get-ChildItem -Path $dir -Filter 'config-*.json' |
        Sort-Object LastWriteTime -Descending |
        Where-Object { $_.FullName -ne (Resolve-Path $Baseline).Path } |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $Current) { throw "No -Current given and no other config-*.json found next to the baseline." }
    Write-Host "Comparing against latest: $Current"
}
if (-not (Test-Path $Current)) { throw "Current not found: $Current" }

$a = Get-Content $Baseline -Raw | ConvertFrom-Json
$b = Get-Content $Current  -Raw | ConvertFrom-Json

$driftFound = $false

function Compare-Section {
    param(
        [string]$Name,
        [object[]]$Old,
        [object[]]$New,
        [string]$Key
    )
    $Old = @($Old); $New = @($New)
    $oldMap = @{}; foreach ($i in $Old) { if ($null -ne $i.$Key) { $oldMap[[string]$i.$Key] = $i } }
    $newMap = @{}; foreach ($i in $New) { if ($null -ne $i.$Key) { $newMap[[string]$i.$Key] = $i } }

    $added   = $newMap.Keys | Where-Object { -not $oldMap.ContainsKey($_) } | Sort-Object
    $removed = $oldMap.Keys | Where-Object { -not $newMap.ContainsKey($_) } | Sort-Object
    $changed = foreach ($k in ($oldMap.Keys | Where-Object { $newMap.ContainsKey($_) } | Sort-Object)) {
        $ojson = $oldMap[$k] | ConvertTo-Json -Depth 6 -Compress
        $njson = $newMap[$k] | ConvertTo-Json -Depth 6 -Compress
        if ($ojson -ne $njson) { $k }
    }

    if ($added -or $removed -or $changed) {
        $script:driftFound = $true
        Write-Host ""
        Write-Host "=== $Name ===" -ForegroundColor Yellow
        foreach ($k in $added)   { Write-Host "  + added   : $k" -ForegroundColor Green }
        foreach ($k in $removed) { Write-Host "  - removed : $k" -ForegroundColor Red }
        foreach ($k in $changed) {
            Write-Host "  ~ changed : $k" -ForegroundColor Cyan
            $od = ($oldMap[$k] | ConvertTo-Json -Depth 6)
            $nd = ($newMap[$k] | ConvertTo-Json -Depth 6)
            ($od -split "`n") | ForEach-Object { Write-Host "      old $_" }
            ($nd -split "`n") | ForEach-Object { Write-Host "      new $_" }
        }
    }
    else {
        Write-Host "=== $Name === no change"
    }
}

Compare-Section -Name 'services'        -Old $a.services        -New $b.services        -Key 'Name'
Compare-Section -Name 'scheduledTasks'  -Old $a.scheduledTasks  -New $b.scheduledTasks  -Key 'TaskName'
Compare-Section -Name 'localGroups'     -Old $a.localGroups     -New $b.localGroups     -Key 'name'
Compare-Section -Name 'firewallProfiles' -Old $a.firewall.profiles -New $b.firewall.profiles -Key 'Name'
Compare-Section -Name 'firewallInboundAllow' -Old $a.firewall.enabledInboundAllowRules -New $b.firewall.enabledInboundAllowRules -Key 'DisplayName'
Compare-Section -Name 'hotfixes'        -Old $a.hotfixes        -New $b.hotfixes        -Key 'HotFixID'
Compare-Section -Name 'autoRun'         -Old $a.autoRun         -New $b.autoRun         -Key 'name'

# windowsFeatures is a flat string array
$fa = @($a.windowsFeatures); $fb = @($b.windowsFeatures)
$fAdded = $fb | Where-Object { $_ -notin $fa }
$fRemoved = $fa | Where-Object { $_ -notin $fb }
if ($fAdded -or $fRemoved) {
    $driftFound = $true
    Write-Host ""
    Write-Host "=== windowsFeatures ===" -ForegroundColor Yellow
    foreach ($f in ($fAdded  | Sort-Object)) { Write-Host "  + added   : $f" -ForegroundColor Green }
    foreach ($f in ($fRemoved | Sort-Object)) { Write-Host "  - removed : $f" -ForegroundColor Red }
}
else { Write-Host "=== windowsFeatures === no change" }

Write-Host ""
if ($driftFound) {
    Write-Host "Drift detected." -ForegroundColor Yellow
    if ($FailOnDrift) { exit 1 }
}
else {
    Write-Host "No drift." -ForegroundColor Green
}
