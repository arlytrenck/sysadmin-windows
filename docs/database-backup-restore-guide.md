# Database Backup & Restore Guide (SQL Server)

A focused guide for SQL Server, the most common database engine on
Windows Server. Pairs with
[backup-dr-testing-runbook.md](backup-dr-testing-runbook.md), which
covers *testing* that these backups actually restore — do that
periodically, not just once.

## Backup types and when to use them

- **Full backup**: a complete point-in-time copy. The baseline every
  other backup type builds on.
- **Differential backup**: everything changed since the last full —
  smaller and faster than another full, but restore requires the last
  full plus the latest differential.
- **Transaction log backup**: enables point-in-time recovery between
  fulls/differentials. Required if your RPO is tighter than "since last
  night's full backup." Only available in Full or Bulk-Logged recovery
  model — Simple recovery model truncates the log and can't do this.

## Taking a backup

```sql
-- Full backup
BACKUP DATABASE MyDb
TO DISK = 'E:\Backups\MyDb-Full.bak'
WITH INIT, COMPRESSION, CHECKSUM;

-- Differential (requires a prior full)
BACKUP DATABASE MyDb
TO DISK = 'E:\Backups\MyDb-Diff.bak'
WITH DIFFERENTIAL, COMPRESSION, CHECKSUM;

-- Transaction log (requires Full or Bulk-Logged recovery model)
BACKUP LOG MyDb
TO DISK = 'E:\Backups\MyDb-Log.trn'
WITH COMPRESSION, CHECKSUM;
```

`CHECKSUM` catches page corruption at backup time rather than discovering
it during a restore — worth the small overhead. `COMPRESSION` shrinks the
file and usually backs up faster too (CPU-bound, not I/O-bound).

## Restoring

```sql
-- Full restore
RESTORE DATABASE MyDb
FROM DISK = 'E:\Backups\MyDb-Full.bak'
WITH NORECOVERY;   -- NORECOVERY: more backups (diff/log) still to apply

-- Then a differential, if you have one
RESTORE DATABASE MyDb
FROM DISK = 'E:\Backups\MyDb-Diff.bak'
WITH NORECOVERY;

-- Then any transaction log backups, in order
RESTORE LOG MyDb
FROM DISK = 'E:\Backups\MyDb-Log.trn'
WITH RECOVERY;     -- RECOVERY on the last one: bring the DB online
```

## Verifying a backup without a full restore

```sql
RESTORE VERIFYONLY FROM DISK = 'E:\Backups\MyDb-Full.bak';
```

This confirms the backup file is readable and internally consistent —
useful as a fast daily sanity check — but it does **not** prove the
backup restores into a working, queryable database. Only an actual
restore test does that (see the DR runbook). Treat `VERIFYONLY` as a
smoke test, not a substitute for the real thing.

## Domain controller caveat

A domain controller's AD database (NTDS.dit) has its own backup/restore
rules via System State backup (`wbadmin` or a compatible tool), and
restoring it wrong causes USN rollback or replication conflicts. Never
attempt to restore a DC's System State onto a live domain as a test —
always restore into an isolated lab forest, as covered in the DR runbook.

## General practices

- **Encrypt backups at rest**, especially once they leave the server —
  SQL Server supports native `BACKUP ... WITH ENCRYPTION`, or encrypt at
  the storage layer.
- **Use a dedicated, minimally-privileged backup account**, not `sa`.
- **Store backups off the source host** — a backup that lives only on
  the server it protects is lost in the same failure that takes the
  server.
- **Automate + alert on failure**, not just success — see
  [monitoring-alerting-guide.md](monitoring-alerting-guide.md) for
  wiring a non-zero exit into a notification.
- **Retain more than one generation.** Corruption that's already been
  backed up isn't caught by a single "latest" backup.
