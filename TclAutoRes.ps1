<#
.SYNOPSIS
  Watches a TCL Google TV (Game Master / Game Bar) over adb and switches the PC's output mode
  when the TV's "screen ratio" (16:9 / 21:9 / 32:9) changes.

.DESCRIPTION
  Runs as the normal user (no administrator rights). Read README.md, DISCLAIMER.md and SECURITY.md first.

.PARAMETER Config
  Path to config.json (default: config\config.json next to this script).
.PARAMETER Apply
  Apply the profile for this ratio number once and exit (e.g. -Apply 1). Useful for testing.
.PARAMETER Once
  Read the TV's current ratio from its log buffer, apply it once and exit.
.PARAMETER ListDisplays
  Print the displays Windows sees and the TV's available modes, then exit.
.PARAMETER DryRun
  Log what would be changed without changing any display mode.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\TclAutoRes.ps1 -ListDisplays
#>
[CmdletBinding()]
param(
    [string]$Config = '',
    [int]$Apply = -1,
    [switch]$Once,
    [switch]$ListDisplays,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 leaves $PSScriptRoot empty inside param() defaults, so resolve defaults here.
if (-not $Config) { $Config = Join-Path $PSScriptRoot 'config\config.json' }
Import-Module (Join-Path $PSScriptRoot 'src\TclAutoRes.psm1') -Force -DisableNameChecking -Verbose:$false

$cfg = Read-TarConfig -Path $Config
Initialize-TarLog -Path $cfg.LogFile -ShowDebug:($VerbosePreference -eq 'Continue')

# ------------------------------------------------------------------ list mode
if ($ListDisplays) {
    Initialize-TarDisplayType
    Write-Host 'Displays attached to the desktop (device | monitor id | primary):'
    foreach ($m in [TarDisplay]::Monitors()) { Write-Host "  $m" }
    $dev = Find-TarTvDisplay -MonitorId $cfg.MonitorId
    if (-not $dev) { Write-Host "No display matches monitorId '$($cfg.MonitorId)'. Set display.monitorId in config.json."; exit 1 }
    Write-Host "TV display: $dev  current: $((Get-TarCurrentMode -Device $dev | ForEach-Object { '{0}x{1}@{2}' -f $_.Width, $_.Height, $_.Refresh }))"
    Write-Host 'Modes Windows offers for the TV:'
    [TarDisplay]::Modes($dev) | Sort-Object { [int](($_ -split '[x@]')[0]) }, { [int](($_ -split '[x@]')[1]) }, { [int](($_ -split '[x@]')[2]) } | ForEach-Object { Write-Host "  $_" }
    exit 0
}

$adb = Resolve-TarAdb -Configured $cfg.AdbPath

# ------------------------------------------------------------------ apply one profile
function Invoke-Profile {
    param([int]$Ratio, [string]$Reason)
    try { return (Invoke-ProfileCore -Ratio $Ratio -Reason $Reason) }
    catch { Write-TarLog "ratio $Ratio ($Reason): $($_.Exception.Message)" 'ERROR'; return 'error' }
}

function Invoke-ProfileCore {
    param([int]$Ratio, [string]$Reason)
    if (-not $cfg.Profiles.ContainsKey($Ratio)) { Write-TarLog "ratio $Ratio ($Reason): no profile configured, nothing to do"; return 'noprofile' }
    $p = $cfg.Profiles[$Ratio]

    # The TV re-sends hot-plug when the ratio changes, so the display can be missing for a moment.
    $dev = $null
    for ($i = 0; $i -lt 10 -and -not $dev; $i++) {
        $dev = Find-TarTvDisplay -MonitorId $cfg.MonitorId
        if (-not $dev) { Start-Sleep -Milliseconds 700 }
    }
    if (-not $dev) { Write-TarLog "ratio $Ratio ($Reason): TV display '$($cfg.MonitorId)' not found" 'WARN'; return 'nodisplay' }

    $res = 'failed'
    for ($i = 0; $i -lt 3; $i++) {
        $res = Set-TarDisplayMode -Device $dev -Width $p.Width -Height $p.Height -Refresh $p.Refresh -Tolerance $cfg.RefreshTol -Persist $cfg.Persist -DryRun:$DryRun
        if ($res -notlike 'failed*') { break }
        Start-Sleep -Milliseconds 800
    }
    Write-TarLog ("ratio {0} [{1}] ({2}): {3}x{4}@{5} -> {6}" -f $Ratio, $p.Label, $Reason, $p.Width, $p.Height, $p.Refresh, $res)
    if ($res -eq 'nomode') {
        Write-TarLog "Windows does not list $($p.Width)x$($p.Height)@$($p.Refresh) for the TV. Create it as a custom resolution (GPU control panel) - see docs/setup.md" 'WARN'
    }

    $needFallback = ($res -eq 'nomode' -or $res -like 'failed*')
    if ($res -eq 'ok' -and $cfg.Verify -and -not $DryRun) {
        if (Test-TarSignal -Config $cfg -Adb $adb -Width $p.Width -Height $p.Height -Refresh $p.Refresh) {
            Write-TarLog 'verify: TV receives the new mode (stable)'
        } else {
            Write-TarLog 'verify: TV does not show a stable signal in the new mode' 'WARN'
            $needFallback = $true
        }
    }
    if ($needFallback -and $p.Fallback -and -not $DryRun) {
        $fb = $p.Fallback
        $r2 = Set-TarDisplayMode -Device $dev -Width $fb.Width -Height $fb.Height -Refresh $fb.Refresh -Tolerance $cfg.RefreshTol -Persist $cfg.Persist
        Write-TarLog ("fallback {0}x{1}@{2} -> {3}" -f $fb.Width, $fb.Height, $fb.Refresh, $r2) 'WARN'
        return 'fallback'
    }
    return $res
}

if ($Apply -ge 0) {
    $r = Invoke-Profile -Ratio $Apply -Reason 'manual'
    if ($r -in @('ok', 'already') -or $r -like 'dryrun*') { exit 0 } else { exit 1 }
}

if ($Once) {
    if (-not (Connect-TarTv -Config $cfg -Adb $adb)) { exit 1 }
    $e = Get-TarLastTvRatio -Config $cfg -Adb $adb
    if (-not $e) { Write-TarLog 'no ratio event in the TV log buffer (change the ratio once on the TV, then retry)' 'WARN'; exit 1 }
    Invoke-Profile -Ratio $e.Ratio -Reason "last log ($($e.Detector))" | Out-Null
    exit 0
}

# ------------------------------------------------------------------ resident watcher
$mutex = New-Object System.Threading.Mutex($false, 'Local\TclAutoRes')
if (-not $mutex.WaitOne(0)) { Write-TarLog 'another TclAutoRes instance is already running; exiting' 'WARN'; exit 0 }

Write-TarLog ("TclAutoRes started (tv={0}, monitor={1}, profiles={2}{3})" -f $cfg.Serial, $cfg.MonitorId, (($cfg.Profiles.Keys | Sort-Object) -join ','), $(if ($DryRun) { ', DRY RUN' } else { '' }))
$firstConnect = $true
try {
    while ($true) {
        if (-not (Connect-TarTv -Config $cfg -Adb $adb)) { Start-Sleep -Seconds 15; continue }

        if ($firstConnect -and $cfg.SyncOnStart) {
            try {
                $e = Get-TarLastTvRatio -Config $cfg -Adb $adb
                if ($e) { Invoke-Profile -Ratio $e.Ratio -Reason 'start-up sync' | Out-Null }
                else { Write-TarLog 'start-up sync: no ratio event in the TV log buffer; waiting for the next change' }
            } catch { Write-TarLog "start-up sync failed: $($_.Exception.Message)" 'WARN' }
        }
        $firstConnect = $false

        # Stream only the configured tags; "-T 1" starts at the newest line (that one old line is skipped).
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $adb
        $psi.Arguments = (@('-s', $cfg.Serial, 'logcat', '-v', 'brief', '-T', '1') + ($cfg.LogTags | ForEach-Object { "${_}:I" }) + @('*:S')) -join ' '
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $proc = [System.Diagnostics.Process]::Start($psi)
        $null = $proc.StandardError.ReadToEndAsync()
        Write-TarLog 'watching the TV log for ratio changes'

        $skipFirst = $true
        $pending = $null
        $recheck = $null
        while ($true) {
            $task = $proc.StandardOutput.ReadLineAsync()
            while (-not $task.Wait(250)) {
                $now = Get-Date
                if ($pending -and ($now - $pending.At).TotalMilliseconds -ge $cfg.SettleMs) {
                    $ratio = $pending.Ratio; $pending = $null
                    $res = Invoke-Profile -Ratio $ratio -Reason 'tv change'
                    if ($res -eq 'ok') { $recheck = [pscustomobject]@{ Ratio = $ratio; At = (Get-Date).AddMilliseconds($cfg.RecheckMs) } }
                }
                if ($recheck -and $now -ge $recheck.At) {
                    # Windows sometimes re-applies its own preferred mode after the TV's hot-plug; correct it once.
                    $ratio = $recheck.Ratio; $recheck = $null
                    $p = $cfg.Profiles[$ratio]
                    $dev = Find-TarTvDisplay -MonitorId $cfg.MonitorId
                    if ($dev) {
                        $cur = Get-TarCurrentMode -Device $dev
                        if ($cur -and -not ($cur.Width -eq $p.Width -and $cur.Height -eq $p.Height -and [math]::Abs($cur.Refresh - $p.Refresh) -le $cfg.RefreshTol)) {
                            Write-TarLog ("recheck: mode drifted to {0}x{1}@{2}; applying again" -f $cur.Width, $cur.Height, $cur.Refresh) 'WARN'
                            Invoke-Profile -Ratio $ratio -Reason 'recheck' | Out-Null
                        }
                    }
                }
            }
            $line = $task.Result
            if ($null -eq $line) { break }          # adb ended (TV off, network lost)
            if ($skipFirst) { $skipFirst = $false; continue }
            $e = Get-TarTvRatioEvent -Config $cfg -Line $line
            if ($e) {
                Write-TarLog ("tv: ratio {0} (port {1}, {2})" -f $e.Ratio, $(if ($null -ne $e.Port) { $e.Port } else { '-' }), $e.Detector) 'DEBUG'
                $pending = [pscustomobject]@{ Ratio = $e.Ratio; At = Get-Date }
                $recheck = $null
            }
        }
        try { if (-not $proc.HasExited) { $proc.Kill() } } catch { }
        Write-TarLog 'adb log stream ended; reconnecting in 10 s' 'WARN'
        Start-Sleep -Seconds 10
    }
} finally {
    $mutex.ReleaseMutex()
}
