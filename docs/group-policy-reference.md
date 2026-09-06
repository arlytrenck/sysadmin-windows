# Group Policy Reference

Working with Group Policy in an AD domain: how it's structured, how to see
what applied and why, editing from PowerShell, and the settings worth
standardizing. Complements
[active-directory-reference.md](active-directory-reference.md). Needs RSAT
(`GroupPolicy` + `ActiveDirectory` modules); run from a management host or a
DC.

## How GPO application works

- A **GPO** is linked to a **site**, **domain**, or **OU**. It applies to
  users/computers in that scope.
- Processing order (later overrides earlier): **L**ocal → **S**ite →
  **D**omain → **O**U (deepest last). "LSDOU".
- **Enforced** link → cannot be overridden by a lower GPO and beats *Block
  Inheritance*.
- **Block Inheritance** on an OU → stops inheriting from above (except
  Enforced links).
- **Security filtering** — a GPO only applies to principals with *Read* +
  *Apply group policy*. Default is `Authenticated Users`.
- **WMI filter** — an extra per-object test (e.g. "only laptops", "only
  Server 2022").
- **Loopback processing** (Merge/Replace) — apply *user* settings based on
  the *computer's* location (kiosks, RDS hosts, servers).
- Refresh: every ~90 min (+ random up to 30) for members, 5 min for DCs, and
  at boot/logon. Force with `gpupdate /force`.

## See what applied (and why)

```powershell
gpupdate /force
gpresult /r                                   # summary for current user+computer
gpresult /h C:\gpresult.html ; ii C:\gpresult.html   # full HTML RSoP report
gpresult /scope computer /v                    # verbose, computer scope only
gpresult /user DOMAIN\alice /s SRV01 /h out.html     # another user, remotely
```

```powershell
Get-GPResultantSetOfPolicy -ReportType Html -Path C:\rsop.html          # local
Get-GPResultantSetOfPolicy -Computer SRV01 -User DOMAIN\alice -ReportType Xml -Path C:\rsop.xml
```

The RSoP report's "Denied GPOs" / "Applied GPOs" and per-setting "Winning
GPO" columns are how you answer "why did this box get that setting".

## Inventory and reporting

```powershell
Get-GPO -All | Sort DisplayName | Select DisplayName,Id,GpoStatus,ModificationTime
Get-GPO -Name 'Server Baseline' | Format-List *
Get-GPOReport -All -ReportType Html -Path C:\all-gpos.html          # every GPO's settings, one file
Get-GPOReport -Name 'Server Baseline' -ReportType Xml -Path C:\baseline.xml

# where is each GPO linked?
(Get-GPInventory) 2>$null
Get-ADOrganizationalUnit -Filter * | ForEach-Object {
  [pscustomobject]@{ OU=$_.DistinguishedName; Links=(Get-GPInheritance -Target $_.DistinguishedName).GpoLinks.DisplayName -join ', ' }
}

# GPOs that are linked nowhere (candidates for cleanup) or empty
Get-GPO -All | Where-Object { $_.User.DSVersion -eq 0 -and $_.Computer.DSVersion -eq 0 }
```

## Create / link / scope from PowerShell

```powershell
New-GPO -Name 'Srv - Audit Policy' -Comment 'Advanced audit baseline'
New-GPLink -Name 'Srv - Audit Policy' -Target 'OU=Servers,DC=corp,DC=example,DC=com' -LinkEnabled Yes
Set-GPLink  -Name 'Srv - Audit Policy' -Target 'OU=Servers,...' -Enforced Yes -Order 1
Set-GPInheritance -Target 'OU=Kiosks,...' -IsBlocked Yes

# security filtering
Set-GPPermission -Name 'Srv - Audit Policy' -TargetName 'Authenticated Users' -PermissionLevel None -Replace
Set-GPPermission -Name 'Srv - Audit Policy' -TargetName 'SG-Servers' -TargetType Group -PermissionLevel GpoApply

# individual registry-backed settings
Set-GPRegistryValue -Name 'Srv - Audit Policy' `
  -Key 'HKLM\Software\Policies\Microsoft\Windows\EventLog\Security' `
  -ValueName MaxSize -Type DWord -Value 196608

# link a WMI filter (must already exist)
$f = Get-ADObject -Filter "objectClass -eq 'msWMI-Som' -and msWMI-Name -eq 'Servers only'" -Properties *
```

For anything beyond registry values (services, security options, scheduled
tasks, drive maps), use **`gpmc.msc`** / **`gpme.msc`** — the PowerShell
module only covers registry-backed policy and Group Policy Preferences
registry items.

## Back up / restore / migrate

```powershell
Backup-GPO -All -Path \\srv\gpo-backups\$(Get-Date -f yyyy-MM-dd)
Backup-GPO -Name 'Server Baseline' -Path C:\gpo-backups
Restore-GPO -Name 'Server Baseline' -Path C:\gpo-backups
Import-GPO -BackupGpoName 'Server Baseline' -TargetName 'Server Baseline v2' `
  -Path C:\gpo-backups -CreateIfNeeded -MigrationTable C:\mig.migtable
```

Schedule `Backup-GPO -All` — GPO changes are otherwise unversioned and
un-undoable. Consider a git repo of the exported `Get-GPOReport` XML so
diffs are reviewable.

## Baseline settings worth standardizing

Prefer Microsoft's **Security Compliance Toolkit** baselines (import the
GPOs, then tune) over hand-authoring:

- **Security Options**: SMB signing required, LM/NTLMv1 disabled, LSA
  protection, UAC on, "Interactive logon: machine inactivity limit".
- **Advanced Audit Policy**: Logon/Logoff, Account Management, Privilege Use,
  Detailed Tracking → Process Creation (+ command line), Object Access as
  needed. Feeds your SIEM.
- **Windows Firewall**: profiles on, inbound block by default (managed
  centrally so local admins can't weaken it).
- **PowerShell**: Module Logging, Script Block Logging, Transcription to a
  protected share.
- **WinRM/WSMan**: HTTPS only, restrict hosts.
- **LAPS** (Windows LAPS on current builds): randomized local Administrator
  password per machine, escrowed in AD.
- **Attack Surface Reduction rules**, Defender exclusions managed centrally.
- **Delivery of updates / restart deadlines** (or hand off to WSUS/Intune).
- **Time**: NT5DS hierarchy for members; the PDC emulator's external source.
- **Screen lock**, drive-map/printer preferences, RDS/loopback where needed.

## Troubleshooting

```powershell
gpupdate /force /wait:0
gpresult /h out.html                                   # start here — Applied vs Denied
Get-WinEvent -LogName 'Microsoft-Windows-GroupPolicy/Operational' -MaxEvents 60
dcgpofix /target:both                                  # LAST RESORT: rebuild the two default GPOs
```

Common causes of "GPO not applying":
- Object is in the wrong OU (GPOs don't follow group membership, only
  location — except security filtering).
- Security filtering / WMI filter excludes it; RSoP shows it under "Denied".
- Slow-link detection skipped it (VPN / metered).
- Replication lag — the DC the client used doesn't have the change yet
  (`repadmin /replsummary`).
- Client-side extension error (check the Operational log).
- A higher **Enforced** GPO is winning; RSoP's "Winning GPO" column names it.
- `SYSVOL` / DFSR not replicating the GPO's files (versions in AD and SYSVOL
  disagree — `Get-GPO` shows both `DSVersion` and `SysvolVersion`).
