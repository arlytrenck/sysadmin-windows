<#
.SYNOPSIS
    Reports physical memory, commit charge, and pagefile usage, names the
    processes responsible, and flags recent low-memory events. The Windows
    counterpart to a Linux memory/swap pressure check.

.DESCRIPTION
    Free physical memory on its own is a poor health signal on Windows:
    the cache manager will happily consume everything not otherwise
    spoken for, so a healthy server and a dying one can both report very
    little free RAM. Commit charge is the number that matters. It counts
    memory the system has *promised* to processes, backed by RAM plus
    pagefile, and when it approaches the commit limit allocations start
    failing regardless of how much physical RAM looks free.

    This checks three thresholds - available physical, commit charge
    against the commit limit, and pagefile utilisation - then lists the
    top consumers by working set and private bytes so the cause is in the
    same output as the symptom. It also reads the System log for
    Resource-Exhaustion-Detector entries, which is Windows recording that
    it already hit this wall while nobody was looking.

    Read-only. It changes no setting and terminates no process.

.PARAMETER AvailableMinPercent
    Flag if available physical memory falls below this percent of total
    (default: 10).

.PARAMETER CommitMaxPercent
    Flag if commit charge exceeds this percent of the commit limit
    (default: 90). This is the threshold worth alerting on.

.PARAMETER PagefileMaxPercent
    Flag if any pagefile is more than this percent full (default: 75).

.PARAMETER Top
    How many processes to list in each consumer table (default: 10).

.PARAMETER EventDays
    How far back to read low-memory events from the System log
    (default: 7). Set to 0 to skip the event log entirely.

.EXAMPLE
    .\Memory-Pressure-Check.ps1

.EXAMPLE
    .\Memory-Pressure-Check.ps1 -CommitMaxPercent 80 -Top 5 -EventDays 30

.NOTES
    Exit codes: 0 = every threshold clear, 1 = at least one threshold
    exceeded or a low-memory event was found, 2 = memory information
    could not be read.

    Reads Win32_OperatingSystem rather than performance counters on
    purpose: counter names like '\Memory\Committed Bytes' are localised
    and break on non-English installs, while the CIM properties do not.

    Reading the System event log generally needs an elevated session.
#>

[CmdletBinding()]
param(
    [int]$AvailableMinPercent = 10,

    [int]$CommitMaxPercent = 90,

    [int]$PagefileMaxPercent = 75,

    [int]$Top = 10,

    [int]$EventDays = 7
)

$ErrorActionPreference = 'Stop'

try {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
} catch {
    Write-Warning "Could not query Win32_OperatingSystem: $($_.Exception.Message)"
    exit 2
}

$flagged = 0

# Every one of these CIM properties is in kilobytes.
$totalPhysMb  = [math]::Round($os.TotalVisibleMemorySize / 1KB, 0)
$freePhysMb   = [math]::Round($os.FreePhysicalMemory / 1KB, 0)
$commitLimMb  = [math]::Round($os.TotalVirtualMemorySize / 1KB, 0)
$commitFreeMb = [math]::Round($os.FreeVirtualMemory / 1KB, 0)
$commitUsedMb = $commitLimMb - $commitFreeMb

$freePhysPct   = if ($totalPhysMb -gt 0) { [math]::Round(100 * $freePhysMb / $totalPhysMb, 1) } else { 0 }
$commitUsedPct = if ($commitLimMb -gt 0) { [math]::Round(100 * $commitUsedMb / $commitLimMb, 1) } else { 0 }

Write-Host "=== Physical memory ==="
Write-Host ("Total:     {0,8:N0} MB" -f $totalPhysMb)
Write-Host ("Available: {0,8:N0} MB  ({1}%)" -f $freePhysMb, $freePhysPct)
Write-Host ("In use:    {0,8:N0} MB  ({1}%)" -f ($totalPhysMb - $freePhysMb), [math]::Round(100 - $freePhysPct, 1))

if ($freePhysPct -lt $AvailableMinPercent) {
    Write-Host "FLAG: available physical memory is $freePhysPct%, below the $AvailableMinPercent% floor"
    $flagged++
}

Write-Host ""
Write-Host "=== Commit charge ==="
Write-Host ("Commit limit: {0,8:N0} MB   (physical RAM + pagefile)" -f $commitLimMb)
Write-Host ("Committed:    {0,8:N0} MB   ({1}%)" -f $commitUsedMb, $commitUsedPct)
Write-Host ("Headroom:     {0,8:N0} MB" -f $commitFreeMb)

if ($commitUsedPct -gt $CommitMaxPercent) {
    Write-Host "FLAG: commit charge is $commitUsedPct% of the limit, past $CommitMaxPercent% - allocations will start failing before RAM looks full"
    $flagged++
}

