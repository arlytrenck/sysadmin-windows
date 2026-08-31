<#
.SYNOPSIS
    Runs a battery of common network diagnostics: adapters, routing, DNS,
    default gateway reachability, listening ports, and an optional
    host:port reachability sweep.

.PARAMETER Targets
    Optional list of host:port pairs to test reachability for
    (e.g. "dc01:389", "8.8.8.8:53").

.EXAMPLE
    .\Network-Diagnostics.ps1 -Targets "dc01:389","fileserver:445"
#>

[CmdletBinding()]
param(
    [string[]]$Targets = @()
)

$ErrorActionPreference = 'SilentlyContinue'

Write-Host "=== Network adapters and addresses ==="
Get-NetIPConfiguration | Format-Table InterfaceAlias, IPv4Address, IPv4DefaultGateway, DNSServer -AutoSize |
    Out-String | Write-Host

Write-Host "=== Routing table ==="
Get-NetRoute -AddressFamily IPv4 | Where-Object { $_.NextHop -ne '0.0.0.0' -or $_.DestinationPrefix -eq '0.0.0.0/0' } |
    Sort-Object -Property RouteMetric |
    Format-Table DestinationPrefix, NextHop, InterfaceAlias, RouteMetric -AutoSize | Out-String | Write-Host

Write-Host "=== Default gateway reachability ==="
$gateways = (Get-NetIPConfiguration).IPv4DefaultGateway.NextHop | Select-Object -Unique
foreach ($gw in $gateways) {
    if (-not $gw) { continue }
    $result = Test-Connection -ComputerName $gw -Count 2 -Quiet
    if ($result) {
        Write-Host "[OK]   Gateway $gw is reachable"
    } else {
        Write-Warning "[FAIL] Gateway $gw did not respond to ping"
    }
}

Write-Host ""
Write-Host "=== DNS resolution check ==="
try {
    $dnsTest = Resolve-DnsName -Name 'www.microsoft.com' -ErrorAction Stop
    Write-Host "[OK]   DNS resolution working ($($dnsTest[0].IPAddress))"
} catch {
    Write-Warning "[FAIL] DNS resolution failed: $_"
}

Write-Host ""
Write-Host "=== Listening TCP ports ==="
Get-NetTCPConnection -State Listen | Sort-Object LocalPort |
    Select-Object LocalAddress, LocalPort, OwningProcess |
    Format-Table -AutoSize | Out-String | Write-Host

if ($Targets.Count -gt 0) {
    Write-Host "=== Target reachability ==="
    foreach ($target in $Targets) {
        $parts = $target -split ':'
        if ($parts.Count -ne 2) {
            Write-Warning "Skipping malformed target '$target' (expected host:port)"
            continue
        }
        $hostName, $port = $parts
        $test = Test-NetConnection -ComputerName $hostName -Port $port -WarningAction SilentlyContinue
        if ($test.TcpTestSucceeded) {
            Write-Host "[OPEN]   $hostName`:$port"
        } else {
            Write-Warning "[CLOSED] $hostName`:$port"
        }
    }
}

Write-Host ""
Write-Host "Done."

