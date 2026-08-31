# Windows Server Incident Response Runbook

A general-purpose starting runbook for responding to a suspected security
incident on a Windows server (compromised account, malware, unexpected
access). Adapt to your environment and any regulatory/contractual
notification obligations — those are outside this document's scope.

## 1. Assess

- What triggered the alert — AV/EDR detection, anomalous logon,
  unexpected process, a report from a user?
- Is this host domain-joined? What does it host (data classification,
  dependent services)?
- Check `user-activity-report.ps1` for recent logons, failed logons, and
  lockouts around the suspected timeframe.
- Do NOT immediately reboot or shut down if forensic evidence (memory,
  running processes) may need to be preserved — consult your incident
  response policy first.

## 2. Contain

- If active compromise is confirmed and containment outweighs evidence
  preservation, disconnect networking (disable the NIC, or pull the cable)
  rather than powering off, to preserve volatile state.
- Disable (don't yet delete) any compromised account:
  `.\User-Mgmt.ps1 -Action Disable -UserName <account>`
- If the account is domain-based, also disable it in Active Directory and
  force logoff of any active sessions.
- Isolate the host from sensitive network segments if your network
  segmentation allows targeted isolation (firewall/NAC quarantine VLAN)
  instead of a full outage.

## 3. Diagnose

Useful starting points:

```powershell
# Recent process starts (if Sysmon or process-creation auditing is enabled)
Get-WinEvent -FilterHashtable @{LogName='Microsoft-Windows-Sysmon/Operational'; Id=1} -MaxEvents 50

# Currently running processes and their parent, for anything unfamiliar
Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, Name, CommandLine

# Recently created local accounts or Administrators-group changes
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4720,4732} -MaxEvents 50

# Scheduled tasks (a common persistence mechanism)
Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' } | Select-Object TaskName, TaskPath

.\Security-Audit.ps1
.\Network-Diagnostics.ps1
```

Look for: unfamiliar scheduled tasks or services, unexpected members of
Administrators, new local accounts, listeners on unusual ports, and
processes launched from user-writable directories (Temp, Downloads,
AppData).

## 4. Mitigate

- Remove confirmed persistence mechanisms (scheduled tasks, services,
  run keys) only after you've documented them — don't destroy evidence
  before it's captured if a forensic review is planned.
- Rotate credentials for the affected account(s), and for any account that
  may have been used to move laterally from this host.
- Patch or remediate the specific vulnerability/misconfiguration that
  allowed the incident, once identified — containment alone doesn't fix
  root cause.

## 5. Verify

- Re-run `security-audit.ps1` and confirm findings from step 3 are
  resolved.
- Confirm no unexpected inbound connections remain
  (`network-diagnostics.ps1`).
- Watch the host closely for a period after remediation before
  considering it fully clear.

## 6. Document

- Timeline: when the incident started (best estimate), when detected,
  actions taken and by whom, when resolved.
- Root cause and the specific fix applied.
- Follow-ups: policy or tooling gaps this incident exposed (e.g., audit
  policy wasn't capturing the event you needed).

This runbook assumes no legal/regulatory hold requirements; if one applies,
follow your organization's evidence-handling procedure before altering the
host.

