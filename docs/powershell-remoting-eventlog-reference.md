# PowerShell Remoting & Event Log Reference

Reference for managing servers remotely with PowerShell and for querying
Windows Event Log directly, beyond what the scripts in this repo cover.

## Enabling remoting

```powershell
Enable-PSRemoting -Force                          # on the target server
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "server1,server2" -Force   # on the client, if not domain-joined
Test-WSMan server1                                 # verify remoting is reachable
```

For domain environments, Kerberos handles authentication and
`TrustedHosts` is generally unnecessary; it's mainly a workgroup/cross-forest
concern.

## Running commands remotely

```powershell
Invoke-Command -ComputerName server1 -ScriptBlock { Get-Service | Where Status -ne 'Running' }

Invoke-Command -ComputerName server1, server2, server3 -ScriptBlock {
    Get-CimInstance Win32_OperatingSystem | Select CSName, LastBootUpTime
}

# Interactive session
Enter-PSSession -ComputerName server1
Exit-PSSession

# Persistent session, reused across multiple commands (avoids reconnect overhead)
$session = New-PSSession -ComputerName server1
Invoke-Command -Session $session -ScriptBlock { Get-Process }
Remove-PSSession $session
```

## Running this repo's scripts remotely

```powershell
Invoke-Command -ComputerName server1 -FilePath .\scripts\Service-Health-Check.ps1 -ArgumentList @('W3SVC')

# Or copy first, then run locally on the target (needed for scripts with
# dependencies like the PSWindowsUpdate module):
Copy-Item .\scripts\Windows-Update.ps1 -Destination \\server1\C$\Scripts\ -Force
Invoke-Command -ComputerName server1 -ScriptBlock { C:\Scripts\Windows-Update.ps1 -Install }
```

## CredSSP / double-hop

Commands run via `Invoke-Command` that themselves need to reach a *third*
machine (e.g., a script on server1 that queries a file share on server2)
hit the "double-hop" problem — the remote session's credentials don't
delegate by default. Options, roughly in order of preference:

- Use CIM/WinRM-based cmdlets that support `-CimSession` instead of a
  nested `Invoke-Command`, where available.
- Enable CredSSP (`Enable-WSManCredSSP`) only where necessary — it's
  more permissive than default Kerberos delegation and increases risk if
  the intermediate host is compromised.
- Use constrained Kerberos delegation configured by your AD admins for a
  narrower, audited alternative to CredSSP.

## Querying Event Log

```powershell
# By log name and event ID, with a time window
Get-WinEvent -FilterHashtable @{LogName='System'; Id=6008; StartTime=(Get-Date).AddDays(-7)}

# XPath-based filter for more complex queries
Get-WinEvent -LogName Security -FilterXPath "*[System[(EventID=4625)]]"

# Across multiple remote machines at once
Get-WinEvent -ComputerName server1,server2 -LogName System -MaxEvents 20

# List available log names and their current size/retention
Get-WinEvent -ListLog * | Where-Object RecordCount -gt 0 | Sort-Object RecordCount -Descending

# Change max size / retention behavior for a log
wevtutil sl Security /ms:1073741824 /rt:false     # 1 GB, overwrite as needed
```

## Notes

- `Get-WinEvent` is the modern replacement for `Get-EventLog`; prefer it —
  `Get-EventLog` is limited to classic logs and is officially
  deprecated-in-spirit even though still present.
- Reading the Security log generally requires an elevated session even for
  a local admin account, due to SeSecurityPrivilege.
- For fleet-wide querying, forwarding logs to a central collector
  (Windows Event Forwarding, or a SIEM agent) scales far better than
  `Get-WinEvent -ComputerName` fan-out against dozens of hosts.

