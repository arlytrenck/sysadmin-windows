# Backup & Disaster Recovery Testing Runbook

A backup you haven't tried restoring is a hope, not a backup. This runbook
is a periodic (quarterly is a reasonable default) exercise for verifying
that backups taken with `Backup-Rotate.ps1` — or whatever your actual
backup tooling is (Windows Server Backup, VSS-based snapshots, a
third-party product) — can actually be restored, and how long that takes.

## 1. Define what "recovered" means before you start

Write down, for the system under test:
- What data/state must come back (files, a database, application config,
  the AD database on a DC)?
- What's the acceptable data loss window (RPO — recovery point
  objective)? E.g. "no more than 24 hours of data".
- What's the acceptable downtime (RTO — recovery time objective)? E.g.
  "back in service within 4 hours".

If you don't have these numbers written down anywhere, this exercise is
also how you discover what they realistically are, so you can compare
against what the business actually needs.

## 2. Pick a backup to restore

- Use a real, recent backup — not a specially prepared "known good" one.
  The point is to test what you'd actually reach for during an incident.
- Note its timestamp and where it lives.

## 3. Restore into an isolated environment

Never test-restore over the production system. Use a spare VM or a
snapshot-and-discard cloud instance — anything you can destroy afterward
without consequence. For a domain controller specifically, restore into
an isolated lab forest, never onto a live domain, to avoid USN rollback
and replication conflicts.

```powershell
# Example: restore a Backup-Rotate.ps1 archive into a scratch directory
Expand-Archive -Path 'E:\Backups\backup-hostname-20250101-020000.zip' -DestinationPath 'C:\RestoreTest'
```

Time the restore. Note every manual step required — each one is a step
that can be forgotten or done wrong during a real incident.

## 4. Verify the restored data

- Spot-check file counts, sizes, and a few file contents against what you
  expect.
- For a database (SQL Server, etc.), actually start it against the
  restored data files and run a basic query, don't just confirm the
  backup file isn't empty.
- For an application, actually start it against the restored state and
  exercise its core function.
- For a domain controller restore test, confirm you understand
  authoritative vs. non-authoritative restore for the objects involved —
  they have very different effects on replication.

## 5. Record the results

For each test, log:
- Date, backup timestamp used, who ran it.
- Time to restore (compare against your RTO).
- Data recency of the restored backup (compare against your RPO).
- Any manual steps, surprises, or missing pieces (a config file or
  registry key that wasn't included in the backup, a credential that had
  to be re-entered manually, a dependency that wasn't documented).
- Pass/fail against your defined success criteria from step 1.

## 6. Fix what you found

A restore test that surfaces zero issues on a system that's never been
tested before is itself a signal to look harder — it's uncommon for a
first real test to be clean. Common findings:
- Backup didn't include something needed for a full recovery (application
  config outside the data directory, a scheduled task definition, a
  certificate needed by the app).
- Restore procedure lived only in someone's head — write it down.
- Restore took far longer than the RTO — investigate why (network
  transfer speed, an unindexed database restore, a manual approval
  bottleneck).

Track fixes and re-test on the next cycle to confirm they actually closed
the gap.

## Cadence

- Critical systems (domain controllers, database servers): quarterly, or
  after any significant change to what's backed up or how.
- Everything else: at least annually.
- After any real incident that involved a restore: immediately, while the
  lessons are fresh — don't wait for the next scheduled cycle.
