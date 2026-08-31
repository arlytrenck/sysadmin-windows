# Disaster Recovery Plan Template

A template for the plan itself — what to restore, in what order, and to
what target — as opposed to
[backup-dr-testing-runbook.md](backup-dr-testing-runbook.md), which
covers *testing* that a plan like this actually works. Write this
before you need it: the point of a DR plan is that it can be followed
by someone stressed, at 3am, who may not be the person who wrote it.

## Define your targets first

Two numbers drive every decision below:

- **RPO (Recovery Point Objective)** — how much data loss is acceptable,
  expressed as time. "RPO of 1 hour" means backups/replication must run
  at least hourly, because anything since the last backup is lost.
- **RTO (Recovery Time Objective)** — how long the recovery is allowed
  to take, from declaring a disaster to being back in service.

These aren't aspirational — they're a budget. A 15-minute RTO for a
database that takes 45 minutes to restore from backup means either the
RTO is unrealistic or the restore strategy needs to change (faster
storage, an Always On availability group instead of restore-from-backup,
etc). Set them honestly, then build the plan to meet them, not the
other way around.

```
Service          RPO        RTO        Current strategy
--------         ---        ---        ----------------
SQL-primary      15 min     1 hour     log shipping + hourly diff backup
App servers      n/a        30 min     redeploy from image/config mgmt
File storage     24 hours   4 hours    nightly Backup-Rotate.ps1 + offsite copy
Domain services  n/a        2 hours    restore from a second DC (see AD reference)
```

## What counts as "a disaster"

Be explicit about scope, since the response differs:

- **Single host failure** — usually the cheapest case if config and
  data are backed up elsewhere; often just "reprovision and restore."
- **Data corruption or loss** (bad deploy, accidental deletion, a bug
  that silently corrupts data over time) — the hard case, because the
  corrupted state may already be in your most recent backups. Keep
  more than one generation of backups for exactly this reason.
- **Domain controller / AD loss** — has its own restore rules and
  pitfalls (USN rollback, replication conflicts); see the domain
  controller caveat in
  [database-backup-restore-guide.md](database-backup-restore-guide.md)
  and [active-directory-reference.md](active-directory-reference.md).
- **Security incident requiring rebuild from clean state** — different
  from the above because you can't trust the most recent state at all,
  including recent backups if the compromise predates detection.

## Dependency order

Recovering services in the wrong order wastes time re-doing work.
Map dependencies before an incident, not during one:

1. Core infrastructure (DNS, Active Directory/domain services, network)
2. Data stores (SQL Server, file storage) — nothing else works without
   these being correct first
3. Backend/application services
4. Anything user-facing (web frontends, load balancers)
5. Monitoring/alerting itself — restore this early enough to observe
   the rest of the recovery, not last

## Contact tree

Who needs to be involved or notified, and how to reach them when normal
channels (chat, email hosted on the affected infrastructure) might be
down. Keep this list somewhere that survives the disaster it's meant to
help with — not solely on the system you're recovering.

```
Role                Primary            Backup             Reachable via
----                -------            ------             -------------
Incident lead       (name)             (name)             phone: ...
Infra owner         (name)             (name)             phone: ...
Vendor/hosting       —                  —                 support: ...
```

## Recovery steps (per service)

For each service in the dependency order above, document concretely:

- Where the backup/replica lives and how to access it
- The exact restore command(s) — see
  [database-backup-restore-guide.md](database-backup-restore-guide.md)
  for the SQL Server-specific version
- How to verify the restore succeeded before moving to the next
  dependency layer (don't assume — check)
- Who is authorized to declare this step done

## After recovery

- Confirm each service against its RTO/RPO targets — did the actual
  recovery meet them? If not, that's a finding for the next test cycle.
- Run a full validation pass, not just "the service is up" — data
  consistency checks where possible.
- Write up what happened using
  [incident-postmortem-template.md](incident-postmortem-template.md).
- Update this plan with anything that didn't match reality — a DR plan
  that isn't updated after every real use (or test) drifts out of date
  exactly when you can least afford that.
