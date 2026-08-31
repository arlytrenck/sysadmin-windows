<#
.SYNOPSIS
    Checks physical disk health status and reliability counters (the
    Storage subsystem's equivalent of SMART) and flags anything not
    Healthy, or with a nonzero read/write/wear error count.

.DESCRIPTION
    Read-only. Uses the Storage module (Get-PhysicalDisk /
    Get-StorageReliabilityCounter), available on Windows Server 2012+ and
    Windows 8+. Exits non-zero if anything is flagged, so it's safe to
    wire into a scheduled task + webhook per the monitoring guide.

.EXAMPLE
    .\Disk-Health-Check.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$worst = 0

Write-Host "=== Physical disk health status ==="
$disks = Get-PhysicalDisk
$disks | Select-Object DeviceId, FriendlyName, MediaType, HealthStatus, OperationalStatus |
    Format-Table -AutoSize | Out-String | Write-Host

foreach ($disk in $disks) {
    if ($disk.HealthStatus -ne 'Healthy') {
        Write-Host "  [WARN] Disk $($disk.DeviceId) ($($disk.FriendlyName)) HealthStatus = $($disk.HealthStatus)"
        $worst = [math]::Max($worst, 2)
    }
    if ($disk.OperationalStatus -ne 'OK') {
        Write-Host "  [WARN] Disk $($disk.DeviceId) ($($disk.FriendlyName)) OperationalStatus = $($disk.OperationalStatus)"
        $worst = [math]::Max($worst, 1)
    }
}

Write-Host ""
Write-Host "=== Reliability counters ==="
foreach ($disk in $disks) {
    try {
        $counters = $disk | Get-StorageReliabilityCounter -ErrorAction Stop
    } catch {
        Write-Host "  Disk $($disk.DeviceId): reliability counters not available ($_)"
        continue
    }

    $line = "Disk {0} ({1}): ReadErrors={2} WriteErrors={3} Temperature={4}C Wear={5}%" -f `
        $disk.DeviceId, $disk.FriendlyName,
        $counters.ReadErrorsTotal, $counters.WriteErrorsTotal,
        $counters.Temperature, $counters.Wear
    Write-Host "  $line"

    if ($counters.ReadErrorsTotal -gt 0 -or $counters.WriteErrorsTotal -gt 0) {
        Write-Host "  [WARN] Disk $($disk.DeviceId) has nonzero read/write errors"
        $worst = [math]::Max($worst, 1)
    }
    if ($counters.Wear -and $counters.Wear -gt 80) {
        Write-Host "  [WARN] Disk $($disk.DeviceId) wear indicator is high ($($counters.Wear)%)"
        $worst = [math]::Max($worst, 1)
    }
}

Write-Host ""
switch ($worst) {
    0 { Write-Host "Result: OK" }
    1 { Write-Host "Result: WARNING - review output above" }
    2 { Write-Host "Result: CRITICAL - review output above" }
}

exit $worst
