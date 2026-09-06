# Windows Firewall Cheatsheet

Windows Defender Firewall with Advanced Security from PowerShell (and a bit of
`netsh`). Inspecting rules, adding scoped rules, profiles, logging. The
snapshot script is
[Firewall-Rules-Dump.ps1](../scripts/Firewall-Rules-Dump.ps1). Run elevated.

## Profiles

Three profiles — `Domain`, `Private`, `Public` — each with its own default
actions. A server on a trusted LAN should be `Domain` (if joined) or
`Private`, never `Public`.

```powershell
Get-NetFirewallProfile | Select Name,Enabled,DefaultInboundAction,DefaultOutboundAction,LogFileName
Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow
Get-NetConnectionProfile                                  # which profile each NIC is using
Set-NetConnectionProfile -InterfaceAlias 'Ethernet' -NetworkCategory Private
```

## Inspect rules

```powershell
Get-NetFirewallRule -Enabled True -Direction Inbound |
  Where-Object Action -eq 'Allow' |
  Sort-Object DisplayName

# rules are stored normalized — join the filter objects to see address/port
Get-NetFirewallRule -DisplayName 'Remote Desktop*' |
  Get-NetFirewallPortFilter
Get-NetFirewallRule -DisplayName 'Remote Desktop*' |
  Get-NetFirewallAddressFilter

# one-liner: rule + port + remote address in a table
Get-NetFirewallRule -Enabled True -Direction Inbound -Action Allow | ForEach-Object {
  $p = $_ | Get-NetFirewallPortFilter
  $a = $_ | Get-NetFirewallAddressFilter
  [pscustomobject]@{
    Name=$_.DisplayName; Proto=$p.Protocol; LocalPort=$p.LocalPort;
    RemoteAddr=$a.RemoteAddress; Profile=$_.Profile; Group=$_.DisplayGroup
  }
} | Sort-Object Name | Format-Table -Auto
```

```cmd
netsh advfirewall firewall show rule name=all            :: classic view
netsh advfirewall show allprofiles                       :: profile summary
```

## Add / change rules

```powershell
# allow a service, scoped to a management subnet, private profile only
New-NetFirewallRule -DisplayName 'App API 8443 (mgmt)' -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 8443 -RemoteAddress 10.0.0.0/24 -Profile Private

# tighten a built-in rule instead of making a new one (RDP example)
Set-NetFirewallRule -DisplayGroup 'Remote Desktop' -RemoteAddress 10.0.0.0/24 -Profile Domain,Private
Disable-NetFirewallRule -DisplayGroup 'Remote Desktop' -Profile Public

# enable/disable a rule group
Enable-NetFirewallRule  -DisplayGroup 'Windows Remote Management'
Disable-NetFirewallRule -DisplayGroup 'File and Printer Sharing'   # if this box isn't a file server

# remove a rule you added
Remove-NetFirewallRule -DisplayName 'App API 8443 (mgmt)'
```

Scope every rule you add: `-RemoteAddress`, `-Profile`, and the narrowest
`-LocalPort`/`-Protocol` that works. An unscoped `Allow Any` inbound rule is
the thing audits flag.

## Program / service rules

```powershell
New-NetFirewallRule -DisplayName 'MyApp' -Direction Inbound -Action Allow `
  -Program 'C:\Program Files\MyApp\myapp.exe' -Profile Private
New-NetFirewallRule -DisplayName 'MyAppSvc' -Direction Inbound -Action Allow `
  -Service 'MyAppSvc' -Protocol TCP -LocalPort 9000
```

## Block outbound (targeted)

Default outbound is Allow. To block a specific program from calling home:

```powershell
New-NetFirewallRule -DisplayName 'Block telemetry.exe out' -Direction Outbound `
  -Action Block -Program 'C:\path\telemetry.exe' -Profile Any
```

Flipping `DefaultOutboundAction` to `Block` on a server is a project — you
must first enumerate and allow everything it legitimately needs.

## Logging

```powershell
Set-NetFirewallProfile -Name Domain,Private -LogAllowed True -LogBlocked True `
  -LogFileName '%SystemRoot%\System32\LogFiles\Firewall\pfirewall.log' -LogMaxSizeKilobytes 8192

Get-Content $env:SystemRoot\System32\LogFiles\Firewall\pfirewall.log -Tail 40 -Wait
```

Turn `LogAllowed` off again after you've diagnosed the issue — it's noisy.
The corresponding event-log channel:

```powershell
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=5152,5157} -MaxEvents 50   # WFP drops (needs audit policy on)
```

## Backup / restore / reset

```cmd
netsh advfirewall export "C:\backup\firewall.wfw"
netsh advfirewall import "C:\backup\firewall.wfw"
netsh advfirewall reset                                  :: back to Windows defaults — destructive
```

Group Policy firewall rules are merged with local rules; if a rule "won't
delete" or keeps coming back, it's coming from a GPO —
`gpresult /h` and check *Windows Defender Firewall with Advanced Security*.
`Get-NetFirewallRule -PolicyStore ActiveStore` shows the effective merged
set; `-PolicyStore <GPO>` shows just that store.

## Quick reachability checks

```powershell
Test-NetConnection host -Port 443                        # TCP connect + route + DNS
Test-NetConnection host -CommonTCPPort RDP
Get-NetTCPConnection -State Listen | Select LocalAddress,LocalPort,OwningProcess
Get-Process -Id (Get-NetTCPConnection -LocalPort 443 -State Listen).OwningProcess
```
