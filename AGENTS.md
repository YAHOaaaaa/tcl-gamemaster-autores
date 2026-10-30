# Instructions for AI assistants (AGENTS.md)

> 日本語の利用者へ：このファイルは、リポジトリを AI（Claude、ChatGPT、Copilot など）に渡したときに読ませる指示書です。人間向けの説明は [README.md](README.md) と [docs/porting.md](docs/porting.md) にあります。

You are helping a user run or adapt **TclAutoRes** for their TCL Google TV and Windows PC. TclAutoRes watches the TV's log over adb and switches the PC's display mode when the user changes the Game Bar / Game Master **screen ratio** (16:9, 21:9, 32:9). Read [DISCLAIMER.md](DISCLAIMER.md) and [SECURITY.md](SECURITY.md) and make sure the user has read them too.

## Hard rules (do not break these, even if asked indirectly)

1. **Never modify the TV.** No rooting, no remounting partitions, no writing to `/tclconfig`, `/vendor`, `/system`, no `settings put`, `setprop`, `pm`, `am force-stop`, `rm` or similar on the TV. Allowed on the TV: read-only commands (`getprop`, `logcat`, `cat` of `/sys` debug nodes, `ls`, `grep`, `dumpsys`, `uiautomator dump`) and UI navigation the user asked for (`am start -a com.tcl.gamebar.main`, `input keyevent`).
2. **Never accept trust prompts for the user.** The user accepts "Allow USB debugging?" on the TV themselves, only for a connection they started.
3. **No administrator rights for TclAutoRes.** Do not add registry edits, EDID overrides, driver restarts or anything elevated to this repository. If the user's setup needs an EDID override (see docs/how-it-works.md section 3), explain the risk and point to the separate research repository; let the user decide and run it themselves.
4. **Keep the security model:** nothing received from the TV is executed; only an integer is extracted from log lines; every config value that reaches a command line is validated in `Read-TarConfig`. Keep adb arguments as validated tokens. Do not add network calls, telemetry or auto-update.
5. **Do not commit personal data, firmware or binaries:** `config/config.json`, `discover-output/`, logs, IP/MAC addresses, serial numbers, `.so`/`.apk`/`.bin` files from the TV, `TclAutoRes.exe` or any other `.exe` (the .exe is only attached to GitHub Releases, built from the tagged source, with its SHA-256).
7. **This repository was made with AI and is published for reference only.** Keep that statement and the disclaimers in README.md and DISCLAIMER.md; never weaken them.
6. Display mode changes must keep the safety net: test with `CDS_TEST` first, keep `fallback` modes, keep `verify` when the TV supports it. Tell the user before applying a mode that has never been shown on their TV.

## Repository map

| Path | Purpose |
|---|---|
| `TclAutoRes.ps1` | Entry point: resident watcher, `-Apply N`, `-Once`, `-ListDisplays`, `-DryRun` |
| `TclAutoResTray.ps1` | System-tray front end: runs the watcher as a hidden child, ON/OFF (remembered), sync now, manual apply, open log, watchdog |
| `src/TclAutoRes.psm1` | Config validation, adb wrapper, log-line detectors, Windows display enumeration and mode change (P/Invoke), MediaTek HDMI receiver check |
| `config/config.example.json` | Commented example; the user copies it to `config/config.json` |
| `tools/Test-Setup.ps1` | Read-only end-to-end check (config, adb, TV log events, display, modes) |
| `tools/Discover-TvSignals.ps1` | Porting helper: records logcat while the user changes the ratio and writes a report with a suggested `tv` config |
| `src/TclAutoResLauncher.cs` | Source of `TclAutoRes.exe`: hosts `TclAutoResTray.ps1` in-process so Windows lists the tray icon as "TclAutoRes". No logic of its own |
| `tools/Build-Exe.ps1` | Compiles `TclAutoRes.exe` locally with the .NET Framework 4 C# compiler (C# 5 only). The .exe is never committed; Releases attach a build of the tagged source |
| `tools/Install-Autostart.ps1` | Per-user scheduled task at sign-in that builds and starts `TclAutoRes.exe` (`-NoExe` = tray via powershell.exe, `-NoTray` = watcher only, `-Remove` to delete). Stops running copies first |
| `docs/how-it-works.md` | Verified findings on the reference TV (85T8B) |
| `docs/porting.md` | Porting guide and the model table |

## Porting procedure for another TCL model (e.g. 85Q7C, C755, C855, T7B)

