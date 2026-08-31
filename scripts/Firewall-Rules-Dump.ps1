<#
.SYNOPSIS
    Dumps active Windows Firewall rules to a timestamped file, for backup,
    review, or diffing against a previous snapshot.

.PARAMETER OutputDir
    Directory to write the timestamped dump to (default: current
    directory).

.PARAMETER BaselineFile
    Previous dump file to diff the new snapshot against.

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

$lines = foreach ($rule in $rules) {
    $portFilter = $rule | Get-NetFirewallPortFilter -ErrorAction SilentlyContinue
    $addressFilter = $rule | Get-NetFirewallAddressFilter -ErrorAction SilentlyContinue
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

$lines | Sort-Object DisplayName | Format-Table -AutoSize | Out-String -Width 300 | Set-Content -Path $outFile -Encoding UTF8

Write-Host "Wrote $($lines.Count) firewall rule(s) to $outFile"

# Also capture the firewall profile state alongside the rule dump
Get-NetFirewallProfile | Format-Table Name, Enabled, DefaultInboundAction, DefaultOutboundAction -AutoSize |
    Out-String | Add-Content -Path $outFile

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
