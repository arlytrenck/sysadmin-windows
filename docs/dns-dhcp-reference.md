# Windows DNS & DHCP Reference

Running the DNS Server and DHCP Server roles on Windows Server, from
PowerShell. Covers zones, records, forwarders, scavenging, DHCP scopes,
reservations, failover, and the checks for the problems these roles actually
have. Needs the `DnsServer` / `DhcpServer` modules (installed with the roles
or RSAT). Run elevated.

---

# DNS Server

## Zones

```powershell
Get-DnsServerZone
Add-DnsServerPrimaryZone -Name corp.example.com -ReplicationScope Domain -DynamicUpdate Secure
Add-DnsServerPrimaryZone -NetworkId 10.0.0.0/24 -ReplicationScope Domain    # reverse zone
Add-DnsServerConditionalForwarderZone -Name partner.example.net -MasterServers 192.0.2.53
Add-DnsServerForwarder -IPAddress 1.1.1.1,9.9.9.9 -PassThru
Get-DnsServerForwarder
```

**AD-integrated primary** (`-ReplicationScope Domain`) is almost always right
in a domain — zone data replicates with AD, supports secure dynamic update,
multi-master. Use standard primary/secondary only for non-AD or DMZ DNS.

`-DynamicUpdate Secure` (AD zones) lets domain members register their own
A/PTR records but stops spoofed registrations.

## Records

```powershell
Get-DnsServerResourceRecord -ZoneName corp.example.com -RRType A | Sort HostName
Add-DnsServerResourceRecordA    -ZoneName corp.example.com -Name web01 -IPv4Address 10.0.0.40 -CreatePtr
Add-DnsServerResourceRecordCName -ZoneName corp.example.com -Name intranet -HostNameAlias web01.corp.example.com
Add-DnsServerResourceRecord -ZoneName corp.example.com -Srv -Name '_ldap._tcp' -DomainName dc01.corp.example.com -Priority 0 -Weight 100 -Port 389

# change an A record (remove + add; there's no in-place set for the address)
$old = Get-DnsServerResourceRecord -ZoneName corp.example.com -Name web01 -RRType A
$new = $old.Clone(); $new.RecordData.IPv4Address = [ipaddress]'10.0.0.41'
Set-DnsServerResourceRecord -ZoneName corp.example.com -OldInputObject $old -NewInputObject $new

Remove-DnsServerResourceRecord -ZoneName corp.example.com -Name web01 -RRType A -Force
```

## Scavenging (stale record cleanup)

Dynamic records that never get cleaned up cause "wrong IP" incidents for
years. Scavenging must be enabled in **three** places or it does nothing:

```powershell
Set-DnsServerScavenging -ScavengingState $true -RefreshInterval 7.00:00:00 `
  -NoRefreshInterval 7.00:00:00 -ScavengingInterval 7.00:00:00 -ApplyOnAllZones
Set-DnsServerZoneAging -Name corp.example.com -Aging $true
# and per-server: the above -ApplyOnAllZones + a server-level ScavengingInterval
Get-DnsServerScavenging
Get-DnsServerZoneAging -Name corp.example.com
```

`NoRefresh + Refresh` = minimum age before a record can be scavenged (default
14 days total). Turn it on **deliberately** on a maintenance window — a
misconfigured aging start can delete valid static records that lack a
timestamp (static records normally have timestamp 0 = never scavenged; verify
before enabling).

## Diagnostics

```powershell
Resolve-DnsName web01.corp.example.com -Server 10.0.0.2 -DnssecOk
Resolve-DnsName -Name corp.example.com -Type SOA -Server 10.0.0.2
Clear-DnsServerCache -Force ; Clear-DnsClientCache
Get-DnsServerStatistics
Test-DnsServer -IPAddress 10.0.0.2 -ZoneName corp.example.com
Get-DnsServerDiagnostics                       # what's being logged
Set-DnsServerDiagnostics -Queries $true -Answers $true -QuestionTransactions $true   # verbose; turn off after
Get-WinEvent -LogName 'Microsoft-Windows-DNS-Server/Analytical' -MaxEvents 50   # needs the channel enabled
dnscmd /info ; dnscmd /zoneprint corp.example.com
```

Health checks that matter:
- `nslookup` the DC's own `_ldap._tcp.dc._msdcs.<domain>` SRV records — if
  those are missing, domain logon and replication break.
- Every DC should list **itself last** (or 127.0.0.1 last) in its NIC DNS,
  with a *partner* DC first, to avoid the "island" problem.
- Root hints or forwarders reachable (`Get-DnsServerForwarder`; test the
  target with `Resolve-DnsName . -Server <forwarder>`).

---

# DHCP Server

## Authorize + scopes

```powershell
Add-DhcpServerInDC -DnsName dhcp01.corp.example.com -IPAddress 10.0.0.5   # AD authorization (required)
Get-DhcpServerInDC

