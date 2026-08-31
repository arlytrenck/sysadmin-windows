<#
.SYNOPSIS
    Create, disable, enable, or remove local Windows user accounts, with
    optional local Administrators group membership.

.DESCRIPTION
    Thin wrapper around the Microsoft.PowerShell.LocalAccounts module
    (New-LocalUser / Disable-LocalUser / Enable-LocalUser / Remove-LocalUser)
    for the common day-to-day account lifecycle actions. Must be run
    elevated.

.PARAMETER Action
    One of: Create, Disable, Enable, Remove.

.PARAMETER UserName
    The local account to act on.

.PARAMETER AddToAdmins
    With -Action Create, also add the new user to the local Administrators
    group.

.PARAMETER FullName
    With -Action Create, the account's full display name.

.EXAMPLE
    .\User-Mgmt.ps1 -Action Create -UserName svc-backup -FullName "Backup Service"

.EXAMPLE
    .\User-Mgmt.ps1 -Action Disable -UserName jsmith

.EXAMPLE
    .\User-Mgmt.ps1 -Action Remove -UserName old-contractor
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Create', 'Disable', 'Enable', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$UserName,

    [switch]$AddToAdmins,

    [string]$FullName = ''
)

$ErrorActionPreference = 'Stop'

$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must be run from an elevated (Administrator) PowerShell session."
}

switch ($Action) {
    'Create' {
        if (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue) {
            throw "User '$UserName' already exists."
        }
        $securePassword = Read-Host -Prompt "Enter initial password for $UserName" -AsSecureString
        if ($PSCmdlet.ShouldProcess($UserName, "Create local user")) {
            New-LocalUser -Name $UserName -Password $securePassword -FullName $FullName -PasswordNeverExpires:$false | Out-Null
            Write-Host "Created user '$UserName'."
            if ($AddToAdmins) {
                Add-LocalGroupMember -Group 'Administrators' -Member $UserName
                Write-Host "Added '$UserName' to local Administrators."
            }
        }
    }
    'Disable' {
        if ($PSCmdlet.ShouldProcess($UserName, "Disable local user")) {
            Disable-LocalUser -Name $UserName
            Write-Host "Disabled user '$UserName'."
        }
    }
    'Enable' {
        if ($PSCmdlet.ShouldProcess($UserName, "Enable local user")) {
            Enable-LocalUser -Name $UserName
            Write-Host "Enabled user '$UserName'."
        }
    }
    'Remove' {
        if ($PSCmdlet.ShouldProcess($UserName, "Remove local user")) {
            Remove-LocalUser -Name $UserName
            Write-Host "Removed user '$UserName'."
        }
    }
}

