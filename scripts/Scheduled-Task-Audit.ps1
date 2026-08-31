<#
.SYNOPSIS
    Enumerates all scheduled tasks on the box, flagging ones that run as
    SYSTEM/high-privilege accounts, run hidden, or execute from
    user-writable locations — common persistence patterns worth a second
    look.

.DESCRIPTION
    Read-only; makes no changes. Useful for a periodic review or as part
    of incident diagnosis.

.EXAMPLE
    .\Scheduled-Task-Audit.ps1 | Tee-Object -FilePath C:\Reports\task-audit.txt
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'SilentlyContinue'

$tasks = Get-ScheduledTask | Where-Object { $_.State -ne 'Disabled' }

Write-Host "=== All enabled scheduled tasks ($($tasks.Count)) ==="
$tasks | Select-Object TaskName, TaskPath, State,
    @{N='RunAs'; E={$_.Principal.UserId}},
    @{N='Hidden'; E={$_.Settings.Hidden}} |
    Sort-Object TaskPath, TaskName | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== Tasks running as SYSTEM or an Administrators-group account ==="
$tasks | Where-Object {
    $_.Principal.UserId -match 'SYSTEM|Administrator' -or $_.Principal.RunLevel -eq 'Highest'
} | Select-Object TaskName, TaskPath, @{N='RunAs'; E={$_.Principal.UserId}}, @{N='RunLevel'; E={$_.Principal.RunLevel}} |
    Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== Hidden tasks ==="
$tasks | Where-Object { $_.Settings.Hidden } |
    Select-Object TaskName, TaskPath | Format-Table -AutoSize | Out-String | Write-Host

Write-Host "=== Tasks with an action pointing at a user-writable path (Temp/Downloads/AppData) ==="
foreach ($task in $tasks) {
    foreach ($action in $task.Actions) {
        $exec = $action.Execute
        if ($exec -and ($exec -match '\\Temp\\|\\Downloads\\|\\AppData\\')) {
            "  {0,-40} -> {1} {2}" -f $task.TaskName, $exec, $action.Arguments | Write-Host
        }
    }
}

Write-Host ""
Write-Host "Done. A task here isn't necessarily malicious — plenty of legitimate"
Write-Host "software installs its own scheduled tasks — but anything unfamiliar,"
Write-Host "especially SYSTEM-level and hidden, is worth tracing back to its source."
