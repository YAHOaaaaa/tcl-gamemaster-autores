<#
.SYNOPSIS
  Helps port TclAutoRes to another TCL TV. Records the TV's log while you change the Game Bar
  "screen ratio", finds the lines that report the change and writes a report (Markdown) with a
  suggested config. Read-only on the TV: it only reads logs, properties and config files.

.DESCRIPTION
  1. Connects to the TV with adb (you accept the "Allow debugging?" prompt on the TV yourself).
  2. Optionally opens the Game Bar (-OpenGameBar; works on Game Bar 3.x).
  3. Records the log for -Seconds while YOU change the ratio on the TV: 16:9 -> 21:9 -> 32:9 -> 16:9.
  4. Writes discover-output\report-<time>.md and the raw log next to it (both git-ignored).
  Review the report before sharing it: IP/MAC-like strings are masked, but check anyway.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Discover-TvSignals.ps1 -Address 192.168.0.50:5555 -OpenGameBar
#>
[CmdletBinding()]
param(
    [string]$Address = '',
    [string]$Serial = '',
    [string]$AdbPath = '',
    [ValidateRange(20, 600)][int]$Seconds = 90,
    [switch]$OpenGameBar,
    [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'discover-output' }
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'src\TclAutoRes.psm1') -Force -DisableNameChecking -Verbose:$false

if ($Address -and $Address -notmatch '^[A-Za-z0-9.\-]{1,253}:[0-9]{1,5}$') { throw "invalid -Address '$Address' (expected host:port)" }
if ($Serial -and $Serial -notmatch '^[A-Za-z0-9._:\-]{1,64}$') { throw "invalid -Serial '$Serial'" }
if (-not $Serial) { $Serial = $Address }
if (-not $Serial) { throw 'give -Address <tv-ip>:5555 (or -Serial for USB)' }

$adb = Resolve-TarAdb -Configured $AdbPath
$cfg = [pscustomobject]@{ Address = $Address; Serial = $Serial }
if (-not (Connect-TarTv -Config $cfg -Adb $adb)) { throw 'TV not connected. Enable network debugging on the TV, accept the prompt, then retry.' }

