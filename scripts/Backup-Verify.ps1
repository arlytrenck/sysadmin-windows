<#
.SYNOPSIS
    Asserts that backups in a folder exist, are recent, are the expected
    count, and survive an integrity check. Wire it into Task Scheduler
    right after the backup job; a non-zero exit is the alert.

.DESCRIPTION
    A backup job that reports success only proves it ran. It does not
    prove the archive opens, that it landed where the restore procedure
    expects, or that the schedule did not silently stop three weeks ago.
    This checks the four things that go wrong quietly:

      - nothing matching the filter is in the folder at all
      - the newest archive is older than the schedule should allow
      - fewer archives are retained than the retention policy claims
      - an archive is present but truncated or corrupt

    Pairs with Backup-Rotate.ps1, whose default output is
    backup-<hostname>-<timestamp>.zip. Read-only: it never deletes or
    rewrites an archive.

.PARAMETER Path
    Folder holding the backup archives.

.PARAMETER MaxAgeHours
    Fail if the newest matching archive is older than this many hours
    (default: 26, which tolerates a daily job that drifts by an hour).

.PARAMETER Filter
    Wildcard for the files that count as backups (default: *.zip).

.PARAMETER MinCount
    Fail if fewer than this many matching archives are present
    (default: 1). Set it to your retention count to catch a rotation
    that has been deleting more than it keeps.

.PARAMETER Deep
    Read every entry in every archive rather than only the newest, and
    read entry contents so the CRC is actually validated. Slower, and
    worth scheduling weekly rather than nightly.

.EXAMPLE
    .\Backup-Verify.ps1 -Path E:\Backups

.EXAMPLE
    .\Backup-Verify.ps1 -Path E:\Backups -MaxAgeHours 50 -MinCount 7 -Deep

.NOTES
    Exit codes: 0 = all checks passed, 1 = at least one check failed,
    2 = the path does not exist or could not be read.

    Integrity handling by extension: .zip opens the central directory and
    (with -Deep) reads each entry; .gz decompresses to a null sink; a
    sibling SHA256SUMS.txt is verified against the files it names;
    anything else is checked for non-zero length only.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Path,

    [int]$MaxAgeHours = 26,

    [string]$Filter = '*.zip',

    [int]$MinCount = 1,

    [switch]$Deep
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Warning "Not a folder: $Path"
    exit 2
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
} catch {
    Write-Warning "Could not load System.IO.Compression.FileSystem: $($_.Exception.Message)"
}

$failed = 0

function Test-ZipArchive {
    param(
        [string]$File,
        [bool]$ReadEntries
    )

    $zip = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($File)
        $entryCount = $zip.Entries.Count

        if ($ReadEntries) {
            $buffer = New-Object byte[] 65536
            foreach ($entry in $zip.Entries) {
                # A directory entry has no content and a zero-length name tail.
                if ($entry.Length -eq 0 -and $entry.Name -eq '') { continue }
                $stream = $entry.Open()
                try {
                    # Reading to the end forces the deflate CRC check. A
                    # truncated archive throws here rather than at open time.
                    while ($stream.Read($buffer, 0, $buffer.Length) -gt 0) { }
                } finally {
                    $stream.Dispose()
                }
            }
        }
        return [pscustomobject]@{ Ok = $true; Detail = "$entryCount entries" }
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message }
    } finally {
        if ($zip) { $zip.Dispose() }
    }
}

function Test-GzipArchive {
    param([string]$File)

    $in = $null
    $gz = $null
    try {
        $in = [System.IO.File]::OpenRead($File)
        $gz = New-Object System.IO.Compression.GZipStream($in, [System.IO.Compression.CompressionMode]::Decompress)
        $buffer = New-Object byte[] 65536
        $total = 0
        while (($read = $gz.Read($buffer, 0, $buffer.Length)) -gt 0) { $total += $read }
        return [pscustomobject]@{ Ok = $true; Detail = "$total bytes decompressed" }
    } catch {
        return [pscustomobject]@{ Ok = $false; Detail = $_.Exception.Message }
    } finally {
        if ($gz) { $gz.Dispose() }
        if ($in) { $in.Dispose() }
    }
}

