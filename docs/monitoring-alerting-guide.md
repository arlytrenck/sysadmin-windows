# Monitoring & Alerting Setup Guide

A practical starting point for monitoring a small Windows Server fleet —
from "scheduled task plus a webhook" up through a proper metrics stack.
Pick the tier that matches your scale; there's no need to run a full
monitoring platform for two servers.

## Tier 0: scripts + Task Scheduler + a notification webhook

The scripts in this repo (`Disk-Usage-Report.ps1`, `Service-Health-Check.ps1`,
`Security-Audit.ps1`) already exit non-zero on a problem. Wire that into a
notification with almost no infrastructure:

```powershell
# Scheduled task action (PowerShell), run every 15 minutes
$result = & C:\Scripts\Disk-Usage-Report.ps1 -ThresholdPercentFree 10
if ($LASTEXITCODE -ne 0) {
    $body = @{ text = "Disk threshold breached on $env:COMPUTERNAME" } | ConvertTo-Json
    Invoke-RestMethod -Uri 'https://hooks.example.com/your-webhook' -Method Post -Body $body -ContentType 'application/json'
}
```

Register it with `Register-ScheduledTask` or the Task Scheduler GUI. This
scales to a handful of hosts and gets you real alerting today. Its limits:
no history/trending, no dashboard, and alert fatigue if thresholds aren't
tuned per-host.

## Tier 1: a metrics agent + hosted or self-hosted backend

Once you want trends (is disk usage growing linearly or did something
spike?) and a dashboard, add a metrics agent:

- **Windows Exporter** (Prometheus) + a self-hosted Prometheus + Grafana —
  full control, more to operate yourself.
- **System Center Operations Manager (SCOM)** — the traditional Microsoft-
  stack option if you're already invested in System Center.
- A hosted option (Datadog, Grafana Cloud, Azure Monitor for hybrid/cloud
  VMs, etc.) — less infrastructure to run, ongoing cost scales with
  hosts/metrics.

Minimum useful metric set for a general-purpose server: CPU, memory, disk
usage and I/O, network throughput, and Windows service state.

## Tier 2: alerting rules on top of metrics

Once metrics are flowing, define alert rules rather than eyeballing
dashboards:

- Alert on trend, not just threshold, where possible — "disk will fill in
  under 48 hours at current growth rate" catches problems earlier than a
  flat "under 10% free" rule and fires less often on temporary spikes.
- Alert on absence, not just presence — a host that stops reporting
  metrics at all is itself worth an alert (a metrics agent that died is
  indistinguishable from "everything's fine" if you only alert on bad
  values).
- Route alerts by severity: a paging alert for "service is down now"
  should not use the same channel as "disk is at 75%, plan ahead."

## Log aggregation (complements metrics, doesn't replace them)

Metrics tell you *that* something's wrong; logs tell you *why*. Options
roughly by operational weight:

- Windows Event Forwarding (WEF) to a central collector — built into
  Windows, no extra agent required, good starting point for a small
  fleet.
- A lightweight shipper (Winlogbeat, NXLog) to a log backend (a
  self-hosted ELK stack, or a hosted log service).
- Azure Monitor Agent, if hosts are already Azure-connected or Arc-
  enabled.

## What to actually alert on (a starting list)

- Disk free space below threshold (`Disk-Usage-Report.ps1`)
- A monitored service not running (`Service-Health-Check.ps1`)
- Repeated failed logon attempts or account lockouts beyond a threshold
  (`User-Activity-Report.ps1` can be scripted into a periodic check)
- Certificate expiry approaching (`Cert-Expiry-Check.ps1`)
- Failed scheduled backups (a non-zero exit from `Backup-Rotate.ps1` in
  its scheduled task)
- A new, unrecognized scheduled task appearing (`Scheduled-Task-Audit.ps1`
  run periodically and diffed)
- Host unreachable / not reporting metrics at all

## A note on alert fatigue

More alerts is not more safety once people start ignoring them. Every
alert should be actionable — if an alert fires and the response is always
"yeah, ignore that one," either fix the underlying threshold or remove the
alert. Review your alert rules periodically, not just when adding new
ones.