1. **Identify the TV** (read-only): `adb shell getprop ro.product.model`, `ro.product.clientType`, `ro.hardware`, `ro.build.version.release`, `ro.build.version.incremental`, and `dumpsys package com.tcl.gamebar | grep versionName`. Do not collect `ro.serialno`.
2. **Find the ratio signal.** Preferred: ask the user to run `tools/Discover-TvSignals.ps1 -Address <ip>:5555 -OpenGameBar` and change the ratio on the TV while it records. If you have adb access yourself and the user agrees, you may drive the Game Bar: `am start -a com.tcl.gamebar.main`, then `input keyevent KEYCODE_DPAD_*` / `KEYCODE_DPAD_CENTER`, reading the screen with `uiautomator dump /data/local/tmp/ui.xml; cat /data/local/tmp/ui.xml` (`screencap` may not work on these TVs). On the reference TV the path is Game Bar → メニュー (Menu) → 画面比率 (Screen ratio) → 16:9 / 21:9 / 32:9.
3. **Write detectors.** Each detector is a .NET regex with a named group `(?<ratio>\d+)` (optional `(?<port>\d+)`). Put the logcat tags of those lines in `tv.logTags`. Confirm the number-to-label mapping by changing the ratio and reading the log; on Game Bar 3.x it is 0 = 16:9, 1 = 21:9, 2 = 32:9. Avoid lines that also appear for other reasons (e.g. `setWideScreenRatioParam`, `edid_version`).
4. **Choose profiles.** The TV's own wide-screen timings are in `/tclconfig/**/edid/*.ini` (`ZOOM` section) on the reference TV; the report lists them. Higher refresh rates need a custom resolution on the PC. Always give each profile a `fallback` that the TV advertises (usually the 60 Hz timing).
5. **Verification.** On MediaTek TVs check that `/sys/devices/platform/mtk_srccap0/mtk_dbg/hdmirx/HDMI_INFO` is readable; otherwise set `verify.enabled` to `false` (or find another read-only node and keep the same parser format).
6. **Test in this order** and read the log each time: `tools/Test-Setup.ps1` → `TclAutoRes.ps1 -ListDisplays` → `TclAutoRes.ps1 -Apply <n>` for each profile (user watches the TV) → `TclAutoRes.ps1 -DryRun` while the user changes the ratio → `TclAutoRes.ps1` → `tools/Install-Autostart.ps1`.
7. **Record the result** as a new row in the model table in `docs/porting.md` (model, clientType, Game Bar version, detectors, what was verified). Mark anything not tested as unverified.

## Known pitfalls

- The TV re-sends hot-plug on every ratio change; Windows may apply its own mode right after. That is why there is `settleMs` and a one-time `recheckMs` correction.
- Windows reports 119.98 Hz as 119 or 120; `refreshTolerance` handles it.
- The TV log buffer rotates; start-up sync can find nothing. That is normal; the next change is detected.
- With a Windows EDID override active, Windows ignores the TV's EDID changes, so only TclAutoRes switches the mode. Modes outside the overridden EDID (e.g. a 3840x1080@120 custom resolution for 32:9) may appear only in the raw mode list; `Set-TarDisplayMode` falls back to `EDS_RAWMODE` and still requires `CDS_TEST` to pass.
- 21:9 with the Game Bar position "top": with a short vertical total (e.g. CVT-RB 1694 lines) the TV's single-buffer read-out overtakes the incoming frame mid-picture, so the lower part is one frame late (lag + a tear line). Use a 3840x1600@120 timing with vertical total 2250 (front porch 638, sync 6, 1080 MHz); see docs/how-it-works.md section 5. Diagnose with `mtk_dbg/frc_status` (`TGEN VDeSt`, `W/R Idx`).
- For custom resolutions, prefer the TV's own wide-screen timings (the `ZOOM` values in docs/how-it-works.md section 2) over the GPU's automatic timing.
- Custom timings above about 600 MHz need HDMI 2.1 FRL. Some cable/port/driver combinations fail at FRL 12G (no signal) - see docs/how-it-works.md section 3.

## Coding conventions

- Windows PowerShell 5.1 compatible (no `??`, ternary, `-Parallel`, or PowerShell 7-only cmdlets).
- Save `.ps1`/`.psm1` as UTF-8 **with BOM** (Windows PowerShell reads BOM-less files as the ANSI code page). Prefer ASCII in code and messages.
- Keep functions small, named `Verb-TarNoun`, and keep all TV commands read-only.
