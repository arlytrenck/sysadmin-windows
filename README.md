# sysadmin-windows

A collection of Windows Server administration scripts, runbooks, and
reference documentation, gathered from day-to-day homelab and small-fleet
operations. Companion repo to
[sysadmin-linux](https://github.com/arlytrenck/sysadmin-linux), which
covers the same ground for Linux.

## Layout

```
sysadmin-windows/
├── scripts/
│   ├── Backup-Rotate.ps1              # zip-based backups with retention
│   ├── User-Mgmt.ps1                  # create/disable/enable/remove local users
│   ├── Disk-Usage-Report.ps1          # drive + folder usage, threshold alerting
│   ├── Log-Cleanup.ps1                # archive/prune old event log entries & log files
│   ├── Service-Health-Check.ps1       # check & optionally restart services
│   ├── Windows-Update.ps1             # scan/install updates via PSWindowsUpdate
│   ├── Network-Diagnostics.ps1        # adapters, routing, DNS, reachability
│   ├── Security-Audit.ps1             # admin membership, firewall, failed logons, etc.
│   ├── Package-Inventory.ps1          # snapshot installed software, diff baselines
│   └── User-Activity-Report.ps1       # logons, failed logons, lockouts
└── docs/
    ├── server-hardening-checklist.md
    ├── incident-response-runbook.md
    ├── troubleshooting-guide.md
    ├── active-directory-reference.md
    └── powershell-remoting-eventlog-reference.md
```

## Usage

Each script is a self-contained PowerShell script with comment-based help
(`Get-Help .\ScriptName.ps1 -Full`). Review the source before running
anything against a production host — these are starting points, not
turnkey solutions, and you should adapt paths, thresholds, and service
names to your environment. Most scripts that change system state support
`-WhatIf`.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass   # if scripts are blocked
Get-Help .\scripts\Disk-Usage-Report.ps1 -Full
.\scripts\Service-Health-Check.ps1 -List
```

Scripts that touch user accounts, services, or the Security event log
generally need to run from an elevated ("Run as Administrator")
PowerShell session.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Local Administrator rights for account, service, and security-log
  operations
- `PSWindowsUpdate` module for `Windows-Update.ps1` (auto-installed from
  PSGallery on first run if internet-connected)
- RSAT AD PowerShell module for the Active Directory reference commands
  (not required by any script in this repo directly)

## License

MIT — use at your own risk, no warranty. See individual scripts for
details.

