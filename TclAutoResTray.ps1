<#
.SYNOPSIS
  System-tray front end for TclAutoRes. Runs the watcher (TclAutoRes.ps1) in the background as a hidden
  child process and lets you turn it on/off from the tray icon. No administrator rights.

.DESCRIPTION
  Tray menu: enable/disable automatic switching, sync now, apply a profile manually, open the log, exit.
  The on/off state is remembered in %LOCALAPPDATA%\TclAutoRes\tray-state.json.
  Start it at sign-in with tools\Install-Autostart.ps1. Normally it runs inside TclAutoRes.exe
  (src\TclAutoResLauncher.cs), so Windows lists the icon as "TclAutoRes".

.EXAMPLE
  .\TclAutoRes.exe
  powershell -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File .\TclAutoResTray.ps1
#>
[CmdletBinding()]
param([string]$Config = '')

$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'config\config.json' }
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Import-Module (Join-Path $PSScriptRoot 'src\TclAutoRes.psm1') -Force -DisableNameChecking -Verbose:$false

$trayMutex = New-Object System.Threading.Mutex($false, 'Local\TclAutoResTray')
if (-not $trayMutex.WaitOne(0)) { exit 0 }

try { $cfg = Read-TarConfig -Path $Config }
catch { [System.Windows.Forms.MessageBox]::Show("TclAutoRes: $($_.Exception.Message)", 'TclAutoRes') | Out-Null; exit 1 }

$watcher = Join-Path $PSScriptRoot 'TclAutoRes.ps1'
$psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$stateDir = Join-Path $env:LOCALAPPDATA 'TclAutoRes'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile = Join-Path $stateDir 'tray-state.json'

function Get-TrayEnabled {
    try { return [bool]((Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).enabled) } catch { return $true }
}
function Set-TrayEnabled([bool]$Value) {
    try { (@{ enabled = $Value } | ConvertTo-Json) | Set-Content -LiteralPath $stateFile -Encoding UTF8 } catch { }
}

function New-DotIcon([System.Drawing.Color]$Color) {
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 40, 40, 40))), 2, 6, 28, 18)   # screen
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $Color), 5, 9, 22, 12)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 40, 40, 40))), 12, 25, 8, 3)   # stand
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}
$iconOn = New-DotIcon ([System.Drawing.Color]::FromArgb(255, 46, 160, 67))
$iconOff = New-DotIcon ([System.Drawing.Color]::FromArgb(255, 140, 140, 140))
$iconWarn = New-DotIcon ([System.Drawing.Color]::FromArgb(255, 210, 150, 30))

$script:child = $null
$script:lastStart = [datetime]::MinValue
$script:quickExits = 0
$script:suppressSave = $false

function Start-Hidden([string]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$watcher`" -Config `"$Config`" $Arguments"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    return [System.Diagnostics.Process]::Start($psi)
}

function Start-Watcher {
    if ($script:child -and -not $script:child.HasExited) { return }
    $script:child = Start-Hidden ''
    $script:lastStart = Get-Date
}

