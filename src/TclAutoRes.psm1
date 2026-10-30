# TclAutoRes core module.
# Windows PowerShell 5.1 compatible. Needs no administrator rights.
#
# What it does:
#   - reads a JSON config and validates every value that reaches a command line
#   - runs adb (Android platform-tools) against the TV
#   - finds the TV's Windows display and changes its mode (resolution / refresh rate)
#   - optionally verifies the TV actually receives the new signal (MediaTek debug node) and falls back if not
#
# Security notes (see SECURITY.md):
#   - Nothing read from the TV is ever executed. Log lines are only matched with local regexes and
#     the captured value must be a small integer that maps to a profile in the config.
#   - Only validated tokens are passed to adb; no free text from the config goes into "adb shell".

Set-StrictMode -Version 2.0

$script:LogFile = $null
$script:LogMaxBytes = 1MB
$script:ShowDebug = $false

# ---------------------------------------------------------------- logging

function Initialize-TarLog {
    param([string]$Path, [switch]$ShowDebug)
    $script:ShowDebug = [bool]$ShowDebug
    if (-not $Path) { return }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:LogFile = $Path
}

function Write-TarLog {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')][string]$Level = 'INFO')
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($Level -eq 'DEBUG' -and -not $script:ShowDebug) { return }
    Write-Host $line
    if ($script:LogFile) {
        try {
            if ((Test-Path -LiteralPath $script:LogFile) -and (Get-Item -LiteralPath $script:LogFile).Length -gt $script:LogMaxBytes) {
                Move-Item -LiteralPath $script:LogFile -Destination ($script:LogFile + '.1') -Force
            }
            Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
        } catch { }
    }
}

# ---------------------------------------------------------------- config

$script:ReAddress = '^[A-Za-z0-9.\-]{1,253}:[0-9]{1,5}$'      # host:port for adb over network
$script:ReSerial = '^[A-Za-z0-9._:\-]{1,64}$'                  # adb serial (USB or host:port)
$script:ReTag = '^[A-Za-z0-9_.\-]{1,64}$'                      # logcat tag
$script:ReSysPath = '^/sys/[A-Za-z0-9_./\-]{1,200}$'           # read-only debug node on the TV
$script:ReMonitor = '^[A-Za-z0-9]{3,16}$'                      # PnP monitor id or prefix (e.g. TOL or TOL9653)

