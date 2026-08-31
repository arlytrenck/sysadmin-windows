# Troubleshooting Flowchart

A quick triage flow for "something's wrong with this host" — where to
look first, in what order, before diving deep. Complements
[troubleshooting-guide.md](troubleshooting-guide.md), which is a
reference for specific symptoms; this document is about *where to
start* when you don't yet know which category the problem is in.

## Start here: what's the symptom?

```
Host/service unresponsive or slow
  │
  ├─ Can you reach it at all (RDP/WinRM/ping)?
  │    │
  │    ├─ No  → suspect network/firewall/host-down. Go to NETWORK.
  │    │
  │    └─ Yes → continue below
  │
  ├─ Is CPU usage sustained and high?
  │    └─ Yes → go to CPU
  │
  ├─ Is available memory low / is the system paging heavily?
  │    └─ Yes → go to MEMORY
  │
  ├─ Is any drive near full?
  │    └─ Yes → go to DISK
  │
  └─ None of the above obviously true?
       → check recent changes first (see "Recent changes" below),
         then go to EVENT LOGS for anything that started around when
         the symptom did
```

## CPU

1. Task Manager / `Get-Process | Sort-Object CPU -Descending` — one
   runaway process, or broad load across many? A single process usually
   means a bug or a stuck request; broad load usually means real
   traffic or a scheduling problem.
2. [Process-Watchdog.ps1](../scripts/Process-Watchdog.ps1) flags
   processes over a CPU-time threshold and not-responding processes in
   one pass.
3. Check for a recent deploy, scheduled task, or Windows Update that
   might explain a new CPU-heavy process — see
   [Scheduled-Task-Audit.ps1](../scripts/Scheduled-Task-Audit.ps1) and
   "Recent changes" below.

## Memory

1. Task Manager Performance tab, or `Get-Counter
   '\Memory\Available MBytes'` — how much is actually available, and is
   the commit charge near the commit limit?
2. [Process-Watchdog.ps1](../scripts/Process-Watchdog.ps1) flags
   processes over a working-set memory threshold.
3. Check Event Viewer (System log) for resource-exhaustion events —
   Windows logs when it's under significant memory pressure.
4. Heavy paging (high disk activity correlated with low available
   memory) is often the actual cause of "everything is slow" even when
   no single process looks obviously wrong.

## Disk

1. [Disk-Usage-Report.ps1](../scripts/Disk-Usage-Report.ps1) for a
   fast top-consumers view per volume.
2. [Disk-Health-Check.ps1](../scripts/Disk-Health-Check.ps1) if the
   symptom is slowness rather than fullness — a failing physical disk
   degrades performance well before it fails outright.
3. A volume showing full but nothing obviously large — check the
   Recycle Bin, Volume Shadow Copy storage usage
   (`vssadmin list shadowstorage`), and Windows Update's component
   store (`Dism /Online /Cleanup-Image /AnalyzeComponentStore`).
4. [Log-Cleanup.ps1](../scripts/Log-Cleanup.ps1) if event logs or
   application logs are the culprit.

## Network

1. Can you reach the host at all (ping, or from another host on the
   same network if ICMP is filtered)?
2. [Network-Diagnostics.ps1](../scripts/Network-Diagnostics.ps1)
   covers adapters, routing, and DNS in one pass.
3. [Firewall-Rules-Dump.ps1](../scripts/Firewall-Rules-Dump.ps1) if
   something that used to be reachable suddenly isn't — a rule or GPO
   change is a common, easy-to-miss cause.
4. Check the provider/hypervisor status page if this is a VM or cloud
   instance — sometimes it's not your host at all.

## Event logs

1. [Event-Log-Anomaly-Scan.ps1](../scripts/Event-Log-Anomaly-Scan.ps1)
   — is there an actual spike in error-rate, or does it just feel like
   there is?
2. `Get-WinEvent -FilterHashtable @{LogName='System';Level=1,2;
   StartTime=(Get-Date).AddHours(-1)}` (or narrower/wider as needed)
   once you have an approximate time window from the above.
3. Correlate timestamps across the Application log, System log, and
   any application-specific logs — the full story is often split
   across more than one source.

## Recent changes

Ask this early, not last — most incidents trace back to *something
that changed*, and knowing what changed narrows everything above
dramatically:

- What was deployed, patched, or configured recently? Check
  [Pending-Reboot-Check.ps1](../scripts/Pending-Reboot-Check.ps1) if a
  patch was applied but a reboot never happened.
- Did a scheduled task run around when the symptom started? See
  [Scheduled-Task-Audit.ps1](../scripts/Scheduled-Task-Audit.ps1).
- Was there a Group Policy change that could explain it? `gpresult
  /h report.html` shows what's currently applied.
- Was there a traffic or usage change (a launch, a spike, a new
  integration) that's real load rather than a bug?

## When you're stuck

Escalate with what you've *ruled out*, not just the symptom — "CPU and
memory are normal, disks have headroom, no recent deploys, but response
time tripled at 14:30" is far more useful to the next person than
"the server is slow."