function Stop-Watcher {
    if ($script:child -and -not $script:child.HasExited) {
        # /T also ends the adb logcat child process.
        & "$env:SystemRoot\System32\taskkill.exe" /PID $script:child.Id /T /F 2>&1 | Out-Null
    }
    $script:child = $null
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$itemEnabled = New-Object System.Windows.Forms.ToolStripMenuItem '自動切替 ON (Auto switching)'
$itemEnabled.CheckOnClick = $true
$itemSync = New-Object System.Windows.Forms.ToolStripMenuItem '今すぐ TV に合わせる (Sync now)'
$itemManual = New-Object System.Windows.Forms.ToolStripMenuItem '手動で切替 (Apply profile)'
foreach ($k in ($cfg.Profiles.Keys | Sort-Object)) {
    $p = $cfg.Profiles[$k]
    $mi = New-Object System.Windows.Forms.ToolStripMenuItem ("{0}: {1}x{2} @{3}Hz" -f $p.Label, $p.Width, $p.Height, $p.Refresh)
    $mi.Tag = [int]$k
    $mi.add_Click({ param($s, $e) Start-Hidden ("-Apply {0}" -f [int]$s.Tag) | Out-Null })
    [void]$itemManual.DropDownItems.Add($mi)
}
$itemLog = New-Object System.Windows.Forms.ToolStripMenuItem 'ログを開く (Open log)'
$itemExit = New-Object System.Windows.Forms.ToolStripMenuItem '終了 (Exit)'
[void]$menu.Items.Add($itemEnabled)
[void]$menu.Items.Add($itemSync)
[void]$menu.Items.Add($itemManual)
[void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
[void]$menu.Items.Add($itemLog)
[void]$menu.Items.Add($itemExit)
$tray.ContextMenuStrip = $menu

function Update-Tray {
    $running = ($script:child -and -not $script:child.HasExited)
    if (-not $itemEnabled.Checked) { $tray.Icon = $iconOff; $tray.Text = 'TclAutoRes: OFF' }
    elseif ($running) { $tray.Icon = $iconOn; $tray.Text = 'TclAutoRes: ON' }
    else { $tray.Icon = $iconWarn; $tray.Text = 'TclAutoRes: ON (restarting)' }
}

$itemEnabled.add_CheckedChanged({
    if (-not $script:suppressSave) { Set-TrayEnabled $itemEnabled.Checked }
    if ($itemEnabled.Checked) { $script:quickExits = 0; Start-Watcher } else { Stop-Watcher }
    Update-Tray
})
$itemSync.add_Click({ Start-Hidden '-Once' | Out-Null })
$openLog = {
    if (Test-Path -LiteralPath $cfg.LogFile) { Start-Process -FilePath "$env:SystemRoot\System32\notepad.exe" -ArgumentList "`"$($cfg.LogFile)`"" }
    else { $tray.ShowBalloonTip(3000, 'TclAutoRes', 'No log yet.', [System.Windows.Forms.ToolTipIcon]::Info) }
}
$itemLog.add_Click($openLog)
$tray.add_DoubleClick($openLog)
$itemExit.add_Click({
    $timer.Stop()
    Stop-Watcher
    $tray.Visible = $false
    [System.Windows.Forms.Application]::Exit()
})

# Watchdog: restart the watcher if it ends while enabled (TV off, adb restart, crash).
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 5000
$timer.add_Tick({
    if ($script:child -and -not $script:child.HasExited -and ((Get-Date) - $script:lastStart).TotalSeconds -gt 60) { $script:quickExits = 0 }
    if ($itemEnabled.Checked -and -not ($script:child -and -not $script:child.HasExited)) {
        $age = ((Get-Date) - $script:lastStart).TotalSeconds
        if ($age -lt 20) { $script:quickExits++ }
        if ($script:quickExits -ge 3) {
            # Turn off for this session only; the saved ON/OFF choice is kept for the next start.
            $script:suppressSave = $true; $itemEnabled.Checked = $false; $script:suppressSave = $false
            $tray.ShowBalloonTip(8000, 'TclAutoRes', 'The watcher keeps stopping (another instance running, or a config error). Turned OFF - see the log.', [System.Windows.Forms.ToolTipIcon]::Warning)
        } elseif ($age -ge 30) {
            Start-Watcher
        }
    }
    Update-Tray
})

$itemEnabled.Checked = (Get-TrayEnabled)   # fires CheckedChanged -> starts the watcher when ON
if ($itemEnabled.Checked -and -not $script:child) { Start-Watcher }
Update-Tray
$tray.Visible = $true
$timer.Start()
try { [System.Windows.Forms.Application]::Run() }
finally {
    Stop-Watcher
    $tray.Visible = $false
    $tray.Dispose()
    $trayMutex.ReleaseMutex()
}