function Get-TarProp {
    # Returns a property of a PSCustomObject or a default when missing (StrictMode-safe).
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function Assert-TarMatch {
    param([string]$Value, [string]$Pattern, [string]$What)
    if ($Value -notmatch $Pattern) { throw "config: invalid $What '$Value'" }
}

function Read-TarConfig {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "config file not found: $Path (copy config\config.example.json to config\config.json)" }
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $c = $raw | ConvertFrom-Json

    $adb = Get-TarProp $c 'adb'
    $cfg = [ordered]@{
        AdbPath        = [string](Get-TarProp $adb 'path' '')
        Address        = [string](Get-TarProp $adb 'address' '')
        Serial         = [string](Get-TarProp $adb 'serial' '')
        LogTags        = @()
        Detectors      = @()
        HdmiPort       = $null
        MonitorId      = 'TOL'
        Profiles       = @{}
        SettleMs       = 2500
        RecheckMs      = 4000
        RefreshTol     = 1.0
        Persist        = $true
        SyncOnStart    = $true
        Verify         = $null
        LogFile        = ''
    }

    if ($cfg.Address) { Assert-TarMatch $cfg.Address $script:ReAddress 'adb.address (expected host:port)' }
    if ($cfg.Serial) { Assert-TarMatch $cfg.Serial $script:ReSerial 'adb.serial' }
    if (-not $cfg.Serial) { $cfg.Serial = $cfg.Address }
    if (-not $cfg.Serial) { throw 'config: set adb.address (e.g. 192.168.0.50:5555) or adb.serial' }

    $tv = Get-TarProp $c 'tv'
    foreach ($t in @(Get-TarProp $tv 'logTags' @())) { Assert-TarMatch ([string]$t) $script:ReTag 'tv.logTags entry'; $cfg.LogTags += [string]$t }
    if ($cfg.LogTags.Count -eq 0) { throw 'config: tv.logTags must list at least one logcat tag' }
    $port = Get-TarProp $tv 'hdmiPort' $null
    if ($null -ne $port) { $cfg.HdmiPort = [int]$port }

    foreach ($d in @(Get-TarProp $tv 'detectors' @())) {
        $name = [string](Get-TarProp $d 'name' 'detector')
        $pattern = [string](Get-TarProp $d 'regex' '')
        if ($pattern -notmatch '\(\?<ratio>') { throw "config: detector '$name' needs a named group (?<ratio>...)" }
        # A match timeout protects against catastrophic backtracking on hostile/odd log lines.
        $re = New-Object System.Text.RegularExpressions.Regex($pattern, [System.Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromMilliseconds(200))
        $cfg.Detectors += [pscustomobject]@{ Name = $name; Regex = $re }
    }
    if ($cfg.Detectors.Count -eq 0) { throw 'config: tv.detectors must contain at least one regex' }

    $disp = Get-TarProp $c 'display'
    $mid = [string](Get-TarProp $disp 'monitorId' 'TOL')
    Assert-TarMatch $mid $script:ReMonitor 'display.monitorId'
    $cfg.MonitorId = $mid
    $cfg.Persist = [bool](Get-TarProp $disp 'persist' $true)
    $cfg.RefreshTol = [double](Get-TarProp $disp 'refreshTolerance' 1.0)

    $profiles = Get-TarProp $c 'profiles'
    if ($null -eq $profiles) { throw 'config: profiles missing' }
    foreach ($p in $profiles.PSObject.Properties) {
        if ($p.Name -like '_*') { continue }   # "_comment" keys
        if ($p.Name -notmatch '^[0-9]{1,2}$') { throw "config: profile key '$($p.Name)' must be the ratio number reported by the TV (0, 1, 2 ...)" }
        $v = $p.Value
        $prof = [pscustomobject]@{
            Key      = [int]$p.Name
            Label    = [string](Get-TarProp $v 'label' $p.Name)
            Width    = [int](Get-TarProp $v 'width' 0)
            Height   = [int](Get-TarProp $v 'height' 0)
            Refresh  = [double](Get-TarProp $v 'refresh' 0)
            Fallback = $null
        }
        if ($prof.Width -lt 640 -or $prof.Height -lt 480 -or $prof.Refresh -lt 23) { throw "config: profile $($p.Name) has an invalid mode" }
        $fb = Get-TarProp $v 'fallback'
        if ($fb) {
            $prof.Fallback = [pscustomobject]@{
                Width = [int](Get-TarProp $fb 'width' 0); Height = [int](Get-TarProp $fb 'height' 0); Refresh = [double](Get-TarProp $fb 'refresh' 0)
            }
            if ($prof.Fallback.Width -lt 640 -or $prof.Fallback.Height -lt 480 -or $prof.Fallback.Refresh -lt 23) { throw "config: profile $($p.Name) fallback is invalid" }
        }
        $cfg.Profiles[[int]$p.Name] = $prof
    }

    $timing = Get-TarProp $c 'timing'
    $cfg.SettleMs = [int](Get-TarProp $timing 'settleMs' 2500)
    $cfg.RecheckMs = [int](Get-TarProp $timing 'recheckMs' 4000)
    $cfg.SyncOnStart = [bool](Get-TarProp $c 'syncOnStart' $true)

    $ver = Get-TarProp $c 'verify'
    if ($ver -and [bool](Get-TarProp $ver 'enabled' $false)) {
        $node = [string](Get-TarProp $ver 'hdmiInfoPath' '')
        Assert-TarMatch $node $script:ReSysPath 'verify.hdmiInfoPath'
        $cfg.Verify = [pscustomobject]@{ Path = $node; TimeoutSec = [int](Get-TarProp $ver 'timeoutSec' 10) }
    }

    $log = [string](Get-TarProp $c 'logFile' '')
    if (-not $log) { $log = Join-Path $env:LOCALAPPDATA 'TclAutoRes\tclautores.log' }
    $cfg.LogFile = [Environment]::ExpandEnvironmentVariables($log)

    return [pscustomobject]$cfg
}

# ---------------------------------------------------------------- adb

function Resolve-TarAdb {
    param([string]$Configured)
    $candidates = @()
    if ($Configured) { $candidates += [Environment]::ExpandEnvironmentVariables($Configured) }
    $cmd = Get-Command adb.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { $candidates += $cmd.Source }
    $candidates += (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
    foreach ($p in $candidates) {
        if ($p -and (Test-Path -LiteralPath $p -PathType Leaf) -and ((Split-Path -Leaf $p) -ieq 'adb.exe')) {
            return (Resolve-Path -LiteralPath $p).Path
        }
    }
    throw 'adb.exe not found. Install Android SDK Platform-Tools from developer.android.com and set adb.path in config.json'
}

function Invoke-TarAdb {
    # Runs adb with an argument array (each element already validated) and returns stdout text.
    param([Parameter(Mandatory)][string]$Adb, [Parameter(Mandatory)][string[]]$Arguments, [int]$TimeoutSec = 20)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Adb
    $psi.Arguments = ($Arguments | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"', '') + '"' } else { $_ } }) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { try { $p.Kill() } catch { }; throw "adb timed out: $($Arguments -join ' ')" }
    $p.WaitForExit()
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $outTask.Result; Err = $errTask.Result }
}

function Connect-TarTv {
    # Makes sure the TV is reachable and authorised. Returns $true when "adb get-state" says "device".
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Adb)
    if ($Config.Address) { Invoke-TarAdb -Adb $Adb -Arguments @('connect', $Config.Address) -TimeoutSec 15 | Out-Null }
    $r = Invoke-TarAdb -Adb $Adb -Arguments @('-s', $Config.Serial, 'get-state') -TimeoutSec 10
    $state = ($r.Out + $r.Err).Trim()
    if ($state -match '^device') { return $true }
    if ($state -match 'unauthorized') { Write-TarLog 'TV says unauthorized: accept the "Allow debugging?" prompt on the TV (only if you started this connection).' 'WARN' }
    else { Write-TarLog "TV not reachable via adb ($($Config.Serial)): $state" 'WARN' }
    return $false
}

function Get-TarTvRatioEvent {
    # Applies the configured detectors to one log line. Returns @{Ratio; Port; Detector} or $null.
    param([Parameter(Mandatory)]$Config, [string]$Line)
    if (-not $Line) { return $null }
    if ($Line.Length -gt 2000) { return $null }
    foreach ($d in $Config.Detectors) {
        try { $m = $d.Regex.Match($Line) } catch [System.Text.RegularExpressions.RegexMatchTimeoutException] { continue }
        if (-not $m.Success) { continue }
        $ratioText = $m.Groups['ratio'].Value
        if ($ratioText -notmatch '^[0-9]{1,2}$') { continue }
        $port = $null
        if ($m.Groups['port'].Success -and $m.Groups['port'].Value -match '^[0-9]{1,2}$') { $port = [int]$m.Groups['port'].Value }
        if ($null -ne $Config.HdmiPort -and $null -ne $port -and $port -ne $Config.HdmiPort) { return $null }
        return [pscustomobject]@{ Ratio = [int]$ratioText; Port = $port; Detector = $d.Name }
    }
    return $null
}

function Get-TarLastTvRatio {
    # Looks through the TV's current log buffer for the most recent ratio event (used at start-up).
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Adb)
    $logArgs = @('-s', $Config.Serial, 'logcat', '-d', '-v', 'brief') + ($Config.LogTags | ForEach-Object { "${_}:I" }) + @('*:S')
    $r = Invoke-TarAdb -Adb $Adb -Arguments $logArgs -TimeoutSec 40
    $last = $null
    foreach ($line in ($r.Out -split "`r?`n")) {
        $e = Get-TarTvRatioEvent -Config $Config -Line $line
        if ($e) { $last = $e }
    }
    return $last
}

