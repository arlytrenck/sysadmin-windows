# Scheduled Tasks Cheatsheet

Creating, inspecting, and debugging Windows scheduled tasks from
PowerShell. Task Scheduler is where most Windows automation actually
lives, and it is also where automation quietly stops working without
telling anyone. For Linux's equivalent, see the companion repo's
[cron-and-timers-cheatsheet.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/cron-and-timers-cheatsheet.md).

Auditing existing tasks for security problems — SYSTEM tasks, hidden
tasks, executables in user-writable paths — is
[Scheduled-Task-Audit.ps1](../scripts/Scheduled-Task-Audit.ps1).

## Inspecting what exists

```powershell
Get-ScheduledTask                                   # every task, all folders
Get-ScheduledTask -TaskPath '\MyJobs\'              # one folder
Get-ScheduledTask | Where-Object State -eq 'Ready'  # enabled and waiting

# The run history is a SEPARATE cmdlet. This is the one you actually want.
Get-ScheduledTaskInfo -TaskName 'Nightly Backup'

# Everything, joined, sorted by how long since it last ran
Get-ScheduledTask | ForEach-Object {
    $info = $_ | Get-ScheduledTaskInfo
    [pscustomobject]@{
        Name       = $_.TaskName
        Path       = $_.TaskPath
        State      = $_.State
        LastRun    = $info.LastRunTime
        LastResult = '0x{0:X}' -f $info.LastTaskResult
        NextRun    = $info.NextRunTime
    }
} | Sort-Object LastRun | Format-Table -AutoSize
```

Look at the action and the account a task actually runs as:

```powershell
$t = Get-ScheduledTask -TaskName 'Nightly Backup'
$t.Actions   | Format-List Execute, Arguments, WorkingDirectory
$t.Principal | Format-List UserId, LogonType, RunLevel
$t.Triggers  | Format-List
$t.Settings  | Format-List ExecutionTimeLimit, MultipleInstances, StartWhenAvailable
```

## Last Run Result: the codes you will actually see

`LastTaskResult` is where a broken task announces itself, and the useful
values are not obvious. It is conventionally read as hex.

| Code | Hex | Meaning |
|---|---|---|
| 0 | 0x0 | Success |
| 1 | 0x1 | Incorrect function — usually the action's own exit code |
| 2 | 0x2 | File not found — check `Execute` and `WorkingDirectory` |
| 267009 | 0x41301 | Task is currently running |
| 267010 | 0x41302 | Task is disabled |
| 267011 | 0x41303 | Task has not yet run |
| 267014 | 0x41306 | Task was terminated by the user or by its time limit |
| 2147942401 | 0x80070001 | Incorrect function |
| 2147942402 | 0x80070002 | The system cannot find the file specified |
| 2147942405 | 0x80070005 | Access denied — the principal lacks rights |
| 2147943645 | 0x8007045D | The device is not ready |

**A non-zero result is not automatically a failure.** The result is the
exit code of whatever the task ran, so a task running robocopy will
report `0x1` on a perfectly healthy night — see
[robocopy-cheatsheet.md](robocopy-cheatsheet.md#exit-codes-read-this-before-scripting-it).
If you alert on "LastTaskResult -ne 0" you will alert every night.

`0x41303` (never run) on a task that was created months ago is the
finding worth chasing: it means the trigger has never fired.

## Creating a task

The four pieces are always the same: an **action** (what to run), a
**trigger** (when), a **principal** (as whom), and **settings** (how it
behaves when things go sideways).

```powershell
$action = New-ScheduledTaskAction `
    -Execute 'powershell.exe' `
    -Argument '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Scripts\Backup-Rotate.ps1" -Source D:\Data -Destination E:\Backups' `
    -WorkingDirectory 'C:\Scripts'

$trigger = New-ScheduledTaskTrigger -Daily -At 2:30am

# SYSTEM: no password to rotate, but it has no network identity and no
# mapped drives. Use a service account when the task touches a share.
$principal = New-ScheduledTaskPrincipal `
    -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -DontStopOnIdleEnd `
    -ExecutionTimeLimit (New-TimeSpan -Hours 4) `
    -MultipleInstances IgnoreNew `
    -RestartCount 2 -RestartInterval (New-TimeSpan -Minutes 10)

Register-ScheduledTask -TaskName 'Nightly Backup' -TaskPath '\MyJobs\' `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Rotates D:\Data into E:\Backups, keeps 14 archives.'
```

`-StartWhenAvailable` is what makes a task run after a missed window
(the server was off at 2:30am). Without it, a missed daily trigger is
simply skipped and nothing tells you.

`-MultipleInstances IgnoreNew` prevents a slow job from stacking on top
of itself — the failure mode where a backup that now takes 25 hours
spawns a second copy competing with the first.

## Triggers worth knowing

```powershell
New-ScheduledTaskTrigger -Daily -At 2:30am
New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 3am
New-ScheduledTaskTrigger -AtStartup
New-ScheduledTaskTrigger -AtLogOn -User 'CONTOSO\svc-app'

# Every 15 minutes, indefinitely - repetition is set on a trigger, not
# created as its own trigger type.
$t = New-ScheduledTaskTrigger -Once -At (Get-Date)
$t.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration ([TimeSpan]::MaxValue)).Repetition
```

Event-driven triggers have no cmdlet and must be built as CIM instances
or imported from XML — the XML route below is far easier to read.

## Running as the right account

| Principal | Password to manage | Network access | Use when |
|---|---|---|---|
| `SYSTEM` | None | Computer account | Local-only work |
| `NETWORK SERVICE` | None | Computer account | Local, lower privilege |
| Domain user | Yes, and it expires | Full user identity | Needs a share or SQL |
| gMSA | Managed by AD | Full | The right answer for domain services |

A group Managed Service Account removes the password rotation problem
entirely:

```powershell
# On the server, after the gMSA is created and this host is authorised
Install-ADServiceAccount -Identity 'svc-backup'
Test-ADServiceAccount   -Identity 'svc-backup'

