# Hyper-V Cheatsheet

Managing a Hyper-V host from PowerShell — VMs, checkpoints, virtual switches,
storage, replica, and the export/import path. The host-config snapshot script
is [Export-HyperV-Config.ps1](../scripts/Export-HyperV-Config.ps1). Run
elevated; the `Hyper-V` PowerShell module ships with the role.

## Host

```powershell
Get-VMHost | Select VirtualMachinePath,VirtualHardDiskPath,NumaSpanningEnabled,MacAddressMinimum,MacAddressMaximum
Set-VMHost -VirtualMachinePath D:\VMs -VirtualHardDiskPath D:\VHDs
Get-VM | Sort-Object State,Name | Format-Table Name,State,CPUUsage,MemoryAssigned,Uptime,Status
Get-VMHostNumaNode
```

## VM lifecycle

```powershell
New-VM -Name web01 -Generation 2 -MemoryStartupBytes 4GB -Path D:\VMs `
  -NewVHDPath D:\VHDs\web01.vhdx -NewVHDSizeBytes 60GB -SwitchName 'vSwitch-LAN'

Start-VM web01
Stop-VM web01                     # graceful (integration services)
Stop-VM web01 -TurnOff            # hard power off — last resort
Restart-VM web01 -Force
Suspend-VM web01 ; Resume-VM web01
Remove-VM web01 -Force            # removes the VM config, NOT the VHDX files
```

## CPU / memory / firmware

```powershell
Set-VM web01 -ProcessorCount 4 -DynamicMemory -MemoryMinimumBytes 2GB `
  -MemoryStartupBytes 4GB -MemoryMaximumBytes 8GB
Set-VM web01 -StaticMemory -MemoryStartupBytes 8GB          # for DBs / latency-sensitive
Set-VM web01 -AutomaticStartAction StartIfRunning -AutomaticStartDelay 30 `
  -AutomaticStopAction ShutDown
Set-VMProcessor web01 -ExposeVirtualizationExtensions $true # nested virtualization
Set-VMFirmware web01 -EnableSecureBoot On -SecureBootTemplate 'MicrosoftWindows'
Set-VMFirmware web01 -SecureBootTemplate 'MicrosoftUEFICertificateAuthority'  # Linux guests
Get-VMFirmware web01 | Select -ExpandProperty BootOrder
```

Gen 2 = UEFI, SCSI boot, Secure Boot, no legacy emulation — use it for any
modern guest. Gen 1 only for old OSes or PXE-from-legacy-NIC needs.

## Virtual switches

```powershell
Get-VMSwitch
New-VMSwitch -Name 'vSwitch-LAN' -NetAdapterName 'Ethernet' -AllowManagementOS $true
New-VMSwitch -Name 'vSwitch-Internal' -SwitchType Internal
New-VMSwitch -Name 'vSwitch-Private'  -SwitchType Private

# NIC / VLAN / bandwidth on a VM
Add-VMNetworkAdapter web01 -SwitchName 'vSwitch-LAN' -Name 'LAN'
Set-VMNetworkAdapterVlan web01 -Access -VlanId 20
Set-VMNetworkAdapter web01 -MinimumBandwidthWeight 30
Set-VMNetworkAdapter web01 -MacAddressSpoofing On           # needed for nested/containers/NLB in guest
Get-VMNetworkAdapter -All | Select VMName,SwitchName,IPAddresses,MacAddress
```

`-AllowManagementOS $true` on an External switch shares the host's NIC with
the host itself; on a dedicated storage/cluster NIC set it `$false`.

## Storage / VHDX

```powershell
New-VHD -Path D:\VHDs\data.vhdx -SizeBytes 200GB -Dynamic
Add-VMHardDiskDrive web01 -Path D:\VHDs\data.vhdx -ControllerType SCSI
Resize-VHD -Path D:\VHDs\web01.vhdx -SizeBytes 100GB        # grow (offline for shrink)
# then extend the partition inside the guest