function Get-TarHdmiRx {
    # Reads the MediaTek HDMI receiver debug node (read-only) and returns one object per port column.
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Adb)
    $r = Invoke-TarAdb -Adb $Adb -Arguments @('-s', $Config.Serial, 'shell', 'cat', $Config.Verify.Path) -TimeoutSec 10
    $rows = @{}
    foreach ($line in ($r.Out -split "`r?`n")) {
        if ($line -match '^(?<k>\S.*?)\s{2,}(?<v>.+)$') { $rows[$Matches['k'].Trim()] = @($Matches['v'].Trim() -split '\s+') }
    }
    $cols = @()
    if (-not $rows.ContainsKey('DE Stable')) { return $cols }
    for ($i = 0; $i -lt $rows['DE Stable'].Count; $i++) {
        $get = { param($k) if ($rows.ContainsKey($k) -and $rows[$k].Count -gt $i -and $rows[$k][$i] -match '^-?[0-9]+$') { [int64]$rows[$k][$i] } else { [int64]-1 } }
        $cols += [pscustomobject]@{
            Column = $i; Stable = (& $get 'DE Stable'); Width = (& $get 'Width'); Height = (& $get 'Height'); RefreshMilliHz = (& $get 'Refresh Rate(mHz)')
        }
    }
    return $cols
}