$principal = New-ScheduledTaskPrincipal -UserId 'CONTOSO\svc-backup$' `
    -LogonType Password -RunLevel Highest
```

To run as a normal domain account, supply the credential at registration
time. The password is stored by the service, not by the task XML:

```powershell
$cred = Get-Credential 'CONTOSO\svc-backup'
Register-ScheduledTask -TaskName 'Nightly Backup' -Action $action -Trigger $trigger `
    -User $cred.UserName -Password $cred.GetNetworkCredential().Password -RunLevel Highest
```

The task also needs the **"Log on as a batch job"** right, or it fails
with `0x80070569` regardless of how correct everything else is. That
right is granted per-machine in local policy or by GPO — see
[group-policy-reference.md](group-policy-reference.md).

## Managing tasks

```powershell
Start-ScheduledTask    -TaskName 'Nightly Backup'   # run it now, ignore the trigger
Stop-ScheduledTask     -TaskName 'Nightly Backup'
Disable-ScheduledTask  -TaskName 'Nightly Backup'
Enable-ScheduledTask   -TaskName 'Nightly Backup'
Unregister-ScheduledTask -TaskName 'Nightly Backup' -Confirm:$false

# Change one property without rebuilding the whole task
Set-ScheduledTask -TaskName 'Nightly Backup' -Trigger (New-ScheduledTaskTrigger -Daily -At 4am)
```

## Export and import as XML

XML is the format to keep in version control, and the only practical way
to move a task between hosts or to build triggers the cmdlets do not
expose.

```powershell
# Export
Export-ScheduledTask -TaskName 'Nightly Backup' -TaskPath '\MyJobs\' |
    Out-File C:\Config\nightly-backup.xml -Encoding Unicode

# Import onto another host
Register-ScheduledTask -TaskName 'Nightly Backup' -TaskPath '\MyJobs\' `
    -Xml (Get-Content C:\Config\nightly-backup.xml -Raw) `
    -User 'CONTOSO\svc-backup' -Password $plain
```

`Export-ScheduledTask` emits UTF-16, and `Register-ScheduledTask -Xml`
expects it. Saving as UTF-8 is a common reason an import fails with a
vague schema error.

## Why a task "runs" but does nothing

Almost every silent scheduled-task failure is one of these:

- **No `-NoProfile`.** The account's PowerShell profile runs first and
  may fail or prompt. Always pass
  `-NoProfile -NonInteractive -ExecutionPolicy Bypass`.
- **Relative paths.** The default working directory is
  `C:\Windows\System32`, not the script's folder. Set
  `-WorkingDirectory`, or use absolute paths everywhere.
- **Mapped drives do not exist.** Drive letters are per-session. A task
  running as SYSTEM has no `Z:`. Use UNC paths.
- **SYSTEM has no network identity of its own.** It reaches the network
  as `DOMAIN\COMPUTERNAME$`, so the share must grant that computer
  account access.
- **"Run only when user is logged on"** was left selected, and nobody is
  logged on at 2am. That is `-LogonType Interactive`; you want
  `ServiceAccount` or `Password`.
- **Quoting.** `-Argument` is one string that Task Scheduler passes
  verbatim. A path with spaces needs inner quotes:
  `-File "C:\Program Files\x\y.ps1"`.
- **The script exits 0 on failure.** Task Scheduler reports what the
  process returned. If your script swallows errors, the task looks
  healthy forever.

Reproduce the environment rather than guessing at it:

```powershell
# Run the exact command line the task uses, as SYSTEM, using PsExec
psexec -s -i powershell.exe -NoProfile -File C:\Scripts\thing.ps1
```

## The task event log

The history tab is a view over an event log you can query directly,
which is what you want for anything beyond one task:

```powershell
# Enable history if it is off (it is off by default on Server)
wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true

# 201 = action completed (carries the return code), 101 = start failed,
# 103 = action start failed, 111 = terminated
Get-WinEvent -FilterHashtable @{
    LogName   = 'Microsoft-Windows-TaskScheduler/Operational'
    Id        = 101, 103, 111, 201
    StartTime = (Get-Date).AddDays(-7)
} | Select-Object TimeCreated, Id, Message | Format-List
```

## schtasks equivalents

`schtasks.exe` still works everywhere and is occasionally the faster
path, particularly against an older host:

```cmd
schtasks /Query /FO LIST /V /TN "Nightly Backup"
schtasks /Run   /TN "Nightly Backup"
schtasks /Change /TN "Nightly Backup" /DISABLE
schtasks /Create /TN "Nightly Backup" /TR "powershell -NoProfile -File C:\Scripts\b.ps1" ^
         /SC DAILY /ST 02:30 /RU SYSTEM /RL HIGHEST
schtasks /Delete /TN "Nightly Backup" /F
```
