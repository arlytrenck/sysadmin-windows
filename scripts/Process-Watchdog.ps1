<#
.SYNOPSIS
    Flags processes over a CPU or working-set memory threshold. Read-only
    by default; with -Kill, sends Stop-Process to anything flagged.

.PARAMETER CpuThresholdSeconds
    Flag a process if its total CPU time exceeds this many seconds
    (default: 3600 - one CPU-hour). Windows doesn't expose instantaneous
    %CPU as cheaply as Unix ps; total CPU time is the practical signal
    for "this has been burning CPU for a long time."

.PARAMETER MemThresholdMB
    Flag a process if its working set exceeds this many MB (default:
    2048).

.PARAMETER Kill
    Stop flagged processes (default: report only). Processes named in
    -Protect are reported but never stopped.

.PARAMETER Protect
    Process names -Kill will not touch, however much CPU or memory they
    use. The default covers the ones whose death takes the host down or
    takes a workload with it: the session and security core (csrss,
    lsass, winlogon, services, smss, wininit, svchost), the shell and
    compositor, Defender, Hyper-V's per-VM worker processes (vmwp, vmmem)
    and SQL Server.

.NOTES
    Exit codes: 0 = nothing flagged; 1 = at least one process flagged.

.EXAMPLE
    .\Process-Watchdog.ps1 -CpuThresholdSeconds 1800 -MemThresholdMB 4096
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [int]$CpuThresholdSeconds = 3600,
    [int]$MemThresholdMB = 2048,
    [switch]$Kill,
    [string[]]$Protect = @(
        'Idle', 'System', 'Registry', 'Memory Compression', 'smss', 'csrss', 'wininit',
        'winlogon', 'services', 'lsass', 'svchost', 'fontdrvhost', 'dwm', 'explorer',
        'MsMpEng', 'vmwp', 'vmmem', 'vmms', 'sqlservr'
    )
)

# Reads tolerate a process exiting mid-scan; the kill path below does not, so
# it passes -ErrorAction Stop and reports what actually happened.
$ErrorActionPreference = 'SilentlyContinue'
$flagged = 0

function Stop-Flagged {
    [CmdletBinding(SupportsShouldProcess)]
    param($Process, [string[]]$ProtectedNames)
    if ($ProtectedNames -contains $Process.ProcessName) {
        Write-Host "  Skipping protected process $($Process.ProcessName) (PID $($Process.Id))"
        return
    }
    if ($PSCmdlet.ShouldProcess("$($Process.ProcessName) (PID $($Process.Id))", "Stop-Process")) {
        try {
            Stop-Process -Id $Process.Id -Force -ErrorAction Stop
            Write-Host "  Stopped PID $($Process.Id) ($($Process.ProcessName))"
        } catch {
            Write-Warning "  Could not stop PID $($Process.Id) ($($Process.ProcessName)): $($_.Exception.Message)"
        }
    }
}

$procs = Get-Process | Where-Object { $_.Id -ne 0 -and $_.Id -ne 4 }

Write-Host "=== Processes over $CpuThresholdSeconds CPU-seconds ==="
$overCpu = $procs | Where-Object { $_.CPU -and $_.CPU -gt $CpuThresholdSeconds } | Sort-Object CPU -Descending
if ($overCpu) {
    $overCpu | Select-Object Id, ProcessName, @{N='CPU(s)'; E={[math]::Round($_.CPU,0)}}, @{N='WS(MB)'; E={[math]::Round($_.WorkingSet64/1MB,0)}} |
        Format-Table -AutoSize | Out-String | Write-Host
    $flagged++
    if ($Kill) {
        foreach ($p in $overCpu) { Stop-Flagged -Process $p -ProtectedNames $Protect }
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
        foreach ($p in $overMem) { Stop-Flagged -Process $p -ProtectedNames $Protect }
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
if ($flagged -eq 0) {
    Write-Host "Nothing flagged."
    exit 0
}
Write-Host "$flagged categor(y/ies) flagged above."
exit 1