Write-Host ""
Write-Host "=== Pagefiles ==="
$pageFiles = @(Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction SilentlyContinue)
if ($pageFiles.Count -eq 0) {
    Write-Host "  No pagefile is configured."
    # Not automatically wrong, but it caps the commit limit at physical RAM
    # and removes any cushion for a burst.
    Write-Host "FLAG: no pagefile - the commit limit is capped at physical RAM, so a spike fails outright instead of paging"
    $flagged++
} else {
    foreach ($pf in $pageFiles) {
        $pfPct = if ($pf.AllocatedBaseSize -gt 0) {
            [math]::Round(100 * $pf.CurrentUsage / $pf.AllocatedBaseSize, 1)
        } else { 0 }
        Write-Host ("  {0}" -f $pf.Name)
        Write-Host ("    Allocated: {0,7:N0} MB   Current: {1,7:N0} MB ({2}%)   Peak: {3,7:N0} MB" -f `
            $pf.AllocatedBaseSize, $pf.CurrentUsage, $pfPct, $pf.PeakUsage)

        if ($pfPct -gt $PagefileMaxPercent) {
            Write-Host "FLAG: $($pf.Name) is $pfPct% used, past $PagefileMaxPercent%"
            $flagged++
        }
        # A peak far above the current usage is the fingerprint of a spike
        # that has already happened and been forgotten.
        if ($pf.AllocatedBaseSize -gt 0 -and
            $pf.PeakUsage -gt ($pf.AllocatedBaseSize * 0.9) -and
            $pf.PeakUsage -gt $pf.CurrentUsage) {
            Write-Host "FLAG: $($pf.Name) peaked at $($pf.PeakUsage) MB of $($pf.AllocatedBaseSize) MB - it has been near exhaustion since boot"
            $flagged++
        }
    }
}

Write-Host ""
Write-Host "=== Top $Top processes by working set ==="
Get-Process |
    Sort-Object -Property WorkingSet64 -Descending |
    Select-Object -First $Top -Property `
        @{ Name = 'Name';       Expression = { $_.ProcessName } },
        @{ Name = 'PID';        Expression = { $_.Id } },
        @{ Name = 'WorkingSet'; Expression = { '{0:N0} MB' -f ($_.WorkingSet64 / 1MB) } },
        @{ Name = 'Private';    Expression = { '{0:N0} MB' -f ($_.PrivateMemorySize64 / 1MB) } } |
    Format-Table -AutoSize | Out-String | Write-Host

# Private bytes is the better ranking for a leak: working set can be trimmed
# by the memory manager, private bytes cannot, so a process climbing here
# while its working set stays flat is still consuming commit.
Write-Host "=== Top $Top processes by private bytes (commit) ==="
Get-Process |
    Sort-Object -Property PrivateMemorySize64 -Descending |
    Select-Object -First $Top -Property `
        @{ Name = 'Name';    Expression = { $_.ProcessName } },
        @{ Name = 'PID';     Expression = { $_.Id } },
        @{ Name = 'Private'; Expression = { '{0:N0} MB' -f ($_.PrivateMemorySize64 / 1MB) } },
        @{ Name = 'Handles'; Expression = { $_.HandleCount } } |
    Format-Table -AutoSize | Out-String | Write-Host

if ($EventDays -gt 0) {
    Write-Host "=== Low-memory events (last $EventDays days) ==="
    $since = (Get-Date).AddDays(-$EventDays)
    $found = 0
    $readable = $true
    try {
        # 2004: Resource-Exhaustion-Detector diagnosed low virtual memory and
        # names the processes that caused it. 2019/2020: the server ran out of
        # nonpaged/paged pool, which is usually a driver rather than a process.
        $events = @(Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            StartTime = $since
            Id        = 2004, 2019, 2020
        } -ErrorAction Stop)

        foreach ($evt in $events) {
            $found++
            Write-Host "FLAG: $($evt.TimeCreated) [$($evt.Id)] $($evt.ProviderName)"
            $message = ($evt.Message -split "`r?`n" | Where-Object { $_.Trim() -ne '' } | Select-Object -First 3) -join ' '
            Write-Host "      $message"
            $flagged++
        }
    } catch [Exception] {
        # Get-WinEvent throws rather than returning an empty set when nothing
        # matches, so "no events" arrives here as an error and is the good case.
        if ($_.Exception.Message -notmatch 'No events were found') {
            Write-Host "  Could not read the System log: $($_.Exception.Message)"
            Write-Host "  (reading it usually needs an elevated session)"
            $readable = $false
        }
    }
    if ($found -eq 0 -and $readable) { Write-Host "  None." }
}

Write-Host ""
if ($flagged -gt 0) {
    Write-Host "RESULT: $flagged memory pressure finding(s)."
    exit 1
}
Write-Host "RESULT: memory, commit charge, and pagefile all within thresholds."
exit 0