Optimize-VHD -Path D:\VHDs\web01.vhdx -Mode Full            # reclaim — VM must be off or disk offline
Get-VHD D:\VHDs\web01.vhdx | Select Path,VhdType,Size,FileSize,FragmentationPercentage
Test-VHD D:\VHDs\web01.vhdx                                 # integrity check

Mount-VHD  D:\VHDs\web01.vhdx -ReadOnly                     # inspect a stopped VM's disk from the host
Dismount-VHD D:\VHDs\web01.vhdx
```

Avoid differencing disks and pass-through disks in production; they trade a
little space for a lot of operational pain.

## Checkpoints (snapshots)

```powershell
Set-VM web01 -CheckpointType Production                     # VSS-consistent; Standard = crash-consistent
Checkpoint-VM web01 -SnapshotName 'pre-change 2026-05-01'
Get-VMSnapshot web01 | Select Name,CreationTime,ParentSnapshotName,SnapshotType
Restore-VMSnapshot -Name 'pre-change 2026-05-01' -VMName web01 -Confirm:$false
Remove-VMSnapshot web01 -Name 'pre-change 2026-05-01'       # merges the AVHDX back
Remove-VMSnapshot web01 -IncludeAllChildSnapshots           # clear a tree
```

Checkpoints are **not backups**: they live on the same disk, and a long-lived
checkpoint's AVHDX grows until it fills the volume. Delete them within days.
Never checkpoint a domain controller or a replicated database on a
non-Production checkpoint type.

## Export / import / move

```powershell
Export-VM web01 -Path E:\Exports\                           # full copy: config + VHDX + checkpoints
Import-VM -Path 'E:\Exports\web01\Virtual Machines\<GUID>.vmcx'                 # register in place
Import-VM -Path '...<GUID>.vmcx' -Copy -GenerateNewId -VhdDestinationPath D:\VHDs\  # clone

Move-VM web01 -DestinationHost hv02 -IncludeStorage -DestinationStoragePath D:\VMs\web01   # live migrate (needs setup)
Move-VMStorage web01 -DestinationStoragePath E:\VMs\web01   # storage-only, VM stays running
Compare-VM -Path '...vmcx'                                  # dry-run an import, see incompatibilities
```

## Replica (DR)

```powershell
Get-VMReplicationServer
Enable-VMReplication web01 -ReplicaServerName hv-dr -ReplicaServerPort 80 -AuthenticationType Kerberos
Start-VMInitialReplication web01
Measure-VMReplication | Select Name,State,Health,LastReplicationTime,AverageReplicationSize
Start-VMFailover web01 -Prepare        # on primary
Start-VMFailover web01                 # on replica — bring it up
Complete-VMFailover web01              # commit, after you've confirmed it's good
```

## Integration services / guest

```powershell
Get-VMIntegrationService web01 | Select Name,Enabled,PrimaryStatusDescription
Enable-VMIntegrationService web01 -Name 'Guest Service Interface'
Copy-VMFile web01 -SourcePath C:\pkg\agent.msi -DestinationPath C:\Windows\Temp\agent.msi `
  -FileSource Host -CreateFullPath                          # needs Guest Service Interface
```

## Health / troubleshooting

```powershell
Get-VM | Where-Object Status -ne 'Operating normally'
Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-Worker-Admin' -MaxEvents 50
Get-WinEvent -LogName 'Microsoft-Windows-Hyper-V-VMMS-Admin'   -MaxEvents 50
Get-VMHostSupportedVersion
Get-VM web01 | Select -ExpandProperty Version               # bump with Update-VMVersion after a host upgrade
```

Common gotchas: a VM stuck "Stopping" (kill the matching `vmwp.exe` by its
VM GUID as a last resort); a checkpoint that won't merge because the volume
is full (free space, then `Remove-VMSnapshot` again); Secure Boot blocking a
Linux guest (switch the template as above); MAC spoofing off breaking nested
Docker/k8s networking.
