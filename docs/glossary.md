# Glossary

Terms used across this repo's scripts and docs, defined at the level
they're used here — not exhaustive references for each subsystem.

**Baseline** — a recorded snapshot of expected state (installed
software, a metric's normal range) that later runs compare against to
detect drift. Used by
[Package-Inventory.ps1](../scripts/Package-Inventory.ps1) and the
anomaly-detection approach in
[Event-Log-Anomaly-Scan.ps1](../scripts/Event-Log-Anomaly-Scan.ps1).

**Blast radius** — how much is affected if a change goes wrong. Smaller
is safer; see [change-management-checklist.md](change-management-checklist.md).

**Commit charge / commit limit** — the total memory Windows has
promised to processes (RAM plus page file), versus the maximum it can
promise. Commit charge approaching the limit is a stronger signal of
memory pressure than "available MBytes" alone.

**CVE** — Common Vulnerabilities and Exposures: a public identifier for
a specific known security vulnerability, relevant when reading a
patch's known-issues list (see
[patch-management-guide.md](patch-management-guide.md)).

**GPO (Group Policy Object)** — a set of configuration settings applied
to computers or users in Active Directory. `gpresult /h report.html`
shows what's actually applied to a given host, which can differ from
what's expected if policy processing failed.

**Idempotent** — an operation that produces the same end state no
matter how many times it's run. Worth aiming for in scripts that change
system state, since a script that's safe to re-run is much easier to
recover with after a partial failure.

**NTDS.dit** — the Active Directory database file on a domain
controller. Has its own backup/restore rules (System State backup);
restoring it incorrectly can cause USN rollback or replication
conflicts — see the domain controller caveat in
[database-backup-restore-guide.md](database-backup-restore-guide.md).

**Postmortem (blameless)** — a writeup after an incident focused on
system and process gaps rather than individual fault. See
[incident-postmortem-template.md](incident-postmortem-template.md).

**RPO / RTO** — Recovery Point Objective (how much data loss is
tolerable, as a time span) and Recovery Time Objective (how long
recovery is allowed to take). Defined in
[disaster-recovery-plan-template.md](disaster-recovery-plan-template.md).

**Runbook** — a procedure written down in enough detail that someone
other than its author can follow it under pressure, as opposed to a
reference doc meant for browsing.

**Signature age** — how long since an antivirus product's detection
signatures were last updated. Checked by
[Defender-Status-Check.ps1](../scripts/Defender-Status-Check.ps1); a
consistently stale signature age usually points to a connectivity or
update-source problem rather than a Defender problem specifically.

**Threshold alerting vs. trend alerting** — alerting on a fixed value
("a drive is 90% full") vs. on the rate of change ("disk usage is
growing 2x faster than last month"). Trend alerting often gives more
lead time; see [capacity-planning-guide.md](capacity-planning-guide.md).

**Working set** — the amount of physical RAM a process is currently
using, as opposed to its total committed memory (which can include
paged-out data). What
[Process-Watchdog.ps1](../scripts/Process-Watchdog.ps1) checks against
its memory threshold.
