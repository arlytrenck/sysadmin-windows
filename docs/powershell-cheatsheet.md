# PowerShell Cheatsheet

Core language and pipeline reference — the stuff that's easy to blank on
mid-task. For remoting and event log querying specifically, see
[powershell-remoting-eventlog-reference.md](powershell-remoting-eventlog-reference.md).
For Active Directory/Group Policy cmdlets, see
[active-directory-reference.md](active-directory-reference.md).

## Getting help (before guessing at parameter names)

```powershell
Get-Help Get-Service -Full
Get-Help Get-Service -Examples
Get-Command -Verb Get -Noun *Service*        # discover cmdlets by verb/noun
Get-Member -InputObject (Get-Service)[0]     # what properties/methods does this object have
Update-Help -Force                           # refresh local help content (needs internet, run as admin)
```

## The pipeline passes objects, not text

```powershell
Get-Process | Where-Object { $_.CPU -gt 100 }             # filter on a real property
Get-Process | Sort-Object CPU -Descending | Select-Object -First 5
Get-Service | Where-Object Status -eq 'Running'            # simplified comparison syntax
Get-ChildItem | ForEach-Object { $_.Name.ToUpper() }
Get-Process notepad | Stop-Process -WhatIf                 # preview a state-changing action
```
`-WhatIf` on any cmdlet that supports `ShouldProcess` (most cmdlets that
change state) shows what would happen without doing it — check before
running the real thing against production.

## Variables and types

```powershell
$x = 5                              # loosely typed by default
[int]$count = "5"                    # explicit cast
$name = "server01"
"Host: $name has $count cores"       # string interpolation
$path = 'C:\logs\{0}.txt' -f $name   # -f format operator, no interpolation surprises
$null -eq $value                     # compare against $null with $null on the left
```

## Arrays and hashtables

```powershell
$arr = @(1, 2, 3)
$arr += 4                            # arrays are fixed-size; += creates a new array
$arr | Where-Object { $_ -gt 1 }

$h = @{ Name = 'srv01'; Role = 'db' }
$h['Role']
$h.Role                              # dot access works too
$h.Keys; $h.Values
foreach ($key in $h.Keys) { "$key = $($h[$key])" }

$list = [System.Collections.Generic.List[string]]::new()   # for heavy append use — avoids
$list.Add('item')                                           # the += reallocation cost
```

## Comparison and logical operators

```powershell
-eq -ne -gt -lt -ge -le      # value comparison (case-insensitive for strings by default)
-ceq -cne                    # case-sensitive variants
-like  'srv*'                # wildcard match
-match '^srv\d+$'            # regex match, sets $matches on success
-contains                    # is an item in a collection
-in                          # is a value in a collection (reversed -contains)
-and -or -not                # logical, short-circuit
```

## String formatting and manipulation

```powershell
"{0,-20} {1,10:N2}" -f "Label", 123.456      # left-pad to 20, right-align number to 10, 2 decimals
"value: $($obj.Property)"                    # subexpression inside a string
$s.Trim(); $s.ToUpper(); $s.Split(',')
$s -replace 'foo', 'bar'                     # regex replace
$s -split ','                                # regex split
[string]::IsNullOrWhiteSpace($s)
```

## Providers and PSDrives

```powershell
Get-PSDrive                          # filesystem, registry (HKLM:/HKCU:), env:, cert:, etc.
Get-ChildItem HKLM:\SOFTWARE          # the registry is just another drive to Get-ChildItem
Get-Item env:PATH
Test-Path C:\Some\Path
```

## Error handling

```powershell
$ErrorActionPreference = 'Stop'      # make non-terminating errors throw, so try/catch sees them

try {
    Get-Item 'C:\does-not-exist' -ErrorAction Stop
} catch {
    Write-Warning "Failed: $($_.Exception.Message)"
} finally {
    Write-Host "Always runs"
}

Get-Item 'C:\does-not-exist' -ErrorAction SilentlyContinue    # per-call override
$Error[0]                                                       # last error, regardless of handling
```

## Modules

```powershell
Get-Module -ListAvailable            # every module PowerShell can see
Import-Module ActiveDirectory
Get-InstalledModule                  # modules installed via PowerShellGet
Install-Module -Name PSWindowsUpdate -Scope CurrentUser
```

## Profile and session setup

```powershell
$PROFILE                             # path to the current user/host profile script
notepad $PROFILE                     # edit it (create the file if Test-Path is false)
$PSVersionTable                      # PowerShell/.NET/OS version info
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser   # allow local scripts to run
```

## Notes

- `-ErrorAction Stop` plus `try`/`catch` is the reliable pattern; relying
  on a cmdlet's default error behavior means some failures silently
  continue the script instead of stopping it.
- Prefer full cmdlet names and parameters in anything committed to a
  repo — aliases (`gci`, `%`, `?`) and positional parameters read fine
  interactively but make scripts harder for someone else (or future you)
  to follow.
- `[PSCustomObject]@{ Name = 'x'; Value = 1 }` is usually the right way to
  build structured output — it formats cleanly with `Format-Table` and
  pipes into `Export-Csv`/`ConvertTo-Json` without extra work.
