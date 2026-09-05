<#
.SYNOPSIS
    Lists every listening TCP/UDP endpoint with its owning process, and
    optionally flags anything not on an allowlist.

.PARAMETER AllowListPath
    Path to a text file listing allowed endpoints, one "TCP:PORT" or
    "UDP:PORT" per line ('#' comments and blank lines ignored). Anything
    listening that isn't on this list is flagged. Without this parameter
    the script is purely informational.

.EXAMPLE
    .\Listening-Ports-Audit.ps1

.EXAMPLE
    .\Listening-Ports-Audit.ps1 -AllowListPath C:\Baselines\ports.txt
#>

[CmdletBinding()]
param(
    [string]$AllowListPath = ''
)

$ErrorActionPreference = 'Stop'

function Get-OwningProcessName {
    param([int]$ProcessId)
    try { (Get-Process -Id $ProcessId -ErrorAction Stop).ProcessName }
    catch { '(unknown)' }
}

Write-Host "=== Listening TCP endpoints ==="
$tcp = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess,
        @{N='Process'; E={ Get-OwningProcessName $_.OwningProcess }} |
    Sort-Object LocalPort
$tcp | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== Listening UDP endpoints ==="
$udp = Get-NetUDPEndpoint -ErrorAction SilentlyContinue |
    Select-Object LocalAddress, LocalPort, OwningProcess,
        @{N='Process'; E={ Get-OwningProcessName $_.OwningProcess }} |
    Sort-Object LocalPort
$udp | Format-Table -AutoSize | Out-String | Write-Host

if (-not $AllowListPath) {
    Write-Host "No allowlist given (-AllowListPath) — informational only."
    exit 0
}

if (-not (Test-Path $AllowListPath)) {
    Write-Warning "Allowlist file '$AllowListPath' not found."
    exit 2
}

$allowed = Get-Content $AllowListPath |
    ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
    Where-Object { $_ } |
    ForEach-Object { $_.ToUpper() }

$seen = @()
$tcp | ForEach-Object { $seen += "TCP:$($_.LocalPort)" }
$udp | ForEach-Object { $seen += "UDP:$($_.LocalPort)" }
$seen = $seen | Sort-Object -Unique

Write-Host "=== Endpoints not on $AllowListPath ==="
$flagged = $false
foreach ($key in $seen) {
    if ($allowed -notcontains $key) {
        Write-Host "  FLAG: $key is listening but not allowlisted"
        $flagged = $true
    }
}

Write-Host ""
if ($flagged) {
    Write-Host "RESULT: unexpected listening port(s) found."
    exit 1
}
Write-Host "RESULT: every listening port is allowlisted."
exit 0
