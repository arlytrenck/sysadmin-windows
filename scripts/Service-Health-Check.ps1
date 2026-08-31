<#
.SYNOPSIS
    Checks the status of one or more Windows services and optionally
    restarts any that aren't running.

.PARAMETER ServiceNames
    Service names (not display names) to check. Use -List to discover names.

.PARAMETER List
    Instead of checking, list all services and their current status.

.PARAMETER Restart
    Attempt to start any service found stopped.

.EXAMPLE
    .\Service-Health-Check.ps1 -ServiceNames W3SVC, MSSQLSERVER -Restart

.EXAMPLE
    .\Service-Health-Check.ps1 -List
#>

[CmdletBinding()]
param(
    [string[]]$ServiceNames = @(),
    [switch]$List,
    [switch]$Restart
)

$ErrorActionPreference = 'Stop'

if ($List) {
    Get-Service | Sort-Object Status, Name |
        Format-Table Name, DisplayName, Status, StartType -AutoSize | Out-String | Write-Host
    exit 0
}

if ($ServiceNames.Count -eq 0) {
    throw "Specify -ServiceNames <name1,name2,...> or use -List to see available services."
}

$anyDown = $false

foreach ($name in $ServiceNames) {
    $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Warning "Service '$name' not found."
        $anyDown = $true
        continue
    }

    if ($svc.Status -eq 'Running') {
        Write-Host "[OK]      $name ($($svc.DisplayName)) is running"
    } else {
        $anyDown = $true
        Write-Warning "[DOWN]    $name ($($svc.DisplayName)) is $($svc.Status)"
        if ($Restart) {
            try {
                Start-Service -Name $name
                Start-Sleep -Seconds 2
                $svc.Refresh()
                if ($svc.Status -eq 'Running') {
                    Write-Host "  Restarted successfully."
                } else {
                    Write-Warning "  Restart attempted but service is now: $($svc.Status)"
                }
            } catch {
                Write-Warning "  Failed to restart '$name': $_"
            }
        }
    }
}

if ($anyDown) { exit 1 } else { exit 0 }

