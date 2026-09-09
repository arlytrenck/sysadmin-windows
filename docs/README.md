# Documentation Index

Everything in this directory is written to be used while something is
happening, not read cover to cover. Grouped below by the question that
sends you looking for it. The [repository README](../README.md) has the
same files listed as a plain tree if you already know the name.

Nothing here is environment-specific: paths, thresholds, and service
names are examples, and you should expect to adapt them.

## Setting up a server

- [windows-server-bootstrap-checklist.md](windows-server-bootstrap-checklist.md)
  — day-0 procedure for a fresh Windows Server, in order.
- [server-hardening-checklist.md](server-hardening-checklist.md) — what
  to change before it carries traffic.
- [group-policy-reference.md](group-policy-reference.md) — GPO
  structure, RSoP, editing from PowerShell, baseline settings.
- [windows-in-the-homelab.md](windows-in-the-homelab.md) — where a
  Windows box earns its place next to a Linux fleet.

## Day-to-day command references

- [powershell-cheatsheet.md](powershell-cheatsheet.md) — the pipeline,
  objects, filtering, formatting, remoting basics.
- [powershell-remoting-eventlog-reference.md](powershell-remoting-eventlog-reference.md)
  — WinRM, sessions, and querying the event log properly.
- [scheduled-tasks-cheatsheet.md](scheduled-tasks-cheatsheet.md) —
  creating tasks, run-as accounts, the Last Run Result codes, and why a
  task "runs" but does nothing.
- [robocopy-cheatsheet.md](robocopy-cheatsheet.md) — bulk copy and
  mirror, the retry defaults that will bite you, and the exit-code
  bitmask.
- [glossary.md](glossary.md) — terms used across these documents.

## Active Directory and identity

- [active-directory-reference.md](active-directory-reference.md) —
  objects, OUs, replication, the commands worth knowing.
- [dns-dhcp-reference.md](dns-dhcp-reference.md) — Windows DNS and DHCP
  roles: zones, scavenging, scopes, failover.
- [recovery-access-and-directory-services-runbook.md](recovery-access-and-directory-services-runbook.md)
  — DSRM, break-glass accounts, AD recovery.

## Networking, storage, and virtualisation

- [windows-networking-cheatsheet.md](windows-networking-cheatsheet.md)
- [windows-firewall-cheatsheet.md](windows-firewall-cheatsheet.md) —
  Defender Firewall from PowerShell: scoped rules, profiles, logging.
- [windows-storage-cheatsheet.md](windows-storage-cheatsheet.md) —
  disks, volumes, Storage Spaces, NTFS permissions, shares.
- [hyper-v-cheatsheet.md](hyper-v-cheatsheet.md) — VMs, checkpoints,
  vSwitches, VHDX, replica, export and import.

## Security

- [certificate-management-reference.md](certificate-management-reference.md)
  — the stores, requesting and renewing, private key permissions, and
  binding to services.
- [endpoint-protection-guide.md](endpoint-protection-guide.md) —
  Defender configuration, exclusions, and what to alert on.
- [secret-rotation-runbook.md](secret-rotation-runbook.md) — rotating a
  service account or key with a rollback path, and the gMSA/LAPS
  alternatives that remove the job entirely.

## Backup, monitoring, and capacity

- [backup-dr-testing-runbook.md](backup-dr-testing-runbook.md) —
  exercising backups on a schedule, because an untested backup is a
  hypothesis.
- [database-backup-restore-guide.md](database-backup-restore-guide.md)
- [monitoring-alerting-guide.md](monitoring-alerting-guide.md) — what
  to alert on, and what to leave as a dashboard.
- [capacity-planning-guide.md](capacity-planning-guide.md) — noticing
  you are going to run out before you do.

## When something is broken

Start here:

- [troubleshooting-flowchart.md](troubleshooting-flowchart.md) — triage
  order when you do not yet know what kind of problem it is.
- [troubleshooting-guide.md](troubleshooting-guide.md) — reference for
  specific symptoms once you do.

Then:

- [incident-response-runbook.md](incident-response-runbook.md)

## Process and templates

- [patch-management-guide.md](patch-management-guide.md) — patch rings,
  soak periods, and handling a bad update.
- [change-management-checklist.md](change-management-checklist.md)
- [incident-postmortem-template.md](incident-postmortem-template.md)
- [disaster-recovery-plan-template.md](disaster-recovery-plan-template.md)
- [resource-library.md](resource-library.md) — upstream documentation
  for every tool referenced here.
