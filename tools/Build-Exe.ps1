<#
.SYNOPSIS
  Builds TclAutoRes.exe (the tray launcher) from src\TclAutoResLauncher.cs. No administrator rights,
  nothing is downloaded: it uses the C# compiler that ships with .NET Framework 4 on every Windows 10/11.
.DESCRIPTION
  TclAutoRes.exe runs TclAutoResTray.ps1 inside its own process, so Windows shows the tray icon as
  "TclAutoRes" instead of "Windows PowerShell". The .exe is not committed to the repository (GitHub
  Releases attach a build of the tagged source). tools\Install-Autostart.ps1 runs this script automatically.
.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Exe.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $root 'src\TclAutoResLauncher.cs'
$outFile = Join-Path $root 'TclAutoRes.exe'
if (-not (Test-Path -LiteralPath $source)) { throw "not found: $source" }

# Icon: the same "TV" picture as the tray icon (green = ON), stored as PNG images in an .ico file.
function New-TvPng([int]$Size) {
    $bmp = New-Object System.Drawing.Bitmap $Size, $Size
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ScaleTransform($Size / 32.0, $Size / 32.0)
    $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 40, 40, 40))
    $g.FillRectangle($dark, 2, 6, 28, 18)   # screen
    $g.FillRectangle((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 46, 160, 67))), 5, 9, 22, 12)
    $g.FillRectangle($dark, 12, 25, 8, 3)   # stand
    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    return , $ms.ToArray()
}
function Write-TvIcon([string]$Path) {
    $sizes = @(16, 24, 32, 48, 256)
    $images = @($sizes | ForEach-Object { , (New-TvPng $_) })
    $fs = [System.IO.File]::Create($Path)
    $w = New-Object System.IO.BinaryWriter $fs
    try {
        $w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]$sizes.Count)   # ICONDIR
        $offset = 6 + 16 * $sizes.Count
        for ($i = 0; $i -lt $sizes.Count; $i++) {                                    # ICONDIRENTRY
            $dim = $(if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] })
            $w.Write([byte]$dim); $w.Write([byte]$dim); $w.Write([byte]0); $w.Write([byte]0)
            $w.Write([uint16]1); $w.Write([uint16]32)
            $w.Write([uint32]$images[$i].Length); $w.Write([uint32]$offset)
            $offset += $images[$i].Length
        }
        foreach ($img in $images) { $w.Write($img) }
    } finally { $w.Close() }
}

$icon = Join-Path ([System.IO.Path]::GetTempPath()) ("TclAutoRes-{0}.ico" -f [guid]::NewGuid().ToString('N'))
try {
    Write-TvIcon $icon
    $provider = New-Object Microsoft.CSharp.CSharpCodeProvider
    $cp = New-Object System.CodeDom.Compiler.CompilerParameters
    $cp.GenerateExecutable = $true
    $cp.GenerateInMemory = $false
    $cp.OutputAssembly = $outFile
    $cp.CompilerOptions = "/target:winexe /optimize+ /win32icon:`"$icon`""
    # System.Management.Automation.dll = the Windows PowerShell 5.1 engine this script is running on.
    [void]$cp.ReferencedAssemblies.Add('System.dll')
    [void]$cp.ReferencedAssemblies.Add('System.Core.dll')
    [void]$cp.ReferencedAssemblies.Add('System.Windows.Forms.dll')
    [void]$cp.ReferencedAssemblies.Add([System.Management.Automation.PowerShell].Assembly.Location)
    $result = $provider.CompileAssemblyFromFile($cp, $source)
    if ($result.Errors.HasErrors) {
        $result.Errors | Where-Object { -not $_.IsWarning } | ForEach-Object { Write-Host $_.ToString() }
        throw 'build failed'
    }
} finally {
    Remove-Item -LiteralPath $icon -Force -ErrorAction SilentlyContinue
}
$info = (Get-Item -LiteralPath $outFile).VersionInfo
Write-Host ("built {0} ({1} {2})" -f $outFile, $info.FileDescription, $info.FileVersion)
