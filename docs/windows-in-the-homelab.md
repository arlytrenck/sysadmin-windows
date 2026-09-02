# Windows in the Homelab

Most homelabs are Linux, but a Windows box shows up for a reason: a Hyper-V
host, Active Directory practice, a game or media server, or the one
application that only runs on Windows. This is how to keep that box low-touch.

## Keep it from surprising you

- **Defer feature updates, don't block them.** On Pro/Enterprise set
  `Windows Update for Business` policies (or `sconfig` on Server Core) to
  defer feature updates 180+ days and quality updates a few days. On a lab
  box, `Set-Service wuauserv -StartupType Manual` plus a scheduled
  `Windows-Update.ps1` run is fine — just don't let it reboot on its own.
- **No automatic reboots.** `NoAutoRebootWithLoggedOnUsers = 1`, or the
  `ActiveHours` window, or gpedit `Configure Automatic Updates = 2` (notify
  only). A homelab service going down at 3am for a reboot you didn't schedule
  is exactly the failure mode to avoid.
- **Disable or tame the tasks that phone home / defrag / reindex** if the box
  is a VM on SSD — review with `Scheduled-Task-Audit.ps1`.

## Run it lean

- **Server Core** (or Hyper-V Server) over Desktop Experience for anything
  headless — smaller attack surface, fewer updates, less RAM. Manage it with
  RSAT / Windows Admin Center / PowerShell remoting from your workstation.
- If it's a VM, **dynamic memory** with a sane floor, `AutomaticStopAction =
  ShutDown` (not Save — saved-state VMs bloat and can corrupt), and
  `AutomaticStartAction = StartIfRunning`.
- Turn off the bits you don't use: SysMain/Superfetch on SSD VMs, Xbox
  services, Windows Search if nothing needs it.

## Remote access

- **RDP over the mesh VPN, never a port-forward.** Bind RDP to the VPN
  interface, or firewall 3389 to the VPN subnet only. See the Linux repo's
  `mesh-vpn-remote-access.md` — Tailscale has a Windows client.
- For Server Core, `Enter-PSSession` / `Invoke-Command` over WinRM (also
  restricted to the VPN subnet) covers most of it.

## Backup

- **`wbadmin`** for a bare-metal / system-state image on a schedule:
  ```
  wbadmin start backup -backupTarget:\\nas\backups\%COMPUTERNAME% `
    -include:C: -allCritical -vssFull -quiet
  ```
- **`restic`** or **Duplicati** for file-level, deduped, encrypted backups to
  a NAS or object storage — the Windows equivalent of the Linux
  `age-backup.sh` pattern.
- Hyper-V VMs: back up the host's config with `Export-HyperV-Config.ps1` and
  the VHDs with production checkpoints (`Checkpoint-VM`) + a copy of the
  exported VM, or a backup tool that's Hyper-V aware.

## Snapshot the config

Commit a regular snapshot to a repo so drift is visible and a rebuild has a
reference:

- `Export-Config-Snapshot.ps1` — services, scheduled tasks, local groups,
  firewall, features, hotfixes, autoruns.
- `Export-HyperV-Config.ps1` — host + per-VM settings, if it's a Hyper-V host.
- `Compare-Config-Drift.ps1` — diff against last week's.

## Hardening

Start from `server-hardening-checklist.md`. The homelab-specific additions:
disable SMBv1, require SMB signing, turn on `Local Administrator Password
Solution` (LAPS) even for a lab if it's domain-joined, and keep Defender real-
time protection on (`Defender-Status-Check.ps1`) — a lab box still browses the
internet.
