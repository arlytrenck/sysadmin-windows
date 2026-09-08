# Windows Server Bootstrap Checklist

Day-0 procedure for a fresh Windows Server (2019/2022/2025), Core or Desktop
Experience. The Linux companion is
[sysadmin-linux/new-server-bootstrap-checklist.md](https://github.com/arlytrenck/sysadmin-linux/blob/main/docs/new-server-bootstrap-checklist.md).
Run everything from an elevated PowerShell session. Adapt names/IPs.

## 1. Identity and naming

- [ ] Rename the machine and reboot:
  ```powershell
  Rename-Computer -NewName SRV-APP-01 -Restart
  ```
- [ ] Set the local Administrator password from your password manager; do
  **not** reuse a build image's password.
- [ ] Create a dedicated admin account for yourself; keep the built-in
  `Administrator` as break-glass only:
  ```powershell
  New-LocalUser -Name svc-adm -Description 'Named admin' -Password (Read-Host -AsSecureString)
  Add-LocalGroupMember -Group Administrators -Member svc-adm
  ```
- [ ] Disable the built-in Guest account (usually already disabled):
  `Disable-LocalUser -Name Guest`

## 2. Network

- [ ] Static IP / reservation, correct DNS servers, correct DNS suffix:
  ```powershell
  Get-NetAdapter
  New-NetIPAddress -InterfaceAlias 'Ethernet' -IPAddress 10.0.0.20 -PrefixLength 24 -DefaultGateway 10.0.0.1
  Set-DnsClientServerAddress -InterfaceAlias 'Ethernet' -ServerAddresses 10.0.0.2,10.0.0.3
  Set-DnsClient -InterfaceAlias 'Ethernet' -ConnectionSpecificSuffix 'corp.example.com'
  ```
- [ ] Set the network profile to `Private` or `DomainAuthenticated`, never
  `Public` for a server on a trusted LAN:
  `Set-NetConnectionProfile -InterfaceAlias 'Ethernet' -NetworkCategory Private`
- [ ] Confirm forward + reverse DNS resolve for the new name.

## 3. Time

- [ ] Point W32Time at a real source (domain hierarchy, or an NTP pool for a
  standalone box) and verify sync:
  ```powershell
  w32tm /config /manualpeerlist:"time.example.com,0x8" /syncfromflags:manual /update
  Restart-Service w32time
  w32tm /resync ; w32tm /query /status
  ```
  Time skew > 5 min breaks Kerberos domain join.

## 4. Updates and baseline

- [ ] Fully patch before anything else goes on the box:
  ```powershell
  Install-Module PSWindowsUpdate -Force
  Get-WindowsUpdate -Install -AcceptAll -AutoReboot
  ```
- [ ] Set the update ring / WSUS / update deadline per
  [patch-management-guide.md](patch-management-guide.md).
- [ ] Snapshot the clean baseline:
  `.\scripts\Export-Config-Snapshot.ps1 -Path C:\baseline\day0.json`
- [ ] Record installed roles/features + software inventory
  (`.\scripts\Package-Inventory.ps1`).

## 5. Remote management

- [ ] Enable and lock down RDP (NLA required, specific group only):
  ```powershell
  Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 0
  Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name UserAuthentication -Value 1
  Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
  # then restrict the RDP firewall rule's RemoteAddress to your mgmt subnet (step 6)
  ```
- [ ] Enable PowerShell Remoting if you'll use it: `Enable-PSRemoting -Force`
  (domain/private profile only). See
  [powershell-remoting-eventlog-reference.md](powershell-remoting-eventlog-reference.md).
- [ ] For Server Core, confirm you can reach it from your admin box via
  `Enter-PSSession` / RSAT / Windows Admin Center before you walk away.

## 6. Firewall

- [ ] Confirm all three profiles are **On** with inbound default = Block:
  ```powershell
  Get-NetFirewallProfile | Select Name,Enabled,DefaultInboundAction
  Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow
  ```
- [ ] Scope management rules (RDP, WinRM, WMI) to your admin subnet only.
  See [windows-firewall-cheatsheet.md](windows-firewall-cheatsheet.md).
- [ ] Turn on dropped-packet logging while you validate, then dial it back.

## 7. Hardening pass

- [ ] Run [server-hardening-checklist.md](server-hardening-checklist.md) in
  full. Highlights:
  - [ ] Apply a security baseline (Microsoft Security Compliance Toolkit GPO,
    or CIS) rather than hand-setting policies.
  - [ ] SMB1 disabled: `Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol`
  - [ ] LLMNR / NetBIOS-over-TCP/IP disabled.
  - [ ] `Set-ExecutionPolicy RemoteSigned` (or AllSigned) machine-wide.
  - [ ] Defender real-time protection on; add role-appropriate exclusions
    only (`.\scripts\Defender-Status-Check.ps1`).
  - [ ] BitLocker on the OS and data volumes if the hardware supports it
    (`.\scripts\BitLocker-Status-Audit.ps1`); escrow recovery keys.
  - [ ] Audit policy: logon/logoff, account management, privilege use,
    process creation → forwarded to your SIEM / collector.

## 8. Role install

- [ ] Install only the roles this server exists for
  (`Install-WindowsFeature <name> -IncludeManagementTools`). Don't install
  the GUI/DE on a box that doesn't need it.
- [ ] Put application data on a **separate volume** from the OS.
- [ ] Configure the role's own logging, backup, and monitoring hooks.

## 9. Backup and monitoring

- [ ] Windows Server Backup / your backup product configured and a **restore
  tested**. See [backup-dr-testing-runbook.md](backup-dr-testing-runbook.md).
- [ ] System State backup scheduled (critical for DCs, CAs).
- [ ] Monitoring agent installed; host shows up in the dashboard with disk,
  CPU, memory, service, and event-log checks
  ([monitoring-alerting-guide.md](monitoring-alerting-guide.md)).
- [ ] Alert on disk < 20% free and on pending-reboot age.

## 10. Domain join (if applicable)

- [ ] Time in sync (step 3), DNS pointing at domain controllers (step 2).
- [ ] `Add-Computer -DomainName corp.example.com -OUPath 'OU=Servers,DC=corp,DC=example,DC=com' -Restart`
- [ ] After reboot: `gpupdate /force`, then `gpresult /h C:\gpresult.html` to
  confirm the expected GPOs applied. See
  [group-policy-reference.md](group-policy-reference.md).
- [ ] Remove the box from any local groups that the domain now manages.

## 11. Document and snapshot

- [ ] Record: hostname, IP, purpose, roles, owner, dependencies, backup
  location, in your inventory / CMDB.
- [ ] Final `Export-Config-Snapshot.ps1` → commit to your config repo.
- [ ] Note the build date and the baseline image/ISO used.
- [ ] If virtual: take a checkpoint/snapshot labelled "post-bootstrap",
  remove it after a week of stable operation.
