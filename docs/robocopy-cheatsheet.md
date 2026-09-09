# Robocopy Cheatsheet

Bulk file copying and mirroring on Windows. Robocopy is the tool for
anything larger than a drag-and-drop: it retries, it resumes, it
preserves NTFS metadata, and it reports what it did in a form a script
can act on. For Linux's equivalent, see the companion repo's
[rsync-cheatsheet.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/rsync-cheatsheet.md).

Robocopy ships in-box on every supported Windows version. It is a native
executable, not a cmdlet, so PowerShell will not parse its switches for
you and will not throw on failure — see
[Exit codes](#exit-codes-read-this-before-scripting-it) below.

## Why not Copy-Item

`Copy-Item` gives up on the first locked file, does not retry, does not
preserve ACLs or timestamps reliably, and gives you no usable summary of
what moved. For a one-off copy of a folder that is fine. For a file
server migration or a nightly job it is not.

## The switches that matter

```
/E              copy subdirectories, including empty ones (/S skips empty)
/Z              restartable mode - survives a dropped network link mid-file
/J              unbuffered I/O - much faster for large files, do not combine with /Z
/R:n            retries on a failed file (DEFAULT IS 1,000,000 - always set this)
/W:n            seconds between retries (DEFAULT IS 30 - always set this)
/MT[:n]         multithreaded, n = 1-128, default 8. Big win on many small files
/COPY:DAT       copy Data, Attributes, Timestamps (this is the default)
/COPY:DATSOU    ...plus Security (ACLs), Owner, aUditing
/COPYALL        same as /COPY:DATSOU
/DCOPY:DAT      copy directory timestamps too, not just file ones
/B              backup mode - reads files your account cannot normally open
/L              LIST ONLY. Change nothing. Use before every /MIR
/XO /XN /XC     exclude Older / Newer / Changed files
/XF /XD         exclude files / directories by name or wildcard
/NP             no per-file percentage (keeps logs readable)
/NFL /NDL       no file list / no directory list (summary only)
/TEE            write to console and the log file at once
/LOG:file       overwrite a log file   /LOG+:file appends
```

The two defaults worth burning into memory: **`/R` defaults to one
million retries and `/W` to 30 seconds.** A single locked file with the
defaults will park a job for roughly a year. Every robocopy command you
schedule should carry `/R:2 /W:5` or similar.

## The recipes

Copy a tree, preserving everything, with sane retries:

```powershell
robocopy "D:\Data" "E:\Data" /E /COPYALL /DCOPY:DAT /R:2 /W:5 /MT:16 /NP /LOG:C:\Logs\copy.log
```

Mirror — destination becomes an exact match of source, **including
deletions**:

```powershell
# ALWAYS dry-run a mirror first. /MIR will delete files in the destination.
robocopy "D:\Data" "E:\Data" /MIR /L /R:2 /W:5

# Only once the listing is what you expected:
robocopy "D:\Data" "E:\Data" /MIR /COPYALL /DCOPY:DAT /R:2 /W:5 /MT:16 /NP /LOG:C:\Logs\mirror.log
```

`/MIR` is `/E` plus `/PURGE`. Point it at the wrong destination and it
empties that destination. Two habits make this safe: always `/L` first,
and never let the destination be a variable that could expand to empty.
`robocopy D:\Data "$dest" /MIR` with `$dest` unset targets the current
directory.

Nightly incremental of a large share, skipping what has not changed:

```powershell
robocopy "\\fs01\share" "E:\Replica\share" /E /XO /COPYALL /R:2 /W:5 /MT:32 `
    /NP /NFL /NDL /LOG+:C:\Logs\nightly.log
```

Seeding a file server migration, in two passes — a long bulk copy while
users are working, then a short delta at cutover:

```powershell
# Pass 1, days ahead of cutover, users still on the old server
robocopy "\\old\data" "\\new\data" /E /COPYALL /DCOPY:DAT /B /R:2 /W:5 /MT:32 /NP /LOG:C:\Logs\seed.log

# Pass 2, during the maintenance window, with the share taken offline
robocopy "\\old\data" "\\new\data" /MIR /COPYALL /DCOPY:DAT /B /R:2 /W:5 /MT:32 /NP /LOG:C:\Logs\delta.log
```

`/B` (backup mode) needs `SeBackupPrivilege` and `SeRestorePrivilege`,
which an elevated session as a local administrator or Backup Operator
has. It is what lets the copy read files whose ACLs would otherwise deny
your account, and it is why migration copies are run elevated.

Move rather than copy (deletes the source after a verified copy):

```powershell
robocopy "D:\Old" "E:\New" /E /MOVE /COPYALL /R:2 /W:5 /LOG:C:\Logs\move.log
```

Exclude the noise that breaks jobs:

```powershell
robocopy "D:\Data" "E:\Data" /E /R:2 /W:5 `
    /XD "System Volume Information" "$RECYCLE.BIN" ".git" `
    /XF "*.tmp" "Thumbs.db" "desktop.ini" "~$*"
```

## Exit codes: read this before scripting it

Robocopy's exit code is a **bitmask**, and — unlike almost every other
command line tool — a non-zero exit does not mean failure. This is the
single most common way robocopy jobs get wired up wrong.

| Bit | Value | Meaning |
|---|---|---|
| 0 | 1 | Files were copied |
| 1 | 2 | Extra files/dirs found in the destination |
| 2 | 4 | Mismatched files/dirs found |
| 3 | 8 | **Some files or dirs could not be copied** |
| 4 | 16 | **Serious error. Nothing was copied** |

So:

- **0** — nothing to do, source and destination already matched.
- **1** — files copied, clean run. The normal success code.
- **3** — files copied and extras exist. Still success.
- **&lt; 8** — success in every combination.
- **&gt;= 8** — a real failure.

In a scheduled task or a script, test the threshold rather than testing
for zero:

```powershell
robocopy $Source $Destination /MIR /R:2 /W:5 /NP /LOG:$Log
if ($LASTEXITCODE -ge 8) {
    throw "Robocopy failed with exit code $LASTEXITCODE - see $Log"
}
# 0-7 are all success. Treating 1 as an error is the classic mistake, and
# it makes a healthy nightly job page someone every single night.
Write-Host "Robocopy completed with code $LASTEXITCODE (success)."
```

Task Scheduler shows the raw code as the "Last Run Result", so a working
robocopy task reporting `0x1` is fine, not broken. See
[scheduled-tasks-cheatsheet.md](scheduled-tasks-cheatsheet.md).

## Reading the summary

The tail of a robocopy log is the part worth alerting on:

```
               Total    Copied   Skipped  Mismatch    FAILED    Extras
    Dirs :      1204        12      1192         0         0         0
   Files :     38471       308     38163         0         0         4
   Bytes :   41.35 g   1.82 g   39.53 g         0         0    12.4 m
```

`FAILED` above zero is the number to act on. `Skipped` is normal — it is
the files that already matched. `Extras` are files present in the
destination but not the source, which is expected unless you are
mirroring.

```powershell
# Pull the failure count out of a log for monitoring
$tail = Get-Content C:\Logs\nightly.log -Tail 12
$failedLine = $tail | Where-Object { $_ -match '^\s+Files :' }
Write-Host $failedLine
```

## Long paths, and paths with spaces

Robocopy handles paths over 260 characters natively — it is one of the
few in-box tools that always has. Quote every path containing a space,
and **never leave a trailing backslash inside quotes**: `"D:\Data\"`
escapes the closing quote and robocopy parses the rest of the line as
part of the path.

```powershell
robocopy "D:\Data"  "E:\Data"   /E     # right
robocopy "D:\Data\" "E:\Data\"  /E     # broken - trailing backslash in quotes
```

## Verifying afterward

Robocopy does not hash-verify by default; it compares size, timestamp,
and attributes. For a migration where that is not enough, re-run in
list-only mode and confirm nothing is left to do:

```powershell
robocopy $Source $Destination /MIR /L /R:0 /W:0 /NJH /NJS /NP
# any output here means the two sides still differ
```

For genuine content verification, hash both sides:

```powershell
$a = Get-ChildItem -Recurse -File $Source | Get-FileHash -Algorithm SHA256
$b = Get-ChildItem -Recurse -File $Destination | Get-FileHash -Algorithm SHA256
Compare-Object $a.Hash $b.Hash
```

That is expensive on a large share. Reserve it for the data where a
silent corruption would actually matter, and confirm the backup of that
data separately with
[Backup-Verify.ps1](../scripts/Backup-Verify.ps1).
