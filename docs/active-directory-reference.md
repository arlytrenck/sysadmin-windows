# Active Directory & Group Policy Reference

Common commands for day-to-day Active Directory and Group Policy work on a
domain-joined management host with RSAT installed
(`Install-WindowsFeature RSAT-AD-PowerShell` or the equivalent Windows
Capability on client OSes).

## User and group lookups

```powershell
Get-ADUser -Identity jsmith -Properties *
Get-ADUser -Filter "Enabled -eq `$false" -Properties LastLogonDate
Get-ADUser -Filter * -Properties LockedOut | Where-Object LockedOut
Get-ADGroupMember -Identity "Domain Admins"
Get-ADPrincipalGroupMembership -Identity jsmith | Select Name
```

## Account maintenance

```powershell
Unlock-ADAccount -Identity jsmith
Set-ADAccountPassword -Identity jsmith -Reset -NewPassword (Read-Host -AsSecureString)
Set-ADUser -Identity jsmith -Enabled $false
Move-ADObject -Identity "CN=jsmith,OU=Old,DC=example,DC=com" -TargetPath "OU=New,DC=example,DC=com"
```

## Computer objects

```powershell
Get-ADComputer -Filter * -Properties LastLogonDate |
    Where-Object { $_.LastLogonDate -lt (Get-Date).AddDays(-90) }   # stale computer objects
Test-ComputerSecureChannel -Repair                                   # fix a broken machine trust
```

## Group Policy

```powershell
Get-GPO -All | Select DisplayName, GpoStatus, ModificationTime
Get-GPOReport -Name "Default Domain Policy" -ReportType Html -Path .\report.html
gpresult /h report.html /f                       # resultant set of policy for the local machine
gpupdate /force                                  # re-pull and reapply policy
Get-GPInheritance -Target "OU=Servers,DC=example,DC=com"
```

## Replication and domain health

```powershell
repadmin /replsummary
repadmin /showrepl
dcdiag /v                                        # comprehensive domain controller health check
Get-ADDomainController -Filter *
nltest /dsgetdc:example.com
```

## Organizational units and delegation

```powershell
Get-ADOrganizationalUnit -Filter * | Select Name, DistinguishedName
Get-Acl "AD:OU=Servers,DC=example,DC=com" | Select -ExpandProperty Access
```

Delegation is best managed through the Delegation of Control Wizard in
Active Directory Users and Computers for anything beyond a quick read —
ACL edits via `Get-Acl`/`Set-Acl` on `AD:` paths are powerful but easy to
get wrong and hard to audit after the fact.

## Notes

- Prefer OU-linked GPOs with well-scoped security filtering over editing
  the Default Domain Policy directly.
- `dcdiag` and `repadmin /replsummary` are usually the fastest way to tell
  whether a "weird AD behavior" report is actually a replication problem.
- RSAT cmdlets require an available domain controller and appropriate
  permissions; run from a management host, not production member servers,
  where your organization's policy calls for that separation.

