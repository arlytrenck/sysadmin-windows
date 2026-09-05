# Windows Networking Cheatsheet

Quick reference for inspecting and troubleshooting networking on Windows.
The `Get-Net*`/`Test-Net*` cmdlet family (NetTCPIP module) covers most of
what `netsh` used to be needed for — `netsh` is included below since it's
still common in older scripts and some configuration only exposes itself
there.

## Interfaces and addresses

```powershell
Get-NetAdapter                                  # all adapters, link state
Get-NetAdapter | Where-Object Status -eq 'Up'
Get-NetIPAddress -AddressFamily IPv4             # all IPv4 addresses, per interface
Get-NetIPConfiguration                            # address + gateway + DNS in one view
Disable-NetAdapter -Name "Ethernet2"; Enable-NetAdapter -Name "Ethernet2"
```

## Routing

```powershell
Get-NetRoute                                      # full routing table
Get-NetRoute -DestinationPrefix '0.0.0.0/0'        # default route(s)
New-NetRoute -DestinationPrefix "10.0.1.0/24" -InterfaceAlias "Ethernet" -NextHop "10.0.0.1"
route print                                        # legacy view, sometimes easier to read
```

## DNS

```powershell
Resolve-DnsName example.com                       # full query
Resolve-DnsName example.com -Type MX
Resolve-DnsName example.com -Server 1.1.1.1        # query a specific resolver
Get-DnsClientServerAddress                          # configured resolvers per interface
Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses "1.1.1.1","1.0.0.1"
Clear-DnsClientCache                                # flush local resolver cache
Get-DnsClientCache                                  # view what's currently cached
ipconfig /flushdns                                  # legacy equivalent
```

## Connectivity testing

```powershell
Test-Connection example.com -Count 4                       # ping equivalent, returns objects
Test-NetConnection example.com -Port 443                    # TCP port reachability
Test-NetConnection example.com -TraceRoute                  # traceroute equivalent
Test-NetConnection -ComputerName dc01 -CommonTCPPort SMB     # WinRM/SMB/RDP/HTTP shortcuts
```

## Listening ports and active connections

```powershell
Get-NetTCPConnection -State Listen                # every listening TCP endpoint
Get-NetUDPEndpoint                                  # every listening UDP endpoint
Get-NetTCPConnection | Where-Object State -eq 'Established'
Get-Process -Id (Get-NetTCPConnection -LocalPort 443).OwningProcess   # what owns a port
netstat -ano | findstr ":443"                       # legacy equivalent
```
See [Listening-Ports-Audit.ps1](../scripts/Listening-Ports-Audit.ps1) for
a script version of this, with an optional allowlist check.

## Windows Firewall

```powershell
Get-NetFirewallRule -Enabled True -Direction Inbound | Select DisplayName, Action
New-NetFirewallRule -DisplayName "Allow-8443" -Direction Inbound -LocalPort 8443 -Protocol TCP -Action Allow
Disable-NetFirewallRule -DisplayName "Allow-8443"
Get-NetFirewallProfile                              # Domain/Private/Public profile state
Set-NetFirewallProfile -Profile Public -Enabled True
```
See [Firewall-Rules-Dump.ps1](../scripts/Firewall-Rules-Dump.ps1) for a
full ruleset snapshot suitable for diffing.

## netsh (legacy, still needed for a few things)

```
netsh interface ip show config                # per-interface IP config
netsh advfirewall show allprofiles             # firewall profile state
netsh advfirewall firewall show rule name=all  # every firewall rule, verbose
netsh wlan show profiles                       # saved Wi-Fi profiles
netsh wlan show profile name="SSID" key=clear  # recover a saved Wi-Fi password
```

## SMB shares

```powershell
Get-SmbShare                                    # shares hosted by this machine
Get-SmbConnection                               # active outbound SMB sessions
Get-SmbMapping                                  # mapped drives for the current session
New-SmbShare -Name "Data" -Path "D:\Data" -FullAccess "DOMAIN\Admins"
Test-NetConnection dc01 -CommonTCPPort SMB      # confirm SMB is actually reachable
```

## Notes

- `Test-NetConnection` is the single most useful troubleshooting cmdlet
  here — it combines ping, port-check, and route/interface info in one
  call and returns a structured object instead of parsed text.
- A `New-NetFirewallRule`/`Set-DnsClientServerAddress` change takes effect
  immediately; there's no separate "apply" step the way some GUI panels
  imply — verify the change with the matching `Get-*` cmdlet right after.
- `netsh` output is plain text meant for humans, not objects — prefer the
  `Get-Net*`/`Test-Net*` cmdlets in anything scripted, and reach for
  `netsh` only for the handful of things (saved Wi-Fi keys, some legacy
  IPv4/IPv6 transition settings) that don't have a modern cmdlet yet.
