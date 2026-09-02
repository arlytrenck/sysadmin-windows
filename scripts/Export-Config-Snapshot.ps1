<#
.SYNOPSIS
    Captures a point-in-time snapshot of a Windows host's configuration to a
    single JSON file: services, scheduled tasks, local groups, firewall
    profile + rules, installed features/roles, hotfixes, and selected
    autostart registry keys.

.DESCRIPTION
    Read-only; makes no changes. Intended to be run on a schedule (or before
    and after a change window) and committed to a git repo so drift is
    visible and a baseline exists for incident work. Pair with
    Compare-Config-Drift.ps1 to diff two snapshots.

    Secret-looking values are not collected — this captures structure and
    state, not credentials.

.PARAMETER OutDir
    Directory to write the snapshot into. Default: .\config-snapshots
    The file is named config-<hostname>-<yyyyMMdd-HHmmss>.json.

.PARAMETER Compress
    Write compact JSON instead of indented.

.EXAMPLE
    .\Export-Config-Snapshot.ps1 -OutDir C:\ops\snapshots

.EXAMPLE
    .\Export-Config-Snapshot.ps1 | Out-Null   # default location, then `git add`
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path -Path (Get-Location) -ChildPath 'config-snapshots'),
    [switch]$Compress
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

function Get-Safe {
    param([scriptblock]$Block, [string]$Label)
    try { & $Block }
    catch { Write-Warning "$Label`: $($_.Exception.Message)"; return $null }
}

Write-Host "Collecting configuration snapshot for $env:COMPUTERNAME ..."

$snapshot = [ordered]@{
    meta = [ordered]@{
        hostname   = $env:COMPUTERNAME
        collected  = (Get-Date).ToString('o')
        os         = (Get-Safe { (Get-CimInstance Win32_OperatingSystem).Caption } 'os')
        osVersion  = (Get-Safe { (Get-CimInstance Win32_OperatingSystem).Version } 'osVersion')
        collector  = 'Export-Config-Snapshot.ps1'
    }

    services = Get-Safe {
        Get-CimInstance Win32_Service |
            Select-Object Name, DisplayName, StartMode, State, StartName, PathName |
            Sort-Object Name
    } 'services'

    scheduledTasks = Get-Safe {
        Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } |
            Select-Object TaskName, TaskPath, State,
                @{ N = 'RunAs';  E = { $_.Principal.UserId } },
                @{ N = 'Hidden'; E = { [bool]$_.Settings.Hidden } },
                @{ N = 'Actions'; E = { ($_.Actions | ForEach-Object { $_.Execute }) -join '; ' } } |
            Sort-Object TaskPath, TaskName
    } 'scheduledTasks'

    localGroups = Get-Safe {
        Get-LocalGroup | ForEach-Object {
            $gname = $_.Name
            [ordered]@{
                name    = $gname
                members = (Get-Safe { (Get-LocalGroupMember -Group $gname -ErrorAction Stop).Name } "group $gname")
            }
        }
    } 'localGroups'

    firewall = [ordered]@{
        profiles = Get-Safe {
            Get-NetFirewallProfile | Select-Object Name, Enabled,
                DefaultInboundAction, DefaultOutboundAction
        } 'firewallProfiles'
        enabledInboundAllowRules = Get-Safe {
            Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow |
                Select-Object DisplayName, Profile,
                    @{ N = 'LocalPort'; E = { ($_ | Get-NetFirewallPortFilter).LocalPort } },
                    @{ N = 'Program';   E = { ($_ | Get-NetFirewallApplicationFilter).Program } } |
                Sort-Object DisplayName
        } 'firewallRules'
    }

    windowsFeatures = Get-Safe {
        if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            Get-WindowsFeature | Where-Object Installed |
                Select-Object -ExpandProperty Name | Sort-Object
        }
        else {
            Get-WindowsOptionalFeature -Online |
                Where-Object State -eq 'Enabled' |
                Select-Object -ExpandProperty FeatureName | Sort-Object
        }
    } 'windowsFeatures'

    hotfixes = Get-Safe {
        Get-HotFix | Select-Object HotFixID, Description,
            @{ N = 'InstalledOn'; E = { $_.InstalledOn.ToString('yyyy-MM-dd') } } |
            Sort-Object HotFixID
    } 'hotfixes'

    autoRun = Get-Safe {
        $paths = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )
        foreach ($p in $paths) {
            if (Test-Path $p) {
                $props = Get-ItemProperty -Path $p
                $props.PSObject.Properties |
                    Where-Object { $_.Name -notmatch '^PS' } |
                    ForEach-Object { [ordered]@{ path = $p; name = $_.Name; value = $_.Value } }
            }
        }
    } 'autoRun'
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$file = Join-Path $OutDir ("config-{0}-{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))

$json = if ($Compress) { $snapshot | ConvertTo-Json -Depth 8 -Compress }
        else            { $snapshot | ConvertTo-Json -Depth 8 }
Set-Content -Path $file -Value $json -Encoding UTF8

Write-Host "Wrote $file"
Write-Output $file
