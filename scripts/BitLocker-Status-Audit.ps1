<#
.SYNOPSIS
    Audits BitLocker protection status on every volume, flagging anything
    unencrypted, suspended, or missing a recoverable key protector.

.DESCRIPTION
    Read-only; makes no changes. Intended for a periodic compliance check
    on laptops/workstations, or on servers with encrypted data volumes.

.PARAMETER RequireVolumes
    Drive letters (e.g. "C:","D:") that must be fully protected. If any
    listed volume is missing, unencrypted, or suspended, the script
    exits non-zero. Default: just C:.

.EXAMPLE
    .\BitLocker-Status-Audit.ps1 -RequireVolumes 'C:','D:'

.NOTES
    Requires the BitLocker PowerShell module (present on BitLocker-capable
    Windows 10/11 and Server editions with the feature installed). Exit
    codes: 0 = all required volumes fully protected, 1 = one or more
    flagged, 2 = module/cmdlet unavailable.
#>

[CmdletBinding()]
param(
    [string[]]$RequireVolumes = @('C:')
)

if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
    Write-Warning "Get-BitLockerVolume is not available — BitLocker feature/module not present on this host."
    exit 2
}

try {
    $volumes = Get-BitLockerVolume -ErrorAction Stop
} catch {
    Write-Warning "Could not query BitLocker status: $_"
    exit 2
}

Write-Host "=== BitLocker status by volume ==="
$volumes | Select-Object MountPoint, VolumeType, ProtectionStatus, VolumeStatus,
    EncryptionPercentage,
    @{N='KeyProtectors'; E={ ($_.KeyProtector | Select-Object -ExpandProperty KeyProtectorType) -join ',' }} |
    Format-Table -AutoSize | Out-String | Write-Host

$flagged = $false

foreach ($drive in $RequireVolumes) {
    $vol = $volumes | Where-Object { $_.MountPoint -eq $drive }
    if (-not $vol) {
        Write-Host "FLAG: required volume $drive not found"
        $flagged = $true
        continue
    }
    if ($vol.ProtectionStatus -ne 'On') {
        Write-Host "FLAG: $drive protection status is '$($vol.ProtectionStatus)' (expected 'On')"
        $flagged = $true
    }
    if ($vol.VolumeStatus -ne 'FullyEncrypted') {
        Write-Host "FLAG: $drive volume status is '$($vol.VolumeStatus)' (expected 'FullyEncrypted')"
        $flagged = $true
    }
    if (-not $vol.KeyProtector -or $vol.KeyProtector.Count -eq 0) {
        Write-Host "FLAG: $drive has no key protector configured — no recovery path if the TPM/PIN path fails"
        $flagged = $true
    }
}

Write-Host ""
if ($flagged) {
    Write-Host "RESULT: one or more required volumes are not fully protected."
    exit 1
}
Write-Host "RESULT: all required volumes ($($RequireVolumes -join ', ')) are fully protected."
exit 0
