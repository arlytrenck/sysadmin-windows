# Resource library

This collection prioritizes Microsoft and project-maintained references for the Windows Server, PowerShell, identity, and recovery topics covered here. Use them to verify version-specific behavior before making production changes.

## Windows Server and PowerShell

- [Windows Server documentation](https://learn.microsoft.com/en-us/windows-server/) — roles, deployment, security, and operations.
- [PowerShell documentation](https://learn.microsoft.com/en-us/powershell/) — language, remoting, modules, and script authoring.
- [PowerShell Gallery](https://www.powershellgallery.com/) — module discovery; review publisher and module source before installation.
- [Sysinternals](https://learn.microsoft.com/en-us/sysinternals/) — trusted troubleshooting and diagnostics utilities.

## Active Directory, Group Policy, DNS, and DHCP

- [Active Directory Domain Services documentation](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/) — AD DS architecture, deployment, and operations.
- [DNS and AD DS](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/plan/dns-and-ad-ds) — the DNS dependency that must be healthy for directory operations.
- [Group Policy documentation](https://learn.microsoft.com/en-us/windows-server/identity/ad-ds/manage/group-policy/group-policy-overview) — policy design and management.
- [Windows Server DNS documentation](https://learn.microsoft.com/en-us/windows-server/networking/dns/dns-top) — DNS zones, records, and troubleshooting.

## Security, patching, backup, and virtualization

- [Microsoft Defender documentation](https://learn.microsoft.com/en-us/defender-endpoint/) — endpoint protection and investigation guidance.
- [Windows Update documentation](https://learn.microsoft.com/en-us/windows/deployment/update/) — servicing and update management.
- [Windows Server Backup overview](https://learn.microsoft.com/en-us/windows-server/administration/windows-server-backup/windows-server-backup) — backup capabilities and recovery planning.
- [Hyper-V documentation](https://learn.microsoft.com/en-us/windows-server/virtualization/hyper-v/) — hosts, virtual machines, networking, and checkpoints.
- [Microsoft security baselines](https://learn.microsoft.com/en-us/windows/security/operating-system-security/device-management/windows-security-configuration-framework/windows-security-baselines) — baseline security guidance for Windows.

## Practical use

Keep this repository's scripts in a source-controlled test path, run read-only discovery first, and use WhatIf or a maintenance window for state-changing actions. For directory services, validate DNS, time, replication, backup health, and rollback options before changing identities, group membership, or policy.