$files = @(Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending)

Write-Host "=== Inventory ==="
Write-Host "Folder:  $Path"
Write-Host "Filter:  $Filter"
Write-Host "Matched: $($files.Count) file(s)"

if ($files.Count -eq 0) {
    Write-Host "FLAG: nothing matching '$Filter' in $Path"
    Write-Host ""
    Write-Host "RESULT: backup verification failed."
    exit 1
}

if ($files.Count -lt $MinCount) {
    Write-Host "FLAG: only $($files.Count) archive(s) retained, expected at least $MinCount"
    $failed++
}

$newest = $files[0]
$ageHours = [math]::Round(((Get-Date) - $newest.LastWriteTime).TotalHours, 1)
# Round to MB only once there is a whole MB to show, so a small-but-valid
# archive does not report itself as "0 MB" and read as empty.
$sizeText = if ($newest.Length -ge 1MB) {
    "$([math]::Round($newest.Length / 1MB, 1)) MB"
} elseif ($newest.Length -ge 1KB) {
    "$([math]::Round($newest.Length / 1KB, 1)) KB"
} else {
    "$($newest.Length) bytes"
}

Write-Host ""
Write-Host "=== Newest archive ==="
Write-Host "Name:    $($newest.Name)"
Write-Host "Written: $($newest.LastWriteTime) ($ageHours h ago)"
Write-Host "Size:    $sizeText"

if ($ageHours -gt $MaxAgeHours) {
    Write-Host "FLAG: newest backup is $ageHours h old, past the $MaxAgeHours h limit"
    $failed++
}
if ($newest.Length -eq 0) {
    Write-Host "FLAG: newest backup is zero bytes"
    $failed++
}

Write-Host ""
Write-Host "=== Integrity ==="

$toCheck = if ($Deep) { $files } else { @($newest) }
foreach ($file in $toCheck) {
    $result = switch -Wildcard ($file.Name) {
        '*.zip' { Test-ZipArchive -File $file.FullName -ReadEntries $Deep.IsPresent; break }
        '*.gz'  { Test-GzipArchive -File $file.FullName; break }
        '*.tgz' { Test-GzipArchive -File $file.FullName; break }
        default {
            if ($file.Length -gt 0) {
                [pscustomobject]@{ Ok = $true; Detail = 'non-empty (no format-specific check)' }
            } else {
                [pscustomobject]@{ Ok = $false; Detail = 'zero bytes' }
            }
        }
    }

    if ($result.Ok) {
        Write-Host "  OK   $($file.Name) - $($result.Detail)"
    } else {
        Write-Host "FLAG: $($file.Name) failed its integrity check - $($result.Detail)"
        $failed++
    }
}

$sumsFile = Join-Path $Path 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $sumsFile) {
    Write-Host ""
    Write-Host "=== SHA256SUMS.txt ==="
    foreach ($line in (Get-Content -LiteralPath $sumsFile)) {
        if ($line -notmatch '^\s*([0-9a-fA-F]{64})\s+\*?(.+?)\s*$') { continue }
        $expected = $Matches[1]
        $name = $Matches[2]
        $target = Join-Path $Path $name
        if (-not (Test-Path -LiteralPath $target)) {
            Write-Host "FLAG: $name is listed in SHA256SUMS.txt but missing"
            $failed++
            continue
        }
        $actual = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
        if ($actual -ieq $expected) {
            Write-Host "  OK   $name"
        } else {
            Write-Host "FLAG: $name does not match its recorded SHA256"
            $failed++
        }
    }
}

Write-Host ""
if ($failed -gt 0) {
    Write-Host "RESULT: $failed check(s) failed."
    exit 1
}
Write-Host "RESULT: backups present, current, and readable."
exit 0
