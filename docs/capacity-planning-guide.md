# Capacity Planning Guide

Most outages caused by "running out" (disk, memory, connections, IOPS)
are predictable weeks in advance if anyone is tracking the trend line.
This guide is about turning the one-shot reports this repo's scripts
produce into a trend you can act on before the threshold alert fires.

## What to track, and where the data already comes from

| Resource | Script already in this repo | What to record over time |
| --- | --- | --- |
| Disk usage | `Disk-Usage-Report.ps1` | % used per volume, weekly |
| Installed software drift | `Package-Inventory.ps1` | package count + diff vs. last snapshot |
| Certificate expiry | `Cert-Expiry-Check.ps1` | days-to-expiry per cert, so renewals aren't a surprise |
| Failed logons / lockouts | `User-Activity-Report.ps1` | trend, not just a point-in-time count |
| Disk health/wear | `Disk-Health-Check.ps1` | reliability counter trend, not just current status |

You don't need a metrics platform to start — a scheduled task appending
one line per run to a CSV is enough to see a trend:

```powershell
# Append today's C: usage to a simple trend file
$vol = Get-Volume -DriveLetter C
$pctUsed = [math]::Round((($vol.Size - $vol.SizeRemaining) / $vol.Size) * 100, 1)
"$(Get-Date -Format 'yyyy-MM-dd'),$pctUsed" | Add-Content -Path C:\Logs\disk-trend.csv
```

Once you outgrow flat files, feed the same numbers into whatever tier of
the [monitoring-alerting-guide.md](monitoring-alerting-guide.md) stack
you've adopted — the point here is the discipline of tracking trend, not
the tooling.

## Reading a trend, not just a threshold

- **Linear growth**: "we add ~2GB/week" lets you calculate a real
  run-out date (`free space / weekly growth rate`), which is a much
  better planning input than "we're at 80%, is that bad?"
- **Step changes**: a sudden jump (a log misconfig, a new application
  rolled out, a new tenant onboarded) is worth investigating even if the
  absolute number is still comfortable — it changes the growth rate
  going forward, not just today's number.
- **Seasonal/cyclical patterns**: month-end batch jobs, backup windows,
  or business seasonality can make a snapshot look alarming when it's
  actually routine — this is why trend beats point-in-time for alerting
  thresholds too (see the "alert on trend, not just threshold" note in
  the monitoring guide).

## A simple capacity review cadence

- **Monthly**: skim the trend lines for anything accelerating. Five
  minutes per host is usually enough once the data collection is
  automated.
- **Quarterly**: project each tracked resource forward and flag anything
  projected to breach a safe threshold within the next two quarters —
  that's your lead time to budget, order hardware, or renegotiate a
  cloud/licensing tier.
- **Before any known future load change**: an expected growth in
  users/traffic/data retention should trigger a capacity check ahead of
  the change, not a reactive one after it lands.

## Common false economies

- Deferring a disk expansion until it's an emergency almost always costs
  more (downtime, rushed procurement, weekend work) than doing it a
  month early would have.
- Deleting old data to free space without checking retention
  requirements first can create a compliance or DR gap that's more
  expensive than the disk itself.
- Ignoring "it'll be fine, we're only at 60%" without a growth rate
  attached — 60% today with fast growth can be a bigger emergency than
  85% today with growth already flattened out.
