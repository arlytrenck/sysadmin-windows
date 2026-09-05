# Windows Storage Cheatsheet

Disk, volume, and Storage Spaces management from PowerShell, plus the
NTFS permission and file-sharing commands that come up alongside it. For
Linux's equivalent (partitions, LVM, filesystems), see the companion repo's
[lvm-disk-partitioning-cheatsheet.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/lvm-disk-partitioning-cheatsheet.md).

## Identify what's there before touching anything

```powershell
Get-Disk                                # every physical/virtual disk, size, partition style
Get-Partition                           # every partition across all disks
Get-Volume                               # every volume, drive letter, filesystem, health
Get-PhysicalDisk                         # media type (SSD/HDD), health status, bus type
Get-PhysicalDisk | Get-StorageReliabilityCounter   # SMART-equivalent wear/error counters
```
See [Disk-Health-Check.ps1](../scripts/Disk-Health-Check.ps1) for a script
wrapping the reliability-counter check with thresholds.

## Initializing and partitioning a new disk

```powershell
Get-Disk | Where-Object PartitionStyle -eq 'RAW'          # newly attached, unformatted disks
Initialize-Disk -Number 2 -PartitionStyle GPT
New-Partition -DiskNumber 2 -UseMaximumSize -DriveLetter D
Format-Volume -DriveLetter D -FileSystem NTFS -NewFileSystemLabel "Data"
```
One-liner version, new disk to ready-to-use volume:
```powershell
Get-Disk -Number 2 | Initialize-Disk -PartitionStyle GPT -PassThru |
    New-Partition -UseMaximumSize -AssignDriveLetter |
    Format-Volume -FileSystem NTFS -NewFileSystemLabel "Data" -Confirm:$false
```

## Growing a volume

```powershell
Get-PartitionSupportedSize -DriveLetter D          # min/max size the partition can be resized to
Resize-Partition -DriveLetter D -Size (Get-PartitionSupportedSize -DriveLetter D).SizeMax
```
Growing works online for most cases; shrinking a volume with data near
the end of the partition may need a defrag pass first
(`Optimize-Volume -DriveLetter D -Defrag`).

## Storage Spaces (software RAID-equivalent, local or shared SAS enclosures)

```powershell
Get-StoragePool                                                  # existing pools
Get-PhysicalDisk -CanPool $true                                   # disks available to pool
New-StoragePool -FriendlyName "Pool1" -StorageSubSystemFriendlyName "Windows Storage*" `
    -PhysicalDisks (Get-PhysicalDisk -CanPool $true)
New-VirtualDisk -StoragePoolFriendlyName "Pool1" -FriendlyName "VDisk1" `
    -ResiliencySettingName Mirror -UseMaximumSize
Get-VirtualDisk | Get-StorageJob                                  # in-progress resync/repair status
```
`ResiliencySettingName`: `Simple` (no redundancy, striping only), `Mirror`
(survive a disk loss, like RAID1/10), `Parity` (like RAID5/6 — better
capacity, much slower on HDDs, avoid for anything latency-sensitive).

## NTFS permissions

```powershell
Get-Acl C:\Data | Format-List                              # current ACL
icacls C:\Data                                              # human-friendly ACL dump
icacls C:\Data /grant "DOMAIN\svc-app:(OI)(CI)M"            # grant Modify, inherit down
icacls C:\Data /remove "DOMAIN\OldGroup"
icacls C:\Data /reset /T                                     # reset to inherited-only, recursive
(Get-Acl C:\Data).Access | Select IdentityReference, FileSystemRights, AccessControlType
```
`icacls` is usually faster to read/write than `Get-Acl`/`Set-Acl` for a
quick change; use `Get-Acl`/`Set-Acl` when the change needs to be built
programmatically (copying one ACL onto many paths, for example).

## SMB shares

```powershell
Get-SmbShare
New-SmbShare -Name "Data" -Path "D:\Data" -FullAccess "DOMAIN\Admins" -ChangeAccess "DOMAIN\Users"
Grant-SmbShareAccess -Name "Data" -AccountName "DOMAIN\NewGroup" -AccessRight Change
Get-SmbShareAccess -Name "Data"                              # share-level permissions
Remove-SmbShare -Name "Data"
```
Share-level permissions (`Get-SmbShareAccess`) and NTFS permissions
(`icacls`/`Get-Acl`) are evaluated together — the effective access is
whichever is *more restrictive*. A share granting Full Control on top of
NTFS Read still only allows Read.

## Volume health and maintenance

```powershell
Repair-Volume -DriveLetter D -Scan                # chkdsk-equivalent, read-only scan
Repair-Volume -DriveLetter D -OfflineScanAndFix    # full chkdsk /f, needs a reboot for the boot volume
Optimize-Volume -DriveLetter D -Analyze            # fragmentation report
Optimize-Volume -DriveLetter D -Defrag             # defragment (HDD) or -ReTrim (SSD)
```

## Notes

- `Get-Volume`/`Get-Partition` return live objects — filter/select on them
  directly rather than parsing text the way older `diskpart` scripts had
  to.
- Prefer Mirror over Parity for Storage Spaces virtual disks backing
  anything latency-sensitive (databases, VM storage) — parity's write
  penalty is much larger on spinning disks than the RAID5/6 analogy
  suggests.
- Confirm `Get-PartitionSupportedSize` before a shrink — Windows will
  refuse to shrink past whatever unmovable files currently sit near the
  end of the volume, and the error message alone doesn't make that
  obvious.
