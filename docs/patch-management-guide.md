# Patch Management Guide

A practical patching strategy for a small Windows Server fleet — enough
process to avoid both "we never patch" and "an untested patch took down
production on a Tuesday." Pairs with
[Windows-Update.ps1](../scripts/Windows-Update.ps1) (applying updates)
and [Pending-Reboot-Check.ps1](../scripts/Pending-Reboot-Check.ps1)
(confirming a patch cycle actually finished).

## Patch rings

Rolling every update out to every server the same day is how one bad
patch takes down the whole fleet at once. A simple three-ring model:

1. **Canary** (1 host, or a non-production VM matching prod as closely
   as possible): gets updates first, day 0.
2. **Broad** (most of the fleet): gets updates a few days after canary,
   once nothing broke.
3. **Last-touch** (anything that's expensive or slow to recover if a
   patch goes wrong — a domain controller, a database server holding
   the only copy of something): gets updates last, once broad rollout
   has run clean for a defined soak period.

The soak period between rings doesn't need to be long — even 48-72 hours
catches most "this patch breaks X" reports, which tend to surface fast
once a patch is out in the wild.

## Before rolling out

- **Read the release notes / known-issues list** for the update, not
  just the CVE summary — Microsoft (and third-party software vendors
  whose products are affected) publish known-issue call-outs for
  problematic updates fairly quickly.
- **Confirm a recent, verified backup exists** for anything in the
  "last-touch" ring before patching it — see
  [backup-dr-testing-runbook.md](backup-dr-testing-runbook.md).
- **Check for maintenance-mode/monitoring-silence needs** — a patch
  reboot will otherwise fire every alert tied to that host's
  availability.

## Applying updates

```powershell
# Scan and report only, don't install
.\scripts\Windows-Update.ps1 -ListOnly

# Install with auto-reboot suppressed, so you control the reboot window
.\scripts\Windows-Update.ps1 -AutoReboot:$false

# Confirm afterward whether a reboot is actually needed
.\scripts\Pending-Reboot-Check.ps1
```

Separating "install" from "reboot" matters for the last-touch ring
especially — you want the reboot to happen in a planned maintenance
window, not whenever the update happens to finish downloading.

## After rolling out

- **Verify the reboot actually completed and the host came back
  healthy** — check the relevant services with
  [Service-Health-Check.ps1](../scripts/Service-Health-Check.ps1) rather
  than assuming "it's pingable" means "it's fully working."
- **Watch error rates for a few hours post-patch**, not just at the
  moment of reboot —
  [Event-Log-Anomaly-Scan.ps1](../scripts/Event-Log-Anomaly-Scan.ps1)
  can catch a regression that only shows up once real traffic returns.
- **Record what was installed and when**, even informally — when a
  problem shows up days later, "what changed" is the first question,
  and a patch log answers it immediately instead of requiring
  reconstruction from Windows Update history on every host.

## Handling a bad patch

- **Know the rollback path before you need it**: `wusa
  /uninstall /kb:XXXXXXX` for a specific update, or restore from the
  pre-patch backup/snapshot if the update can't be cleanly removed.
- **Pause the ring** — stop broad/last-touch rollout the moment canary
  or early-broad hosts show a problem, rather than continuing on
  schedule and hoping it was a one-off.
- **File it, don't just work around it** — a known-bad update should be
  explicitly blocked (WSUS approval removed, or the equivalent in
  whatever update-management tooling you use) so it isn't accidentally
  reapplied later.
