# Change Management Checklist

A pre/post-change checklist for changes to a production Windows Server
host — config edits, software installs, service changes, anything that
isn't pure read-only investigation. Scaled for a homelab or small
fleet: not a formal change-advisory-board process, just the minimum
discipline that keeps a bad change from becoming an incident. Pairs
with [patch-management-guide.md](patch-management-guide.md) for the
update-specific version of this, and with
[incident-postmortem-template.md](incident-postmortem-template.md) for
when a change goes wrong anyway.

## Before the change

- [ ] **Written down what's changing and why**, even briefly — a ticket
  or a line in a shared doc. Future-you (or whoever investigates a
  later incident) needs to be able to find this.
- [ ] **Confirmed a recent, verified backup exists** for anything the
  change touches — see
  [database-backup-restore-guide.md](database-backup-restore-guide.md)
  for SQL Server, or the relevant config/data path otherwise.
  "Verified" means tested restorable, not just "a backup job ran."
- [ ] **Identified the rollback path** before starting, not after
  something goes wrong. A System Restore point or VM snapshot taken
  immediately before the change is cheap insurance for anything
  higher-risk than a single config value.
- [ ] **Checked for a maintenance window / notified anyone who needs to
  know**, if the change could cause visible disruption — including
  silencing alerts tied to the expected disruption so real problems
  aren't lost in the noise.
- [ ] **Considered blast radius.** Can this be tested on one host before
  the rest of the fleet? A canary host, even an informal one, catches
  most "this breaks on real config" problems cheaply.

## During the change

- [ ] **One change at a time.** Bundling multiple unrelated changes
  makes rollback and root-causing much harder if something breaks —
  you won't know which part did it.
- [ ] **Capture the exact commands run**, not just the intent —
  PowerShell history is not a durable record; a transcript
  (`Start-Transcript`) or script is.

## After the change

- [ ] **Verified the change had the intended effect**, not just "the
  command didn't error." Check the actual state (a service is running,
  a setting took effect) —
  [Service-Health-Check.ps1](../scripts/Service-Health-Check.ps1) and
  [Security-Audit.ps1](../scripts/Security-Audit.ps1) are useful
  generic checks depending on what changed.
- [ ] **Watched for regressions for a reasonable window afterward**, not
  just at the moment of the change —
  [Event-Log-Anomaly-Scan.ps1](../scripts/Event-Log-Anomaly-Scan.ps1)
  can catch a problem that only shows up once real traffic returns.
- [ ] **Checked whether a reboot is now pending** —
  [Pending-Reboot-Check.ps1](../scripts/Pending-Reboot-Check.ps1) — and
  scheduled it deliberately rather than leaving the host in a
  half-applied state indefinitely.
- [ ] **Re-enabled anything silenced** for the maintenance window.
- [ ] **Updated any documentation the change invalidated** — a runbook,
  an inventory, a diagram. Stale docs are worse than no docs, because
  they're trusted.

## When a change goes wrong

Roll back using the path identified before starting, rather than trying
to forward-fix under pressure — a forward fix invented while something
is actively broken is itself an unreviewed, untested change. If the
incident was more than trivial, write it up using
[incident-postmortem-template.md](incident-postmortem-template.md).
