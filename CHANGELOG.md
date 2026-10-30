# 変更履歴 / Changelog

## v2.0.0（2026-10-30）

- **32:9 に対応**：Game Bar で 32:9 にすると、3840x1080@120 に自動で切り替わります（85T8B で確認）。
  - Windows の EDID 上書き中は、EDID の範囲外のカスタム解像度が通常のモード一覧に出ないことがあるため、生のモード一覧（`EDS_RAWMODE`）からも探すようにしました。切替前の `CDS_TEST`、映ったかの確認、映らないときの予備モードへの復帰はそのままです。
  - `-ListDisplays` と `tools/Test-Setup.ps1` で、生の一覧だけにあるモードも表示します。
  - 手順書に、TV が申告する 32:9 のタイミング（3840x1080、全体 4000x1111、119.974Hz / 59.968Hz）を追加しました。
- **トレイを `TclAutoRes.exe` で起動**：タスクバーの設定やタスクマネージャーで「Windows PowerShell」ではなく「TclAutoRes」と表示されます。
  - `.exe` は配布しません。`tools/Build-Exe.ps1` が、同梱のソース `src/TclAutoResLauncher.cs` から Windows 標準の C# コンパイラーで手元で作ります（管理者権限・ダウンロード不要）。
  - `tools/Install-Autostart.ps1` は `.exe` を作って登録し、動いている TclAutoRes を先に止めます。`-NoExe` で従来の powershell.exe での起動も選べます。

**v1 から更新するとき：** ファイルを置き換えてから `tools\Install-Autostart.ps1` を実行し直してください。トレイアイコンが「^」の中に隠れた場合は、設定 → 個人用設定 → タスクバー → その他のシステム トレイ アイコン で「TclAutoRes」をオンにします。

## v1.0.0（2026-10-30）

- 最初の公開。16:9 / 21:9 の自動切替、トレイアイコン、自動起動、MediaTek の HDMI 受信部での確認と予備モードへの自動復帰。

---

**English:** v2.0.0 adds 32:9 (3840x1080@120, verified on the 85T8B) by falling back to the raw mode list when a custom resolution is outside the current (overridden) EDID, and runs the tray icon as `TclAutoRes.exe`, built locally from the included C# source (no binary is shipped). v1.0.0 was the first release (16:9 / 21:9).