function Sh([string]$Cmd, [int]$T = 30) { (Invoke-TarAdb -Adb $adb -Arguments @('-s', $Serial, 'shell', $Cmd) -TimeoutSec $T).Out }
function Mask([string]$s) {
    $s = [regex]::Replace($s, '\b(\d{1,3}\.){3}\d{1,3}\b', '<ip>')
    $s = [regex]::Replace($s, '\b([0-9A-Fa-f]{2}[:\-]){5}[0-9A-Fa-f]{2}\b', '<mac>')
    return $s
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rawFile = Join-Path $OutDir "logcat-$stamp.txt"
$report = Join-Path $OutDir "report-$stamp.md"

# Only allow-listed properties (no serial numbers).
$propNames = 'ro.product.model', 'ro.product.brand', 'ro.product.clientType', 'ro.hardware', 'ro.hardware.version_id', 'ro.build.version.release', 'ro.build.version.incremental', 'ro.odm.tcl.panel_resolution'
$props = [ordered]@{}
foreach ($n in $propNames) { $props[$n] = (Sh "getprop $n").Trim() }
$gamebar = ((Sh 'dumpsys package com.tcl.gamebar | grep -m1 versionName') -replace '\s+', ' ').Trim()

if ($OpenGameBar) { Sh 'am start -a com.tcl.gamebar.main' | Out-Null }

Write-Host ''
Write-Host "Recording for $Seconds s. On the TV, open Game Bar > Menu > Screen ratio and change it:"
Write-Host '   16:9 -> 21:9 -> 32:9 -> 16:9   (wait about 5 seconds after each change)'
Write-Host ''
$p = Start-Process -FilePath $adb -ArgumentList @('-s', $Serial, 'logcat', '-v', 'brief', '-T', '1') -RedirectStandardOutput $rawFile -NoNewWindow -PassThru
for ($i = $Seconds; $i -gt 0; $i -= 5) { Write-Host "  $i s left"; Start-Sleep -Seconds ([math]::Min(5, $i)) }
try { Stop-Process -Id $p.Id -Force } catch { }
Start-Sleep -Milliseconds 500

# ---- analyse
$keyword = '(?i)(wide.?screen|screen.?ratio|aspect.?ratio|display_ratio|zoom|edid|SetWinRegion|setOption)'
$noise = '(?i)(depop|duration=|Davey|uiautomator)'
$templates = @{}
foreach ($line in (Get-Content -LiteralPath $rawFile -Encoding UTF8)) {
    if ($line -notmatch $keyword -or $line -match $noise) { continue }
    $msg = $line -replace '^[VDIWEF]/', ''
    $tpl = [regex]::Replace(($msg -replace '\(\s*\d+\)', '(pid)'), '\d+', '#')
    if (-not $templates.ContainsKey($tpl)) { $templates[$tpl] = [pscustomobject]@{ Hits = 0; Example = $line; Values = New-Object System.Collections.Generic.List[string] } }
    $t = $templates[$tpl]; $t.Hits++
    if ($t.Values.Count -lt 12) { $t.Values.Add(($line -replace '^.*?:\s*', '')) }
}
$top = $templates.GetEnumerator() | Sort-Object { $_.Value.Hits } -Descending | Select-Object -First 40

# Known patterns (TCL MediaTek, Game Bar 3.x)
$known = @(
    @{ Tag = 'sita.thal'; Regex = 'fpi_edid_set_wide_screen_mode, port: (?<port>\d+), display_ratio: (?<ratio>\d+)' },
    @{ Tag = 'VIDEOFUNC'; Regex = 'setWideScreenRatio,\d+\].*wideScreenRatio is \[(?<ratio>\d+)\]' }
)
$found = @()
$rawText = Get-Content -LiteralPath $rawFile -Raw -Encoding UTF8
foreach ($k in $known) { if ($rawText -match $k.Regex) { $found += $k } }

# Wide-screen timings the TV advertises (TCL keeps them in /tclconfig/.../edid/*.ini, "ZOOM" section)
$zoom = Sh "grep -r -E '(Refresh|H_ACTIVE_PIXELS|V_ACTIVE_Lines)_[0-9]+' /tclconfig 2>/dev/null | head -400" 60
$timings = @{}
foreach ($l in ($zoom -split "`r?`n")) {
    if ($l -match '^(?<f>[^:]+):\s*"?(?<k>Refresh|H_ACTIVE_PIXELS|V_ACTIVE_Lines)_(?<i>\d+)"?\s*[:=]\s*(?<v>\d+)') {
        $id = $Matches['f'] + '#' + $Matches['i']
        if (-not $timings.ContainsKey($id)) { $timings[$id] = @{} }
        $timings[$id][$Matches['k']] = [int]$Matches['v']
    }
}
$timingSet = $timings.Values | ForEach-Object { '{0}x{1} @ {2:N3} Hz' -f $_['H_ACTIVE_PIXELS'], $_['V_ACTIVE_Lines'], ($_['Refresh'] / 1000.0) } | Sort-Object -Unique
$mtk = (Sh 'ls /sys/devices/platform/mtk_srccap0/mtk_dbg/hdmirx/HDMI_INFO 2>/dev/null').Trim()

# ---- report
$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("# TclAutoRes discovery report ($stamp)")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## TV')
foreach ($k in $props.Keys) { [void]$sb.AppendLine("- $k = $($props[$k])") }
[void]$sb.AppendLine("- Game Bar: $gamebar")
[void]$sb.AppendLine("- MediaTek HDMI_INFO node: $(if ($mtk) { 'present (verify can be enabled)' } else { 'not found (set verify.enabled = false)' })")
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Known ratio patterns found')
if ($found.Count) { foreach ($k in $found) { [void]$sb.AppendLine("- tag ``$($k.Tag)``: ``$($k.Regex)``") } }
else { [void]$sb.AppendLine('- none. Use the candidate lines below to write a detector (see docs/porting.md).') }
[void]$sb.AppendLine('')
if ($found.Count) {
    [void]$sb.AppendLine('### Suggested config.json "tv" section')
    [void]$sb.AppendLine('```json')
    $tags = ($found | ForEach-Object { '"' + $_.Tag + '"' }) -join ', '
    $dets = ($found | ForEach-Object { '      { "name": "' + $_.Tag + '", "regex": "' + ($_.Regex -replace '\\', '\\') + '" }' }) -join ",`n"
    [void]$sb.AppendLine("  `"tv`": {`n    `"logTags`": [$tags],`n    `"detectors`": [`n$dets`n    ],`n    `"hdmiPort`": null`n  }")
    [void]$sb.AppendLine('```')
    [void]$sb.AppendLine('')
}
[void]$sb.AppendLine('## Wide-screen timings in the TV config (ZOOM)')
if ($timingSet) { foreach ($t in $timingSet) { [void]$sb.AppendLine("- $t") } } else { [void]$sb.AppendLine('- not found') }
[void]$sb.AppendLine('')
[void]$sb.AppendLine('## Candidate log lines (numbers replaced by #, most frequent first)')
foreach ($e in $top) {
    [void]$sb.AppendLine("- x$($e.Value.Hits): ``$(Mask $e.Key)``")
    [void]$sb.AppendLine("  - values seen: $(Mask (($e.Value.Values | Select-Object -Unique) -join ' | '))")
}
Set-Content -LiteralPath $report -Value $sb.ToString() -Encoding UTF8
Write-Host ''
Write-Host "Report: $report"
Write-Host "Raw log: $rawFile  (contains device details; do not publish it)"
