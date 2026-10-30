<#
.SYNOPSIS
  Checks the whole chain without changing anything: config, adb, TV connection, ratio log events,
  the TV's Windows display and whether every profile's mode is available.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Setup.ps1
#>
[CmdletBinding()]
param([string]$Config = '')

$ErrorActionPreference = 'Stop'
if (-not $Config) { $Config = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\config.json' }
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\TclAutoRes.psm1') -Force -DisableNameChecking -Verbose:$false

$ok = $true
function Report([bool]$Pass, [string]$Text) {
    if ($Pass) { Write-Host "[OK] $Text" } else { Write-Host "[NG] $Text"; $script:ok = $false }
}

Write-Host "PowerShell $($PSVersionTable.PSVersion)"
try { $cfg = Read-TarConfig -Path $Config; Report $true "config: $Config" }
catch { Report $false "config: $($_.Exception.Message)"; exit 1 }

try { $adb = Resolve-TarAdb -Configured $cfg.AdbPath; Report $true "adb: $adb" }
catch { Report $false $_.Exception.Message; exit 1 }

$connected = Connect-TarTv -Config $cfg -Adb $adb
Report $connected "adb connection to $($cfg.Serial)"
if ($connected) {
    $props = Invoke-TarAdb -Adb $adb -Arguments @('-s', $cfg.Serial, 'shell', 'getprop ro.product.model; getprop ro.product.clientType; getprop ro.hardware; getprop ro.build.version.release; getprop ro.build.version.incremental')
    $p = @($props.Out -split "`r?`n" | Where-Object { $_ })
    Write-Host ("     TV: model={0} client={1} hw={2} android={3} build={4}" -f $p[0], $p[1], $p[2], $p[3], $p[4])
    $gb = Invoke-TarAdb -Adb $adb -Arguments @('-s', $cfg.Serial, 'shell', 'dumpsys package com.tcl.gamebar | grep -m1 versionName')
    Write-Host "     Game Bar: $($gb.Out.Trim())"

    $e = Get-TarLastTvRatio -Config $cfg -Adb $adb
    if ($e) { Report $true "last ratio event in the TV log: ratio=$($e.Ratio) port=$($e.Port) ($($e.Detector))" }
    else { Write-Host '[--] no ratio event in the TV log buffer yet (change the ratio once on the TV and run again)' }

    if ($cfg.Verify) {
        $cols = @(Get-TarHdmiRx -Config $cfg -Adb $adb)
        Report ($cols.Count -gt 0) "verify node readable ($($cfg.Verify.Path))"
        foreach ($c in $cols) { if ($c.Stable -eq 1) { Write-Host ("     HDMI rx column {0}: {1}x{2} {3:N2} Hz stable" -f $c.Column, $c.Width, $c.Height, ($c.RefreshMilliHz / 1000.0)) } }
    }
}

$dev = Find-TarTvDisplay -MonitorId $cfg.MonitorId
Report ([bool]$dev) "Windows display for monitorId '$($cfg.MonitorId)': $dev"
if ($dev) {
    $cur = Get-TarCurrentMode -Device $dev
    Write-Host ("     current mode: {0}x{1}@{2}" -f $cur.Width, $cur.Height, $cur.Refresh)
    $modes = [TarDisplay]::Modes($dev)
    foreach ($k in ($cfg.Profiles.Keys | Sort-Object)) {
        $pr = $cfg.Profiles[$k]
        $found = @($modes | Where-Object { $_ -match '^(\d+)x(\d+)@(\d+)$' -and [int]$Matches[1] -eq $pr.Width -and [int]$Matches[2] -eq $pr.Height -and [math]::Abs([int]$Matches[3] - $pr.Refresh) -le $cfg.RefreshTol })
        $text = "profile {0} [{1}] {2}x{3}@{4}" -f $k, $pr.Label, $pr.Width, $pr.Height, $pr.Refresh
        if ($found.Count -gt 0) { Write-Host "[OK] $text available in Windows ($($found -join ', '))" }
        else { Write-Host "[--] $text not offered by Windows right now (normal if the TV is in another ratio; otherwise create a custom resolution)" }
    }
}

if ($ok) { Write-Host 'RESULT=OK' } else { Write-Host 'RESULT=CHECK_NG_LINES' }