function Test-TarSignal {
    # True when some HDMI port reports a stable signal with the expected size and refresh rate.
    param([Parameter(Mandatory)]$Config, [Parameter(Mandatory)][string]$Adb, [int]$Width, [int]$Height, [double]$Refresh)
    # With YCbCr 4:2:0 the MediaTek receiver reports half the width (e.g. 1920 for 3840x2160@120).
    $deadline = (Get-Date).AddSeconds($Config.Verify.TimeoutSec)
    $seen = 'nothing read'
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 1000
        try { $cols = Get-TarHdmiRx -Config $Config -Adb $Adb } catch { continue }
        $active = @($cols | Where-Object { $_.Width -gt 0 })
        if ($active.Count) { $seen = ($active | ForEach-Object { 'col{0}: stable={1} {2}x{3} {4:N2}Hz' -f $_.Column, $_.Stable, $_.Width, $_.Height, ($_.RefreshMilliHz / 1000.0) }) -join '; ' }
        else { $seen = 'no active port' }
        foreach ($c in $cols) {
            $widthOk = ($c.Width -eq $Width -or ($c.Width * 2) -eq $Width)
            if ($c.Stable -eq 1 -and $widthOk -and $c.Height -eq $Height -and [math]::Abs($c.RefreshMilliHz / 1000.0 - $Refresh) -le ($Config.RefreshTol + 0.5)) { return $true }
        }
    }
    Write-TarLog "verify: last HDMI receiver state: $seen" 'WARN'
    return $false
}

# ---------------------------------------------------------------- Windows display

$script:TarTypeDef = @'
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public static class TarDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DISPLAY_DEVICE {
        public int cb;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DeviceName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceString;
        public int StateFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceID;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string DeviceKey;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
        public int dmFields;
        public int dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
        public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
        public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplayDevices(string lpDevice, uint iDevNum, ref DISPLAY_DEVICE lpDisplayDevice, uint dwFlags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern bool EnumDisplaySettingsEx(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode, int dwFlags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, uint dwflags, IntPtr lParam);

    public static DEVMODE NewMode() { DEVMODE d = new DEVMODE(); d.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE)); return d; }

    // Returns "\\.\DISPLAYn|MONITOR\XXX1234\..." for every monitor attached to the desktop.
    public static List<string> Monitors() {
        List<string> r = new List<string>();
        for (uint i = 0; i < 32; i++) {
            DISPLAY_DEVICE a = new DISPLAY_DEVICE(); a.cb = Marshal.SizeOf(a);
            if (!EnumDisplayDevices(null, i, ref a, 0)) break;
            if ((a.StateFlags & 1) == 0) continue; // DISPLAY_DEVICE_ATTACHED_TO_DESKTOP
            for (uint j = 0; j < 8; j++) {
                DISPLAY_DEVICE m = new DISPLAY_DEVICE(); m.cb = Marshal.SizeOf(m);
                if (!EnumDisplayDevices(a.DeviceName, j, ref m, 0)) break;
                r.Add(a.DeviceName + "|" + m.DeviceID + "|" + ((a.StateFlags & 4) != 0 ? "primary" : ""));
            }
        }
        return r;
    }

    public static List<string> Modes(string dev) { return Modes(dev, false); }

    // raw = EDS_RAWMODE: also the modes the monitor's current EDID does not cover, e.g. a custom resolution made
    // for another TV ratio while a Windows EDID override is active.
    public static List<string> Modes(string dev, bool raw) {
        List<string> r = new List<string>();
        DEVMODE d = NewMode();
        for (int i = 0; EnumDisplaySettingsEx(dev, i, ref d, raw ? 2 : 0); i++) {
            string s = d.dmPelsWidth + "x" + d.dmPelsHeight + "@" + d.dmDisplayFrequency;
            if (!r.Contains(s)) r.Add(s);
            d = NewMode();
        }
        return r;
    }
}
'@

function Initialize-TarDisplayType {
    if (-not ('TarDisplay' -as [type])) { Add-Type -TypeDefinition $script:TarTypeDef -ErrorAction Stop }
}

