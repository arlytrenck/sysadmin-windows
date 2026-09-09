# Secret Rotation Runbook

A repeatable procedure for rotating a credential on Windows — a service
account password, an API token, a certificate private key, a local
administrator password — with minimal downtime and a clean rollback.
Applies whether the secret leaked, someone left, or it is simply overdue.

The Linux companion is
[secret-rotation-runbook.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/secret-rotation-runbook.md).
The procedure is the same; where the secret hides is not.

## When to rotate

- **Now, unscheduled:** the value turned up in a git history, a log, a
  chat message, a screenshot, a GPO preference, or a departing
  administrator's laptop. Assume compromise, and rotate before the
  post-mortem is finished rather than after.
- **Scheduled:** long-lived service account passwords on a calendar,
  after an audit finding, or on a compliance requirement.

If it may have leaked, look for damage done with the old value —
unfamiliar logons, new accounts, changed group membership — both before
and after rotating. [User-Activity-Report.ps1](../scripts/User-Activity-Report.ps1)
and [Local-Admin-Audit.ps1](../scripts/Local-Admin-Audit.ps1) are the
starting points.

## Before you touch anything

**1. Inventory every place the secret is used.** A service account
password is rarely in one place, and the copy you forget is the one that
locks the account out at 3am.

```powershell
# Scheduled tasks running as this account, across every host you manage
Get-ScheduledTask | Where-Object { $_.Principal.UserId -match 'svc-app' } |
    Select-Object TaskPath, TaskName, @{ N='RunAs'; E={ $_.Principal.UserId } }

# Services running as this account
Get-CimInstance Win32_Service | Where-Object StartName -match 'svc-app' |
    Select-Object Name, StartName, State, StartMode

# IIS application pools
Import-Module WebAdministration
Get-ChildItem IIS:\AppPools | Where-Object { $_.processModel.userName -match 'svc-app' } |
    Select-Object Name, @{ N='User'; E={ $_.processModel.userName } }

# COM+ identities, DCOM, and ODBC DSNs are the ones people forget
Get-CimInstance Win32_DCOMApplicationSetting | Where-Object RunAsUser -match 'svc-app'
```

Then, off-host: SQL Server linked servers and credentials, connection
strings in `web.config` and `appsettings.json`, CI/CD variables, backup
software job credentials, monitoring agents, mapped drive scripts, and
the password manager entry itself.

**2. Know how each consumer reloads.** A service needs a restart. An IIS
app pool needs a recycle. A scheduled task stores the password in the
Credential Manager vault and needs re-registering. None of them pick up
a new password on their own.

**3. Confirm you can roll back.** For an AD account that means knowing
you can set the password back; for a certificate it means still holding
the old PFX. Do not rotate a credential whose old value you have already
destroyed.

**4. Check the account is not the one you are logged in with.** Rotating
the password of the account running your own remote session ends the
session.

## Rotation with an overlap window (preferred)

Where the platform allows two valid credentials at once, use it. There
is no downtime and the rollback is "stop using the new one".

Applies to: API tokens that support multiple active keys, certificates
(old and new are both valid until the old expires), and Azure AD / Entra
app registrations with two client secrets.

1. **Issue the new value** without revoking the old.
2. **Deploy the new value** to one consumer. Verify it works.
3. **Roll the remaining consumers**, verifying as you go.
4. **Watch for use of the old value.** For an app registration, sign-in
   logs show which secret was used. Wait at least one full business
   cycle — a weekly job that still holds the old secret will not fail
   until the weekend.
5. **Revoke the old value.** Rotation is not finished until this is
   done; an un-revoked old secret is still a live credential.

## Rotation without overlap (single-value)

Windows service account passwords are the common case, and there is a
brief window where things are broken. Schedule it.

1. Announce the window and stop the dependent services deliberately,
   rather than letting them fail:
   ```powershell
   Stop-Service -Name 'MyAppService'
   Stop-WebAppPool -Name 'MyAppPool'
   ```
