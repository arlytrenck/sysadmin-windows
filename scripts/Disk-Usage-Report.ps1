<#
.SYNOPSIS
    Reports free space on all fixed drives and the largest subfolders on a
    given path, with an optional alert threshold.

.PARAMETER Path
    Folder to break down by subfolder size (default: C:\).

.PARAMETER Top
    Number of largest subfolders to show (default: 10).

.PARAMETER ThresholdPercentFree
    If any fixed drive's free space percentage drops below this value, exit
    with a non-zero code after printing the report (default: 10).

.EXAMPLE
    .\Disk-Usage-Report.ps1 -Path D:\Data -Top 15 -ThresholdPercentFree 15
#>

[CmdletBinding()]
param(
    [string]$Path = 'C:\',
    [int]$Top = 10,
    [int]$ThresholdPercentFree = 10
)

$ErrorActionPreference = 'Stop'

Write-Host "=== Fixed drive usage ==="
$alert = $false
$drives = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"
foreach ($drive in $drives) {
    $freeGB  = [math]::Round($drive.FreeSpace / 1GB, 1)
    $totalGB = [math]::Round($drive.Size / 1GB, 1)
    $pctFree = if ($drive.Size -gt 0) { [math]::Round(($drive.FreeSpace / $drive.Size) * 100, 1) } else { 0 }
    $flag = ''
    if ($pctFree -lt $ThresholdPercentFree) {
        $alert = $true
        $flag = '  <-- below threshold'
    }
    "{0,-4} {1,8:N1} GB free / {2,8:N1} GB total  ({3,5:N1}% free){4}" -f $drive.DeviceID, $freeGB, $totalGB, $pctFree, $flag | Write-Host
}

Write-Host ""
Write-Host "=== Top $Top largest subfolders under $Path ==="
try {
    $items = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue
    $sizes = foreach ($item in $items) {
        $size = (Get-ChildItem -Path $item.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum
        [PSCustomObject]@{
            Path   = $item.FullName
            SizeGB = [math]::Round(($size / 1GB), 2)
        }
    }
    $sizes | Sort-Object SizeGB -Descending | Select-Object -First $Top |
        Format-Table -AutoSize | Out-String | Write-Host
} catch {
    Write-Warning "Could not enumerate '$Path': $_"
}

if ($alert) {
    Write-Warning "One or more drives are below the ${ThresholdPercentFree}% free-space threshold."
    exit 1
}

exit 0

