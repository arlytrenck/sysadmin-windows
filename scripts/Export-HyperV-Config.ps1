<#
.SYNOPSIS
    Captures the Hyper-V host and VM configuration to a single JSON file:
    host settings, virtual switches, and per-VM CPU/memory/network/disk/
    checkpoint/integration-service settings.

.DESCRIPTION
    Read-only; makes no changes and does not export VHDs. Intended to be run
    on a schedule and committed to a repo so VM config drift is visible and a
    rebuild reference exists. Pair with Compare-Config-Drift.ps1 (the VM list
    compares by the 'name' key).

    Requires the Hyper-V PowerShell module and an elevated session.

.PARAMETER OutDir
    Directory to write into. Default: .\hyperv-snapshots
    File: hyperv-<hostname>-<yyyyMMdd-HHmmss>.json

.PARAMETER Compress
    Write compact JSON instead of indented.

.EXAMPLE
    .\Export-HyperV-Config.ps1 -OutDir C:\ops\snapshots
#>
[CmdletBinding()]
param(
    [string]$OutDir = (Join-Path -Path (Get-Location) -ChildPath 'hyperv-snapshots'),
    [switch]$Compress
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw "Hyper-V PowerShell module not available. Install the Hyper-V feature / RSAT."
}

function Get-Safe {
    param([scriptblock]$Block, [string]$Label)
    try { & $Block }
    catch { Write-Warning "$Label`: $($_.Exception.Message)"; return $null }
}

Write-Host "Collecting Hyper-V configuration for $env:COMPUTERNAME ..."

$snapshot = [ordered]@{
    meta = [ordered]@{
        hostname  = $env:COMPUTERNAME
        collected = (Get-Date).ToString('o')
        collector = 'Export-HyperV-Config.ps1'
    }

    host = Get-Safe {
        Get-VMHost | Select-Object `
            VirtualMachinePath, VirtualHardDiskPath,
            MaximumStorageMigrations, MaximumVirtualMachineMigrations,
            NumaSpanningEnabled, EnableEnhancedSessionMode,
            @{ N = 'LiveMigration'; E = { $_.VirtualMachineMigrationEnabled } }
    } 'host'

    virtualSwitches = Get-Safe {
        Get-VMSwitch | Select-Object Name, SwitchType, AllowManagementOS,
            NetAdapterInterfaceDescription,
            @{ N = 'Bandwidth'; E = { $_.BandwidthReservationMode } }
    } 'virtualSwitches'

    vms = Get-Safe {
        Get-VM | ForEach-Object {
            $vm = $_
            [ordered]@{
                name              = $vm.Name
                state             = "$($vm.State)"
                generation        = $vm.Generation
                version           = $vm.Version
                processorCount    = $vm.ProcessorCount
                memory            = [ordered]@{
                    startupMB   = [int]($vm.MemoryStartup / 1MB)
                    minimumMB   = [int]($vm.MemoryMinimum / 1MB)
                    maximumMB   = [int]($vm.MemoryMaximum / 1MB)
                    dynamic     = $vm.DynamicMemoryEnabled
                }
                automaticStart    = "$($vm.AutomaticStartAction)"
                automaticStop     = "$($vm.AutomaticStopAction)"
                checkpointType    = "$($vm.CheckpointType)"
                checkpoints       = (Get-Safe { (Get-VMSnapshot -VMName $vm.Name).Name } "checkpoints $($vm.Name)")
                integration       = (Get-Safe {
                    Get-VMIntegrationService -VMName $vm.Name |
                        Select-Object Name, Enabled
                } "integration $($vm.Name)")
                network           = (Get-Safe {
                    Get-VMNetworkAdapter -VMName $vm.Name |
                        Select-Object Name, SwitchName,
                            @{ N = 'MAC';  E = { $_.MacAddress } },
                            @{ N = 'VLAN'; E = { (Get-VMNetworkAdapterVlan -VMNetworkAdapter $_).AccessVlanId } }
                } "network $($vm.Name)")
                disks             = (Get-Safe {
                    Get-VMHardDiskDrive -VMName $vm.Name | ForEach-Object {
                        $p = $_.Path
                        [ordered]@{
                            path       = $p
                            controller = "$($_.ControllerType)$($_.ControllerNumber):$($_.ControllerLocation)"
                            sizeGB     = (Get-Safe { [int]((Get-VHD -Path $p).Size / 1GB) } "vhd $p")
                            type       = (Get-Safe { "$((Get-VHD -Path $p).VhdType)" } "vhdtype $p")
                        }
                    }
                } "disks $($vm.Name)")
            }
        }
    } 'vms'
}

if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$file = Join-Path $OutDir ("hyperv-{0}-{1}.json" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmmss'))

$json = if ($Compress) { $snapshot | ConvertTo-Json -Depth 10 -Compress }
        else            { $snapshot | ConvertTo-Json -Depth 10 }
Set-Content -Path $file -Value $json -Encoding UTF8

Write-Host "Wrote $file"
Write-Output $file