Add-DhcpServerv4Scope -Name 'LAN' -StartRange 10.0.0.100 -EndRange 10.0.0.240 `
  -SubnetMask 255.255.255.0 -State Active
Add-DhcpServerv4ExclusionRange -ScopeId 10.0.0.0 -StartRange 10.0.0.100 -EndRange 10.0.0.110
Set-DhcpServerv4OptionValue -ScopeId 10.0.0.0 -Router 10.0.0.1 -DnsServer 10.0.0.2,10.0.0.3 `
  -DnsDomain corp.example.com
Set-DhcpServerv4Scope -ScopeId 10.0.0.0 -LeaseDuration 8.00:00:00
```

Server-wide vs scope options: set DNS servers / domain at the **server**
level (`Set-DhcpServerv4OptionValue` with no `-ScopeId`) unless a scope needs
to differ.

## Reservations

```powershell
Add-DhcpServerv4Reservation -ScopeId 10.0.0.0 -IPAddress 10.0.0.50 `
  -ClientId 00-11-22-33-44-55 -Name printer01 -Description 'HP MFP'
Get-DhcpServerv4Reservation -ScopeId 10.0.0.0
Get-DhcpServerv4Lease -ScopeId 10.0.0.0 | Sort IPAddress |
  Select IPAddress,HostName,ClientId,AddressState,LeaseExpiryTime
# convert an active lease to a reservation:
Get-DhcpServerv4Lease -ScopeId 10.0.0.0 -ClientId 00-11-22-33-44-55 | Add-DhcpServerv4Reservation
```

## DNS registration from DHCP

```powershell
Set-DhcpServerv4DnsSetting -ScopeId 10.0.0.0 -DynamicUpdates Always `
  -DeleteDnsRROnLeaseExpiry $true -UpdateDnsRRForOlderClients $true -NameProtection $false
```

If DHCP registers records in a **secure** AD zone, run the DHCP service as a
dedicated service account and add it to the **DnsUpdateProxy** group — or
records get orphaned with the wrong owner and can't be updated later. Know
the DnsUpdateProxy security trade-off before using it.

## Failover (two DHCP servers, no split-brain)

```powershell
Add-DhcpServerv4Failover -Name 'LAN-failover' -PartnerServer dhcp02.corp.example.com `
  -ScopeId 10.0.0.0 -LoadBalancePercent 50 -SharedSecret (Read-Host) -AutoStateTransition $true
Get-DhcpServerv4Failover
Invoke-DhcpServerv4FailoverReplication -Name 'LAN-failover' -Force   # after editing scope options
```

**Hot standby** for a clear primary/backup; **load balance** for two equal
servers. Remember to re-run replication after any scope/option change — it is
not automatic for config, only for leases.

## Backup / health

```powershell
Backup-DhcpServer -Path C:\dhcp-backup                 # also runs automatically to %windir%\System32\dhcp\backup every 60 min
Export-DhcpServer -File C:\dhcp-export.xml -Leases
Get-DhcpServerv4ScopeStatistics                        # % pool in use — alert before exhaustion
Get-DhcpServerv4Scope | Where-Object { (Get-DhcpServerv4ScopeStatistics -ScopeId $_.ScopeId).PercentageInUse -gt 85 }
Get-DhcpServerDatabase                                  # cleanup interval, backup path
Get-WinEvent -LogName 'Microsoft-Windows-Dhcp-Server/Operational' -MaxEvents 50
```

Common DHCP issues: server not authorized in AD (it refuses to hand out
leases); a rogue DHCP server on the LAN (`Get-DhcpServerInDC` lists only
authorized ones — find rogues with a client packet capture or
`dhcploc.exe`); pool exhaustion (shorten lease time or widen the range);
failover partners out of sync (re-run replication).
