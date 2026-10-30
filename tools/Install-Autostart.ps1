<#
.SYNOPSIS
  Starts TclAutoRes automatically when you sign in to Windows (Task Scheduler, current user,
  normal privileges - no administrator rights). By default it starts the tray icon
  (TclAutoResTray.ps1), which runs the watcher in the background and lets you turn it on/off.
  -NoTray starts the watcher alone (no icon). -Remove deletes the task again.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1 -Remove
#>
[CmdletBinding()]
param([switch]$Remove, [switch]$NoTray, [string]$TaskName = 'TclAutoRes')

$ErrorActionPreference = 'Stop'
if ($TaskName -notmatch '^[A-Za-z0-9_\-]{1,64}$') { throw 'invalid -TaskName' }

if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "removed scheduled task '$TaskName'"
    } else { Write-Host "no scheduled task '$TaskName'" }
    exit 0
}

$root = Split-Path -Parent $PSScriptRoot
$scriptPath = Join-Path $root $(if ($NoTray) { 'TclAutoRes.ps1' } else { 'TclAutoResTray.ps1' })
$config = Join-Path $root 'config\config.json'
if (-not (Test-Path -LiteralPath $config)) { throw "create $config first (copy config\config.example.json)" }

$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$psArgs = "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptPath`" -Config `"$config`""
# On Windows 11 with Windows Terminal as the default terminal, -WindowStyle Hidden still leaves an empty
# terminal window. Starting through "conhost.exe --headless" (Windows 10 1809+) creates no window at all.
$conhost = Join-Path $env:SystemRoot 'System32\conhost.exe'
if (Test-Path -LiteralPath $conhost) {
    $action = New-ScheduledTaskAction -Execute $conhost -Argument "--headless `"$psExe`" $psArgs" -WorkingDirectory $root
} else {
    $action = New-ScheduledTaskAction -Execute $psExe -Argument $psArgs -WorkingDirectory $root
}
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
# Stop an older registration first so only one copy runs.
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'TclAutoRes: switch PC display mode when the TCL TV screen ratio changes' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "registered and started scheduled task '$TaskName' for $user (runs at sign-in, no admin rights)"
Write-Host "log: $env:LOCALAPPDATA\TclAutoRes\tclautores.log"