function Find-TarTvDisplay {
    # Returns the GDI device name (\\.\DISPLAYn) of the TV. MonitorId may be a full PnP id (TOL9653) or a prefix (TOL).
    param([Parameter(Mandatory)][string]$MonitorId)
    Initialize-TarDisplayType
    $hits = @()
    foreach ($entry in [TarDisplay]::Monitors()) {
        $parts = $entry -split '\|'
        if ($parts[1] -match ('^MONITOR\\' + [regex]::Escape($MonitorId) + '[A-Za-z0-9]*\\')) { $hits += $parts[0] }
    }
    $hits = @($hits | Select-Object -Unique)
    if ($hits.Count -eq 1) { return $hits[0] }
    if ($hits.Count -gt 1) { throw "more than one display matches monitorId '$MonitorId' ($($hits -join ', ')); set the full id, e.g. TOL9653" }
    return $null
}

function Get-TarCurrentMode {
    param([Parameter(Mandatory)][string]$Device)
    Initialize-TarDisplayType
    $d = [TarDisplay]::NewMode()
    if (-not [TarDisplay]::EnumDisplaySettingsEx($Device, -1, [ref]$d, 0)) { return $null }
    return [pscustomobject]@{ Width = $d.dmPelsWidth; Height = $d.dmPelsHeight; Refresh = $d.dmDisplayFrequency }
}

function Set-TarDisplayMode {
    # Changes the mode of one display. Returns 'already', 'ok', 'nomode' or 'failed:<code>'.
    param([Parameter(Mandatory)][string]$Device, [int]$Width, [int]$Height, [double]$Refresh, [double]$Tolerance = 1.0, [bool]$Persist = $true, [switch]$DryRun)
    Initialize-TarDisplayType
    $cur = [TarDisplay]::NewMode()
    if (-not [TarDisplay]::EnumDisplaySettingsEx($Device, -1, [ref]$cur, 0)) { return 'failed:enum' }
    if ($cur.dmPelsWidth -eq $Width -and $cur.dmPelsHeight -eq $Height -and [math]::Abs($cur.dmDisplayFrequency - $Refresh) -le $Tolerance) { return 'already' }

    # Pick the listed refresh rate closest to the target (Windows reports 119.98 Hz as 119 or 120).
    # If the normal list has none, look in the raw list (custom resolutions outside the TV's current EDID);
    # the driver still has to accept the mode with CDS_TEST below, and verify/fallback still apply.
    $freqs = @()
    foreach ($raw in $false, $true) {
        foreach ($m in [TarDisplay]::Modes($Device, $raw)) {
            if ($m -match '^(\d+)x(\d+)@(\d+)$' -and [int]$Matches[1] -eq $Width -and [int]$Matches[2] -eq $Height) {
                $f = [int]$Matches[3]
                if ([math]::Abs($f - $Refresh) -le $Tolerance) { $freqs += $f }
            }
        }
        if ($freqs.Count -gt 0) { break }
    }
    if ($freqs.Count -eq 0) { return 'nomode' }
    $freq = ($freqs | Sort-Object { [math]::Abs($_ - $Refresh) }, { -1 * $_ } | Select-Object -First 1)
    if ($DryRun) { return "dryrun:${Width}x${Height}@$freq" }

    $new = $cur
    $new.dmPelsWidth = $Width
    $new.dmPelsHeight = $Height
    $new.dmDisplayFrequency = $freq
    $new.dmFields = 0x80000 -bor 0x100000 -bor 0x400000   # DM_PELSWIDTH | DM_PELSHEIGHT | DM_DISPLAYFREQUENCY
    $test = [TarDisplay]::ChangeDisplaySettingsEx($Device, [ref]$new, [IntPtr]::Zero, 2, [IntPtr]::Zero)   # CDS_TEST
    if ($test -ne 0) { return "failed:test$test" }
    $flags = 0
    if ($Persist) { $flags = 1 }   # CDS_UPDATEREGISTRY: Windows keeps this mode after reboot / re-plug
    $rc = [TarDisplay]::ChangeDisplaySettingsEx($Device, [ref]$new, [IntPtr]::Zero, $flags, [IntPtr]::Zero)
    if ($rc -ne 0) { return "failed:$rc" }
    return 'ok'
}

Export-ModuleMember -Function *-Tar*
