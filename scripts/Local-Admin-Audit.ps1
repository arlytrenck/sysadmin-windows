<#
.SYNOPSIS
    Enumerates members of the local Administrators group and flags
    accounts that aren't on an expected allow-list, plus any disabled or
    expired accounts that are still sitting in the group.

.PARAMETER AllowList
    Names (SamAccountName, DOMAIN\user, or .\localuser form) expected to
    be local admins. Anything in the group but not in this list is
    flagged. Omit to just list membership without flagging.

.NOTES
    Exit codes: 0 = nothing flagged; 1 = a member is off the allow-list,
    disabled, expired, or an unresolvable SID (a deleted account that was
    never removed from the group).

.EXAMPLE
    .\Local-Admin-Audit.ps1 -AllowList 'Administrator','CONTOSO\svc-backup','CONTOSO\jsmith'
#>

[CmdletBinding()]
param(
    [string[]]$AllowList = @()
)

$ErrorActionPreference = 'Stop'

$flaggedAny = $false

# Look the group up by its well-known SID: its name is localized (it is
# "Administrateurs" on a French install), so -Group 'Administrators' fails there.
try {
    $members = @(Get-LocalGroupMember -SID 'S-1-5-32-544')
} catch {
    # Get-LocalGroupMember fails for the whole group when any one member is an
    # unresolvable SID, which is what a deleted domain account leaves behind.
    Write-Warning "Get-LocalGroupMember failed ($($_.Exception.Message)); reading the group through ADSI instead."
    $groupName = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([Security.Principal.NTAccount]).Value -replace '^.*\\', ''
    $adsiGroup = [ADSI]"WinNT://./$groupName,group"
    $members = @(foreach ($m in @($adsiGroup.Invoke('Members'))) {
        $path = $m.GetType().InvokeMember('AdsPath', 'GetProperty', $null, $m, $null)
        [pscustomobject]@{
            Name            = ($path -replace '^WinNT://', '') -replace '/', '\'
            ObjectClass     = 'Unknown'
            PrincipalSource = 'Unknown'
        }
    })
}

$orphans = @($members | Where-Object { $_.Name -match '(^|\\)S-1-\d+(-\d+)+$' })
$members = @($members | Where-Object { $_.Name -notmatch '(^|\\)S-1-\d+(-\d+)+$' })

Write-Host "=== Local Administrators group membership ($($members.Count + $orphans.Count)) ==="
$members | Select-Object Name, ObjectClass, PrincipalSource | Format-Table -AutoSize | Out-String | Write-Host

if ($AllowList.Count -gt 0) {
    Write-Host "=== Members not on the allow-list ==="
    $unexpected = $members | Where-Object {
        $short = $_.Name -replace '^.*\\', ''
        -not ($AllowList -contains $_.Name -or $AllowList -contains $short)
    }
    if ($unexpected) {
        $unexpected | Select-Object Name, ObjectClass | Format-Table -AutoSize | Out-String | Write-Host
        $flaggedAny = $true
    } else {
        Write-Host "None - every member matches the allow-list."
    }
}

Write-Host "=== Disabled, expired, or unresolvable accounts still in Administrators ==="
foreach ($orphan in $orphans) {
    Write-Host "  [ORPHAN]   $($orphan.Name) is a SID that no longer resolves to an account"
    $flaggedAny = $true
}

# Domain accounts: use the ActiveDirectory module when RSAT is installed, and
# fall back to a plain LDAP query when it is not, so a member server without
# RSAT gets a real answer rather than one "could not resolve" line per account.
$haveAdModule = [bool](Get-Command Get-ADUser -ErrorAction SilentlyContinue)

function Get-DomainAccountState {
    param([string]$SamAccountName)

    if ($haveAdModule) {
        $u = Get-ADUser -Identity $SamAccountName -Properties Enabled, AccountExpirationDate -ErrorAction Stop
        return [pscustomobject]@{ Enabled = $u.Enabled; Expires = $u.AccountExpirationDate }
    }

    $searcher = [adsisearcher]"(&(objectCategory=person)(objectClass=user)(sAMAccountName=$SamAccountName))"
    [void]$searcher.PropertiesToLoad.Add('userAccountControl')
    [void]$searcher.PropertiesToLoad.Add('accountExpires')
    $hit = $searcher.FindOne()
    if (-not $hit) { throw "no directory entry found for '$SamAccountName'" }

    $uac = [int]$hit.Properties['userAccountControl'][0]
    $expiresRaw = [int64]$hit.Properties['accountExpires'][0]
    # accountExpires is 0 or Int64.MaxValue for "never".
    $expires = if ($expiresRaw -gt 0 -and $expiresRaw -lt [int64]::MaxValue) { [datetime]::FromFileTime($expiresRaw) } else { $null }
    [pscustomobject]@{ Enabled = -not ($uac -band 2); Expires = $expires }
}

foreach ($member in $members) {
    if ($member.ObjectClass -ne 'User' -or $member.PrincipalSource -notin @('Local', 'ActiveDirectory')) {
        continue
    }
    $short = $member.Name -replace '^.*\\', ''
    try {
        if ($member.PrincipalSource -eq 'Local') {
            $acct = Get-LocalUser -Name $short -ErrorAction Stop
            $state = [pscustomobject]@{ Enabled = $acct.Enabled; Expires = $acct.AccountExpires }
        } else {
            $state = Get-DomainAccountState -SamAccountName $short
        }
        if (-not $state.Enabled) {
            Write-Host "  [DISABLED] $($member.Name) is disabled but still in Administrators"
            $flaggedAny = $true
        }
        if ($state.Expires -and $state.Expires -lt (Get-Date)) {
            Write-Host "  [EXPIRED]  $($member.Name) expired $($state.Expires) but still in Administrators"
            $flaggedAny = $true
        }
    } catch {
        Write-Host "  [UNKNOWN]  Could not resolve $($member.Name): $($_.Exception.Message)"
    }
}
if (-not $flaggedAny) {
    Write-Host "None found."
    exit 0
}
exit 1
