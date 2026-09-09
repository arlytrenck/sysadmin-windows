# Disk Full Emergency Runbook

A volume at or near 100%: services failing to write, SQL Server going
read-only, logons hanging. This is the "stop the bleeding" procedure. See
also [Disk-Usage-Report.ps1](../scripts/Disk-Usage-Report.ps1) and
[Log-Cleanup.ps1](../scripts/Log-Cleanup.ps1). The Linux companion is
[disk-full-emergency-runbook.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/disk-full-emergency-runbook.md)
in sysadmin-linux — same procedure shape, different culprits.

## 0. Confirm and locate

```powershell
Get-Volume | Select-Object DriveLetter, FileSystemLabel, SizeRemaining, Size |
    Sort-Object SizeRemaining
Get-PSDrive -PSProvider FileSystem

# which physical disk backs the volume that's full
Get-Partition -DriveLetter D | Get-Disk
```

If `C:` itself is full, even simple commands (profile load, event log
writes) may start failing. Free a little breathing room first (step 2),
then investigate properly.

## 1. Find the space

```powershell
# biggest top-level folders under the full volume, one level at a time
Get-ChildItem D:\ -Directory | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        SizeGB = [math]::Round((Get-ChildItem $_.FullName -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum / 1GB, 2)
    }
} | Sort-Object SizeGB -Descending | Select-Object -First 15 | Format-Table -AutoSize

# biggest individual files
Get-ChildItem D:\ -Recurse -File -ErrorAction SilentlyContinue |
    Sort-Object Length -Descending | Select-Object -First 20 FullName,
    @{ N='SizeMB'; E={ [math]::Round($_.Length / 1MB, 1) } }
```

`Get-ChildItem -Recurse` on a large volume is slow. For a genuinely fast
whole-tree view, use a purpose-built tool (WizTree, TreeSize, or
`du.exe` from Sysinternals) rather than waiting on the above.

### The classic culprit: shadow copies, not files

Deleting files on Windows often doesn't free the space you expect,
because **Volume Shadow Copy (VSS)** storage keeps the old blocks for
System Restore, Previous Versions, and — the big one — any backup
product that uses VSS snapshots. `Get-ChildItem` and Explorer are both
blind to this; `Get-Volume` still counts it as used.

```powershell
vssadmin list shadowstorage
vssadmin list shadows /for=D:

# how much space VSS is ALLOWED to use on this volume - often set to
# "unbounded" (100%) by default, which is how this silently eats a disk
vssadmin list shadowstorage /for=D:

# cap it, then delete the oldest shadows to reclaim space now
vssadmin resize shadowstorage /for=D: /on=D: /maxsize=10GB
vssadmin delete shadows /for=D: /oldest
```

