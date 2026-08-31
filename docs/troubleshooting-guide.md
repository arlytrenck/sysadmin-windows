# Windows Server Troubleshooting Guide

Quick-reference commands for common problem areas. PowerShell-first, with
the classic command-line equivalent noted where it's still commonly used.

## Disk / storage

```powershell
Get-PSDrive -PSProvider FileSystem                    # free space per drive
Get-Volume                                             # health status per volume
.\Disk-Usage-Report.ps1                                # largest subfolders + alerting
Get-CimInstance Win32_LogicalDisk | Select DeviceID, FreeSpace, Size
```

## Memory / CPU

```powershell
Get-Counter '\Memory\Available MBytes'
Get-Counter '\Processor(_Total)\% Processor Time'
Get-Process | Sort-Object CPU -Descending | Select -First 15
Get-Process | Sort-Object WS -Descending | Select -First 15   # working set (RAM)
```

## Services

```powershell
Get-Service | Where-Object Status -ne 'Running'        # everything not running
.\Service-Health-Check.ps1 -ServiceNames <name> -Restart
Get-EventLog -LogName System -Source 'Service Control Manager' -Newest 20
```

## Event logs

```powershell
Get-WinEvent -LogName System -MaxEvents 50
Get-WinEvent -FilterHashtable @{LogName='Application'; Level=2} -MaxEvents 50   # errors only
Get-EventLog -LogName Application -EntryType Error -Newest 20                  # legacy cmdlet, still common
wevtutil qe System /c:20 /rd:true /f:text                                      # from cmd.exe
```

## Networking

```powershell
Get-NetIPConfiguration
Test-NetConnection -ComputerName host -Port 443
Resolve-DnsName example.com
Get-NetTCPConnection -State Listen
ipconfig /flushdns
.\Network-Diagnostics.ps1
```

## Permissions

```powershell
Get-Acl C:\path\to\file | Format-List
icacls C:\path\to\folder                                # classic, still very common
takeown /f C:\path\to\file                               # take ownership when locked out
```

## Windows Update / patch issues

```powershell
Get-HotFix | Sort-Object InstalledOn -Descending | Select -First 10
Get-WindowsUpdateLog                                    # decodes ETW trace to a readable log
sfc /scannow                                             # check for corrupted system files
DISM /Online /Cleanup-Image /RestoreHealth                # repair the component store
```

## Boot / startup problems

```powershell
Get-CimInstance Win32_OperatingSystem | Select LastBootUpTime
Get-ScheduledTask | Where-Object State -eq 'Ready'       # startup tasks
Get-CimInstance Win32_StartupCommand                     # legacy startup entries (Run keys, etc.)
shutdown /r /o /t 0                                      # reboot into Advanced Startup Options
```

## Active Directory / domain issues (domain-joined hosts)

```powershell
Test-ComputerSecureChannel                               # verify machine trust with the domain
nltest /sc_verify:<domain>
gpresult /r                                               # applied Group Policy summary
gpupdate /force
Get-ADUser -Identity <user> -Properties LockedOut, PasswordExpired   # requires RSAT
```

