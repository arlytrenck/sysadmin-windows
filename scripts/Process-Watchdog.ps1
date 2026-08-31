<#
.SYNOPSIS
    Flags processes over a CPU or working-set memory threshold. Read-only
    by default; with -Kill, sends Stop-Process to anything flagged.

.PARAMETER CpuThresholdSeconds
    Flag a process if its total CPU time exceeds this many seconds
    (default: 3600 — one CPU-hour). Windows doesn't expose instantaneous
    %CPU as cheaply as Unix ps; total CPU time is the practical signal
    for "this has been burning CPU for a long time."

.PARAMETER MemThresholdMB
    Flag a process if its working set exceeds this many MB (default:
    2048).

.PARAMETER Kill
    Stop flagged processes (default: report only).

.EXAMPLE
    .\Process-Watchdog.ps1 -CpuThresholdSeconds 1800 -MemThresholdMB 4096
#>

[CmdletBinding()]
param(
    [int]$CpuThresholdSeconds = 3600,
    [int]$MemThresholdMB = 2048,
    [switch]$Kill
)

$ErrorActionPreference = 'SilentlyContinue'
$flagged = 0

$procs = Get-Process | Where-Object { $_.Id -ne 0 -and $_.Id -ne 4 }

Write-Host "=== Processes over $CpuThresholdSeconds CPU-seconds ==="
$overCpu = $procs | Where-Object { $_.CPU -and $_.CPU -gt $CpuThresholdSeconds } | Sort-Object CPU -Descending
if ($overCpu) {
    $overCpu | Select-Object Id, ProcessName, @{N='CPU(s)'; E={[math]::Round($_.CPU,0)}}, @{N='WS(MB)'; E={[math]::Round($_.WorkingSet64/1MB,0)}} |
        Format-Table -AutoSize | Out-String | Write-Host
    $flagged++
    if ($Kill) {
        foreach ($p in $overCpu) {
            Write-Host "  Stopping PID $($p.Id) ($($p.ProcessName))"
            Stop-Process -Id $p.Id -Force
        }
    }
} else {
    Write-Host "None found."
}

Write-Host ""
Write-Host "=== Processes over $MemThresholdMB MB working set ==="
$overMem = $procs | Where-Object { $_.WorkingSet64 -gt ($MemThresholdMB * 1MB) } | Sort-Object WorkingSet64 -Descending
if ($overMem) {
    $overMem | Select-Object Id, ProcessName, @{N='WS(MB)'; E={[math]::Round($_.WorkingSet64/1MB,0)}}, @{N='CPU(s)'; E={[math]::Round($_.CPU,0)}} |
        Format-Table -AutoSize | Out-String | Write-Host
    $flagged++
    if ($Kill) {
        foreach ($p in $overMem) {
            Write-Host "  Stopping PID $($p.Id) ($($p.ProcessName))"
            Stop-Process -Id $p.Id -Force
        }
    }
} else {
    Write-Host "None found."
}

Write-Host ""
Write-Host "=== Processes not responding ==="
$notResponding = $procs | Where-Object { $_.Responding -eq $false }
if ($notResponding) {
    $notResponding | Select-Object Id, ProcessName | Format-Table -AutoSize | Out-String | Write-Host
    $flagged++
} else {
    Write-Host "None found."
}

Write-Host ""
if ($flagged -eq 0) { Write-Host "Nothing flagged." } else { Write-Host "$flagged categor(y/ies) flagged above." }
