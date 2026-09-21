<#
.SYNOPSIS
    Dumps active Windows Firewall rules to a timestamped file, for backup,
    review, or diffing against a previous snapshot.

.PARAMETER OutputDir
    Directory to write the timestamped dump to (default: current
    directory).

.PARAMETER BaselineFile
    Previous dump file to diff the new snapshot against. The dump is one
    pipe-delimited line per rule; a baseline written by an older version of
    this script (a padded table) will show every line as changed once,
    until it is replaced with a dump in the new format.

.PARAMETER EnabledOnly
    Only dump rules that are currently enabled (default: all rules).

.EXAMPLE
    .\Firewall-Rules-Dump.ps1 -OutputDir C:\Reports -EnabledOnly
#>

[CmdletBinding()]
param(
    [string]$OutputDir = '.',
    [string]$BaselineFile = '',
    [switch]$EnabledOnly
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$outFile = Join-Path $OutputDir "firewall-$env:COMPUTERNAME-$timestamp.txt"

$rules = Get-NetFirewallRule
if ($EnabledOnly) {
    $rules = $rules | Where-Object { $_.Enabled -eq 'True' }
}

# Fetch every port and address filter once and index them by rule id. Piping
# each rule into Get-NetFirewallPortFilter costs a separate CIM round trip per
# rule, which on a host with a few hundred rules takes minutes.
$portFilters = @{}
foreach ($f in @(Get-NetFirewallPortFilter -All -ErrorAction SilentlyContinue)) { $portFilters[$f.InstanceID] = $f }
$addressFilters = @{}
foreach ($f in @(Get-NetFirewallAddressFilter -All -ErrorAction SilentlyContinue)) { $addressFilters[$f.InstanceID] = $f }

$lines = foreach ($rule in $rules) {
    $portFilter = $portFilters[$rule.InstanceID]
    $addressFilter = $addressFilters[$rule.InstanceID]
    [PSCustomObject]@{
        Name          = $rule.Name
        DisplayName   = $rule.DisplayName
        Enabled       = $rule.Enabled
        Direction     = $rule.Direction
        Action        = $rule.Action
        Profile       = $rule.Profile
        Protocol      = $portFilter.Protocol
        LocalPort     = $portFilter.LocalPort
        RemoteAddress = $addressFilter.RemoteAddress
    }
}

# One pipe-delimited line per rule, not a Format-Table. A table is padded to its
# widest cell, so a single longer rule name reflows every line and the baseline
# diff below reports the whole file as changed. Sorting on the rule Name (the
# unique id) keeps the order stable when DisplayNames repeat.
$delimited = @('# Name|DisplayName|Enabled|Direction|Action|Profile|Protocol|LocalPort|RemoteAddress')
$delimited += foreach ($line in ($lines | Sort-Object Name)) {
    ($line.Name, $line.DisplayName, $line.Enabled, $line.Direction, $line.Action, $line.Profile,
     $line.Protocol, (@($line.LocalPort) -join ','), (@($line.RemoteAddress) -join ',')) -join '|'
}

# Also capture the firewall profile state alongside the rule dump
$delimited += '# Profile|Enabled|DefaultInboundAction|DefaultOutboundAction'
$delimited += foreach ($p in (Get-NetFirewallProfile | Sort-Object Name)) {
    "PROFILE|$($p.Name)|$($p.Enabled)|$($p.DefaultInboundAction)|$($p.DefaultOutboundAction)"
}

$delimited | Set-Content -Path $outFile -Encoding UTF8

Write-Host "Wrote $(@($lines).Count) firewall rule(s) to $outFile"

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
