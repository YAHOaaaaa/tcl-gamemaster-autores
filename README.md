# TclAutoRes：TCL TV の画面比率に合わせて PC の解像度を自動で切り替える

TCL の Google TV（Game Master / Game Bar）で **画面比率（16:9 / 21:9 / 32:9）を変えるだけで**、Windows PC の出力を、あらかじめ決めた解像度・リフレッシュレートに自動で切り替える常駐プログラムです。
例：16:9 → 3840x2160@120Hz、21:9（画面位置：下）→ 3840x1600@120Hz。

> [!CAUTION]
> **免責事項（必ずお読みください）**
>
> これは個人が自分の機器で試したものを公開しているだけで、TCL・Google・Microsoft・NVIDIA などのメーカーとは一切関係がありません。
> TV の開発者向け機能（ADB）を使い、PC の表示モードを自動で変更します。**機器の故障、画面が映らなくなること、データの消失、保証の対象外になること、ネットワーク上の不正アクセス、その他あらゆる損害が起きる可能性があります。**
> **利用はすべて自己責任です。利用者や第三者に損害が生じても、作者は一切の責任を負いません。作者に文句・苦情・損害賠償などの請求をしないことに同意できる場合だけ使ってください。** 詳細：[DISCLAIMER.md](DISCLAIMER.md)
>
> **Disclaimer:** Provided "AS IS", without warranty of any kind. Not affiliated with TCL or any other vendor. It may damage hardware, leave you without a picture, void warranties or cause other loss. **You use it entirely at your own risk; the author accepts no liability whatsoever and you agree not to make any claim against the author.** See [DISCLAIMER.md](DISCLAIMER.md).

## 仕組み

1. TV で比率を変えると、TV の内部ログに `display_ratio: 1` のような行が出る（[docs/how-it-works.md](docs/how-it-works.md)）。
2. PC の TclAutoRes が、ADB（ネットワークデバッグ）でそのログを読み続け、比率番号を受け取る。
3. 比率番号に対応する解像度・リフレッシュレートに、Windows の表示モードを切り替える。
4. （MediaTek の TV のみ）TV の HDMI 受信部の状態を読み、映っていなければ 60Hz などの予備モードに戻す。

- 管理者権限は不要です。TV の設定やファイルは変更しません（読み取りだけ）。
- Windows のスタートアップ（サインイン時）で裏で動き、システムトレイのアイコンで ON/OFF できます。
- Windows 標準の PowerShell 5.1 だけで動きます。必要なのは Google 公式の `adb.exe` だけです。トレイの起動役 `TclAutoRes.exe` も、Windows 標準の C# コンパイラーで手元で作ります（配布物に .exe は含みません）。

## 対応状況

| 項目 | 状態 |
|---|---|
| TCL 85T8B（日本向け、MT9653、Game Bar 3.00.19）での比率変更の検知 | 確認済み（16:9 ⇔ 21:9、変更から約 3〜5 秒で切替） |
| 同機種 + Windows 11 + RTX 3070：切替と、映らないときの 60Hz への自動復帰 | 確認済み |
| 同環境で 21:9（画面位置：下）の 3840x1600@120 を表示 | 確認済み（EDID 上書きで最大 FRL を 8G にした状態。受信 119.98Hz・FRL 8G×4、パネル出力 120Hz）。上書きなしでは無信号になり、自動で 60Hz に戻ることも確認 |
| 同環境で 32:9 の 3840x1080@120 を表示 | 確認済み（TV と同じタイミングのカスタム解像度。受信約 119.7Hz、TV で比率を変えると自動で切替） |
| ほかの TCL 機種（85Q7C など） | 未確認。[docs/porting.md](docs/porting.md) の手順で調べられます |

変更履歴：[CHANGELOG.md](CHANGELOG.md)

## 使い方（概要）

詳しくは [docs/setup.md](docs/setup.md)。

1. TV：開発者向けオプション → **ネットワークデバッグ ON**、IP アドレスを確認。
2. PC：Google 公式の **Android SDK Platform-Tools** を入れ、`adb connect <TVのIP>:5555`。TV に出る許可の確認に答える。
3. 21:9 の 3840x1600@120、32:9 の 3840x1080@120 など、Windows で選べないモードは **カスタム解像度**として作っておく（値は [docs/setup.md](docs/setup.md) の 3 章）。
4. `config\config.example.json` を `config\config.json` にコピーし、TV の IP とプロファイルを書く。
5. 確認 → 試運転 → 自動起動：
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Setup.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\TclAutoRes.ps1 -Apply 1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\TclAutoRes.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1
   ```
6. サインインすると `TclAutoRes.exe` が起動し、システムトレイのアイコンから自動切替の ON/OFF、今すぐ同期、手動切替、ログ表示ができます。`TclAutoRes.exe` は、登録のときに同梱のソースから手元で作られます（[docs/setup.md](docs/setup.md) の 7 章）。

## ほかの TCL TV で使う／AI に任せる

- 人が作業する場合：[docs/porting.md](docs/porting.md)。調査ツール `tools\Discover-TvSignals.ps1` が、比率を変えたときのログを記録し、設定案を出します。
- AI に任せる場合：このリポジトリを渡し、**まず [AGENTS.md](AGENTS.md) を読むように指示してください。** 移植の手順と、TV を改造しない・管理者権限を使わないなどの禁止事項が書いてあります。AI が出した手順やコードは、実行前に必ず自分で確認してください。

## 注意・制限

- **ネットワークデバッグは、信頼できる自宅ネットワークだけで使ってください。** 詳細：[SECURITY.md](SECURITY.md)
- TV の比率を変えるたびに、TV は EDID（PC に申告する対応解像度）を差し替えます。カスタム解像度は、その比率のときの EDID に対して作る必要があります。
- 環境によっては、カスタムの 3840x1600@120 が無信号になります（HDMI 2.1 FRL 12G の問題）。作者の環境では、Windows の EDID 上書きで回避しました。この方法は管理者権限が必要な別の作業なので、このリポジトリには含めていません：[docs/how-it-works.md](docs/how-it-works.md) の 3 章。
- TV を再起動した直後など、TV のログに比率の記録が無いときは、次に比率を変えるまで切り替えません。

## English summary

TclAutoRes is a small Windows PowerShell watcher (no admin rights) that follows a TCL Google TV's Game Bar "screen ratio" setting over adb and switches the PC's display mode to a configured resolution/refresh rate per ratio (e.g. 16:9 → 3840x2160@120, 21:9 → 3840x1600@120). It never modifies the TV; it only reads `logcat` (and, on MediaTek TVs, a read-only HDMI receiver debug node to verify the new mode and fall back if there is no picture). The tray icon runs as `TclAutoRes.exe`, a small launcher that `tools/Install-Autostart.ps1` compiles locally from `src/TclAutoResLauncher.cs` (no binary is shipped). Verified log detection on a TCL 85T8B (JP, MT9653, Game Bar 3.00.19). For other models, run `tools/Discover-TvSignals.ps1` and follow `docs/porting.md`; AI assistants should read `AGENTS.md` first. Use entirely at your own risk - see `DISCLAIMER.md` and `SECURITY.md`.

## ライセンス

[MIT License](LICENSE)。無保証です。
