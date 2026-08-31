# Windows Server Hardening Checklist

A baseline checklist for a newly provisioned Windows Server before it goes
into production. Not exhaustive — treat it as a floor, and layer your
organization's own policy (CIS Benchmarks, DISA STIGs) on top.

## Access

- [ ] Rename or disable the built-in Administrator account; use named,
      individually-audited accounts with `Run as administrator` instead.
- [ ] Enforce a strong password policy (`secpol.msc` → Account Policies, or
      Group Policy for domain-joined hosts).
- [ ] Enable account lockout policy (reasonable threshold + duration) to
      slow brute-force attempts.
- [ ] Remove unnecessary accounts from the local Administrators group —
      audit with `security-audit.ps1` / `Get-LocalGroupMember`.
- [ ] Disable the Guest account (`Disable-LocalUser -Name Guest`).
- [ ] Require MFA for any remote administrative access (RDP gateway, VPN,
      Azure AD/Entra Conditional Access).

## Network

- [ ] Enable Windows Firewall on all profiles (Domain/Private/Public); set
      default-deny inbound.
- [ ] Restrict RDP: don't expose port 3389 directly to the internet — use a
      VPN, Remote Desktop Gateway, or Just-In-Time access.
- [ ] Disable SMBv1 (`Disable-WindowsOptionalFeature -Online -FeatureName
      SMB1Protocol`) unless a legacy dependency requires it.
- [ ] Enable Network Level Authentication (NLA) for RDP.
- [ ] Review and close unnecessary listening ports —
      `network-diagnostics.ps1` lists current listeners.

## System

- [ ] Enable BitLocker on the system volume where hardware/threat model
      supports it.
- [ ] Keep Windows Update current; use `windows-update.ps1` or WSUS/Intune
      for managed patching cadence.
- [ ] Ensure Windows Defender (or your chosen AV/EDR) real-time protection
      is enabled and signatures are current.
- [ ] Disable unused Windows features/roles (`Get-WindowsFeature`) —
      smaller attack surface.
- [ ] Set an appropriate audit policy (`auditpol /get /category:*`) so
      logon, account management, and privilege-use events are actually
      logged — the activity/security scripts here assume this.

## Monitoring

- [ ] Forward event logs to a central SIEM/log collector where feasible.
- [ ] Alert on account lockouts, new Administrators-group members, and
      repeated failed logons.
- [ ] Set Security log size generously (`wevtutil sl Security
      /ms:<bytes>`) — a full log silently stops recording (or overwrites,
      depending on retention mode) if too small for your event volume.
- [ ] Schedule `package-inventory.ps1` periodically and diff against a
      known-good baseline to catch unexpected software installs.

## Before going live

- [ ] Confirm backups are running and a restore has actually been tested.
- [ ] Confirm the account performing routine maintenance is not itself a
      Domain Admin / highly privileged account unless required.
- [ ] Document the server's purpose, owner, and any exceptions to this
      checklist, and where that documentation lives.

