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
│   ├── User-Activity-Report.ps1       # logons, failed logons, lockouts
│   ├── Cert-Expiry-Check.ps1          # TLS cert expiry, live host or local file
│   ├── Scheduled-Task-Audit.ps1       # flag SYSTEM/hidden/user-writable-path tasks
│   ├── Firewall-Rules-Dump.ps1        # snapshot Windows Firewall rules
│   ├── Local-Admin-Audit.ps1          # flag unexpected/disabled local admins
│   ├── Disk-Health-Check.ps1          # physical disk health & reliability counters
│   ├── Process-Watchdog.ps1           # flag high CPU/mem or unresponsive processes
│   ├── Pending-Reboot-Check.ps1       # detect whether a reboot is waiting to apply
│   ├── Event-Log-Anomaly-Scan.ps1     # flag error-rate spikes vs. a trailing baseline
│   └── Defender-Status-Check.ps1      # real-time protection, signature age, last scan
└── docs/
    ├── server-hardening-checklist.md
    ├── incident-response-runbook.md
    ├── troubleshooting-guide.md
    ├── active-directory-reference.md
    ├── powershell-remoting-eventlog-reference.md
    ├── backup-dr-testing-runbook.md
    ├── monitoring-alerting-guide.md
    ├── database-backup-restore-guide.md
    ├── capacity-planning-guide.md
    ├── patch-management-guide.md
    └── endpoint-protection-guide.md
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
  and for `Local-Admin-Audit.ps1`'s domain-account checks (not required
  for local-only accounts)
- Storage module (built in on Windows Server 2012+/Windows 8+) for
  `Disk-Health-Check.ps1`
- Defender PowerShell module (built in on Windows 10/11 and Server
  2016+) for `Defender-Status-Check.ps1`

## Contributing

Bug reports, script/doc suggestions, and pull requests are welcome — see
[CONTRIBUTING.md](CONTRIBUTING.md) for the process and style guidelines.
Pushes and PRs touching `scripts/**.ps1` run through
[PSScriptAnalyzer](.github/workflows/psscriptanalyzer.yml) in CI.

## License

MIT — see [LICENSE](LICENSE). Use at your own risk, no warranty.