Confirm nothing needs those shadow copies (a pending backup job, a
restore point someone's relying on) before deleting them.

## 2. Safe things to delete/reclaim, in order

```powershell
# Disk Cleanup's own logic, from the command line - safe, well-tested
cleanmgr /sagerun:1

# component store (WinSxS) - accumulates every superseded update; this
# is usually the single biggest win on an older Server install
Dism.exe /Online /Cleanup-Image /AnalyzeComponentStore
Dism.exe /Online /Cleanup-Image /StartComponentCleanup

# a prior in-place upgrade's old OS, if still present (10+ GB, typically
# only needed for the first ~10 days after the upgrade)
Get-ChildItem C:\Windows.old -ErrorAction SilentlyContinue
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase   # also removes update rollback

# hibernation file, if hibernate/fast startup isn't needed on a server
powercfg /hibernate off

# Recycle Bin, all drives
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

# temp files actually in use are locked and skipped safely
Get-ChildItem $env:TEMP, 'C:\Windows\Temp' -Recurse -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

# memory dumps from a prior crash
Remove-Item C:\Windows\Minidump\* , C:\Windows\MEMORY.DMP -Force -ErrorAction SilentlyContinue
```

### IIS and application logs

```powershell
# IIS logs - can be tens of GB on a busy, long-running server
Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -File |
    Measure-Object -Property Length -Sum | Select-Object @{N='GB';E={$_.Sum/1GB}}
Get-ChildItem C:\inetpub\logs\LogFiles -Recurse -File | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) |
    Remove-Item -Force

# Windows Update download cache - safe to clear, re-downloads as needed
Stop-Service wuauserv
Remove-Item C:\Windows\SoftwareDistribution\Download\* -Recurse -Force -ErrorAction SilentlyContinue
Start-Service wuauserv
```

### SQL Server

A database that filled the disk usually left a bloated transaction log,
not bloated data. Do **not** delete `.ldf`/`.mdf` files by hand. Free
space elsewhere first, get the instance responsive, then let SQL Server
handle its own log properly:

```powershell
# which database, and how big is the log vs. the data
Invoke-Sqlcmd -Query "SELECT name, size/128.0 AS SizeMB, [FILE_ID] FROM sys.master_files"

# a log stuck at 100% is usually an open transaction or a broken log
# backup chain (log won't truncate under the FULL recovery model without one)
Invoke-Sqlcmd -Query "SELECT name, log_reuse_wait_desc FROM sys.databases"

# once you understand WHY (do not skip the step above), reclaim space:
Invoke-Sqlcmd -Query "BACKUP LOG [MyDb] TO DISK = 'D:\Backups\MyDb_log.trn'"
Invoke-Sqlcmd -Query "DBCC SHRINKFILE (MyDb_log, 1024)"   # target size in MB
```

Shrinking without a log backup first (under the FULL recovery model) is
what turns "disk full" into "no way to restore past this point" —
resist the urge to shrink first and understand why later.

## 3. If you truly cannot free anything on that mount

- **Extend the volume**, if free unallocated space exists on the disk:
  ```powershell
  Get-PartitionSupportedSize -DriveLetter D
  Resize-Partition -DriveLetter D -Size (Get-PartitionSupportedSize -DriveLetter D).SizeMax
  ```
- **Add a disk and extend via Storage Spaces / a new virtual disk**, then
  extend the volume onto it. See
  [windows-storage-cheatsheet.md](windows-storage-cheatsheet.md).
- **Move a large, self-contained folder** to another volume and replace
  it with a junction, so the application keeps its original path:
  ```powershell
  Stop-Service MyAppService
  robocopy D:\AppData E:\AppData /E /COPYALL /MOVE
  New-Item -ItemType Junction -Path D:\AppData -Target E:\AppData
  Start-Service MyAppService
  ```
  See [robocopy-cheatsheet.md](robocopy-cheatsheet.md) for the retry
  flags a move like this should always carry.

## 4. Verify and recover services

```powershell
Get-Volume -DriveLetter D
Get-Service | Where-Object Status -ne 'Running' | Select-Object Name, Status, StartType
# restart anything that stopped or went into a degraded state while the
# volume was full
Restart-Service MyAppService, MSSQLSERVER -ErrorAction SilentlyContinue
Get-WinEvent -LogName System -MaxEvents 50 |
    Where-Object LevelDisplayName -in 'Error', 'Critical'
```

A SQL Server database left in `RECOVERY_PENDING` or `SUSPECT` after a
full-disk event needs an explicit
`ALTER DATABASE ... SET ONLINE` once space is confirmed available, not
just a service restart.

## 5. Prevent the recurrence

- Alert on a volume at **80%** and on the **fill rate**, not just a hard
  threshold. See
  [monitoring-alerting-guide.md](monitoring-alerting-guide.md).
- Cap VSS shadow storage (`vssadmin resize shadowstorage`) on every
  volume a backup product snapshots — "unbounded" is the default and is
  how this happens again.
- Put IIS/application log rotation in place; don't rely on someone
  noticing.
- Give SQL Server data and log files their own volume, separate from the
  OS, so a runaway log can't take down the host.
- Run `Dism.exe /StartComponentCleanup` on a schedule rather than only
  during an emergency — the component store grows every patch cycle.
- Record what filled it in the change log / a
  [postmortem](incident-postmortem-template.md).
