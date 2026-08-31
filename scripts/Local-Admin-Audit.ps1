<#
.SYNOPSIS
    Enumerates members of the local Administrators group and flags
    accounts that aren't on an expected allow-list, plus any disabled or
    expired accounts that are still sitting in the group.

.PARAMETER AllowList
    Names (SamAccountName, DOMAIN\user, or .\localuser form) expected to
    be local admins. Anything in the group but not in this list is
    flagged. Omit to just list membership without flagging.

.EXAMPLE
    .\Local-Admin-Audit.ps1 -AllowList 'Administrator','CONTOSO\svc-backup','CONTOSO\jsmith'
#>

[CmdletBinding()]
param(
    [string[]]$AllowList = @()
)

$ErrorActionPreference = 'Stop'

$members = Get-LocalGroupMember -Group 'Administrators'

Write-Host "=== Local Administrators group membership ($($members.Count)) ==="
$members | Select-Object Name, ObjectClass, PrincipalSource | Format-Table -AutoSize | Out-String | Write-Host

if ($AllowList.Count -gt 0) {
    Write-Host "=== Members not on the allow-list ==="
    $unexpected = $members | Where-Object {
        $short = $_.Name -replace '^.*\\', ''
        -not ($AllowList -contains $_.Name -or $AllowList -contains $short)
    }
    if ($unexpected) {
        $unexpected | Select-Object Name, ObjectClass | Format-Table -AutoSize | Out-String | Write-Host
    } else {
        Write-Host "None — every member matches the allow-list."
    }
}

Write-Host "=== Disabled or expired accounts still in Administrators ==="
$flaggedAny = $false
foreach ($member in $members) {
    if ($member.ObjectClass -ne 'User' -or $member.PrincipalSource -notin @('Local', 'ActiveDirectory')) {
        continue
    }
    $short = $member.Name -replace '^.*\\', ''
    try {
        if ($member.PrincipalSource -eq 'Local') {
            $acct = Get-LocalUser -Name $short -ErrorAction Stop
            if (-not $acct.Enabled) {
                Write-Host "  [DISABLED] $($member.Name) is disabled but still in Administrators"
                $flaggedAny = $true
            }
        } else {
            $acct = Get-ADUser -Identity $short -Properties Enabled, AccountExpirationDate -ErrorAction Stop
            if (-not $acct.Enabled) {
                Write-Host "  [DISABLED] $($member.Name) is disabled but still in Administrators"
                $flaggedAny = $true
            }
            if ($acct.AccountExpirationDate -and $acct.AccountExpirationDate -lt (Get-Date)) {
                Write-Host "  [EXPIRED]  $($member.Name) expired $($acct.AccountExpirationDate) but still in Administrators"
                $flaggedAny = $true
            }
        }
    } catch {
        Write-Host "  [UNKNOWN]  Could not resolve $($member.Name): $_"
    }
}
if (-not $flaggedAny) {
    Write-Host "None found."
}
