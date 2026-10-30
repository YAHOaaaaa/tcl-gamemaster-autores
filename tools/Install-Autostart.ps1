<#
.SYNOPSIS
  Starts TclAutoRes automatically when you sign in to Windows (Task Scheduler, current user,
  normal privileges - no administrator rights). By default it builds and starts TclAutoRes.exe
  (tools\Build-Exe.ps1), which shows the tray icon, runs the watcher in the background and lets you
  turn it on/off. -NoExe starts the tray with powershell.exe instead (the icon is then listed as
  "Windows PowerShell"). -NoTray starts the watcher alone (no icon). -Remove deletes the task again.
  Running copies of TclAutoRes in this session are stopped first, so only one copy runs.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1 -Remove
#>
[CmdletBinding()]
param([switch]$Remove, [switch]$NoTray, [switch]$NoExe, [string]$TaskName = 'TclAutoRes')

$ErrorActionPreference = 'Stop'
if ($TaskName -notmatch '^[A-Za-z0-9_\-]{1,64}$') { throw 'invalid -TaskName' }

# Ends the tray/watcher started from any TclAutoRes folder in this Windows session (and their adb logcat).
function Stop-TclAutoResRunning {
    # A watcher may already be gone with its tray (/T); taskkill's "not found" must not stop this script.
    $ErrorActionPreference = 'Continue'
    $session = (Get-Process -Id $PID).SessionId
    Get-CimInstance Win32_Process -Filter "Name='TclAutoRes.exe' OR Name='powershell.exe'" |
        Where-Object { $_.ProcessId -ne $PID -and $_.SessionId -eq $session -and ($_.Name -eq 'TclAutoRes.exe' -or $_.CommandLine -match 'TclAutoRes(Tray)?\.ps1') } |
        ForEach-Object {
            Write-Host "stopping running TclAutoRes process $($_.ProcessId)"
            & "$env:SystemRoot\System32\taskkill.exe" /PID $_.ProcessId /T /F 2>&1 | Out-Null
        }
}

if ($Remove) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "removed scheduled task '$TaskName'"
    } else { Write-Host "no scheduled task '$TaskName'" }
    Stop-TclAutoResRunning
    exit 0
}

$root = Split-Path -Parent $PSScriptRoot
$config = Join-Path $root 'config\config.json'
if (-not (Test-Path -LiteralPath $config)) { throw "create $config first (copy config\config.example.json)" }

# Stop an older registration and running copies first so only one copy runs (and the .exe can be rebuilt).
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
Stop-TclAutoResRunning
Start-Sleep -Seconds 1

$useExe = -not ($NoTray -or $NoExe)
$exe = Join-Path $root 'TclAutoRes.exe'
if ($useExe) {
    try { & (Join-Path $PSScriptRoot 'Build-Exe.ps1') }
    catch { Write-Warning "could not build TclAutoRes.exe ($($_.Exception.Message)); using powershell.exe instead"; $useExe = $false }
}

if ($useExe) {
    $action = New-ScheduledTaskAction -Execute $exe -Argument "-Config `"$config`"" -WorkingDirectory $root
} else {
    $scriptPath = Join-Path $root $(if ($NoTray) { 'TclAutoRes.ps1' } else { 'TclAutoResTray.ps1' })
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
}

$user = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description 'TclAutoRes: switch PC display mode when the TCL TV screen ratio changes' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName
Write-Host "registered and started scheduled task '$TaskName' for $user (runs at sign-in, no admin rights)"
Write-Host ("starts: {0}" -f $(if ($useExe) { $exe } elseif ($NoTray) { 'watcher only (no tray icon)' } else { 'tray via powershell.exe' }))
Write-Host "log: $env:LOCALAPPDATA\TclAutoRes\tclautores.log"