2. Change the password:
   ```powershell
   # Domain account
   Set-ADAccountPassword -Identity 'svc-app' -Reset `
       -NewPassword (Read-Host -AsSecureString 'New password')

   # Local account
   Set-LocalUser -Name 'svc-app' -Password (Read-Host -AsSecureString 'New password')
   ```
3. Update every consumer from the inventory:
   ```powershell
   # A service
   $svc = Get-CimInstance Win32_Service -Filter "Name='MyAppService'"
   $svc | Invoke-CimMethod -MethodName Change -Arguments @{
       StartName     = 'CONTOSO\svc-app'
       StartPassword = $plain
   }

   # An IIS app pool
   Set-ItemProperty IIS:\AppPools\MyAppPool -Name processModel.password -Value $plain

   # A scheduled task - re-register, it cannot be edited in place
   $task = Get-ScheduledTask -TaskName 'Nightly Job'
   Register-ScheduledTask -TaskName 'Nightly Job' -TaskPath $task.TaskPath `
       -Action $task.Actions -Trigger $task.Triggers -Settings $task.Settings `
       -User 'CONTOSO\svc-app' -Password $plain -Force
   ```
4. Start services and verify before declaring it done.

## The rotation you should not have to do

Two mechanisms remove service account password rotation entirely, and
both are worth adopting instead of getting better at this runbook:

- **gMSA** (group Managed Service Account) — Active Directory rotates the
  password every 30 days and no human ever sees it.
  ```powershell
  New-ADServiceAccount -Name 'svc-app' -DNSHostName 'app01.contoso.com' `
      -PrincipalsAllowedToRetrieveManagedPassword 'AppServers'
  Install-ADServiceAccount -Identity 'svc-app'
  Test-ADServiceAccount   -Identity 'svc-app'
  ```
  See [scheduled-tasks-cheatsheet.md](scheduled-tasks-cheatsheet.md) for
  wiring one into a task.

- **LAPS** (Windows LAPS, built in on current builds) — randomises the
  local administrator password per machine and stores it in AD or Entra.
  It turns "the local admin password leaked" from a fleet-wide emergency
  into a single-machine event.
  ```powershell
  Get-LapsADPassword -Identity 'SERVER01' -AsPlainText
  Reset-LapsPassword -Identity 'SERVER01'
  ```

## Storing the new value

- A password manager or a secret store, never a text file, never a
  spreadsheet, never a GPO preference. **Group Policy Preferences
  passwords are readable by any authenticated domain user** — the key
  that encrypts them is published. If you find one, treat that
  credential as already compromised.
- If a script must read it, use a secret store or a DPAPI-protected
  file, scoped to the account that needs it:
  ```powershell
  # Encrypted with the machine/user DPAPI key - only this account,
  # on this machine, can read it back.
  $sec = Read-Host -AsSecureString 'Value'
  $sec | ConvertFrom-SecureString | Set-Content C:\secure\app.cred

  $sec = Get-Content C:\secure\app.cred | ConvertTo-SecureString
  ```
  `ConvertFrom-SecureString -Key` with a hardcoded key is not protection;
  the key sits next to the ciphertext in the same script.
- Record the rotation date and the next due date somewhere a human will
  look. See [change-management-checklist.md](change-management-checklist.md).

## Verify

```powershell
# The account is not locked and the new password authenticates
Get-ADUser 'svc-app' -Properties LockedOut, PasswordLastSet, PasswordExpired |
    Select-Object Name, LockedOut, PasswordLastSet, PasswordExpired

# Services came back on the new value
Get-Service 'MyAppService' | Select-Object Name, Status, StartType

# Nothing is failing to log on with the old one. 4625 = failed logon,
# 4740 = account locked out.
Get-WinEvent -FilterHashtable @{
    LogName = 'Security'; Id = 4625, 4740; StartTime = (Get-Date).AddHours(-2)
} | Select-Object TimeCreated, Id, @{ N='Account'; E={ $_.Properties[5].Value } }
```

A stream of 4625s after a rotation is a consumer you missed in the
inventory. The account name and the source workstation in the event will
tell you which one.

## After rotation

- **Revoke the old value** if it was an overlap rotation.
- **Confirm nothing still uses it** for at least one full weekly cycle,
  then again after a month for anything monthly.
- **Re-run the exposure check.** If the secret leaked into a git
  history, rotating does not remove it from the history — the old value
  is still there for anyone reading the repo, and any *other* secret in
  that history needs rotating too.
- **Write down what the inventory missed.** The list of places a secret
  hides is the durable output of this exercise, and it is only ever
  learned by getting it wrong once.

## Per-type quick notes

| Secret | Overlap possible | Watch out for |
|---|---|---|
| Domain service account | No | Scheduled tasks, app pools, SQL, linked servers |
| Local admin password | No | Use LAPS instead of rotating by hand |
| Certificate / private key | Yes | New thumbprint breaks every binding — see [certificate-management-reference.md](certificate-management-reference.md) |
| Entra app secret | Yes | Two secrets allowed; revoke the old one deliberately |
| API token | Usually | Whether the vendor lets two keys live at once |
| gMSA | N/A | Nothing to rotate, which is the point |
