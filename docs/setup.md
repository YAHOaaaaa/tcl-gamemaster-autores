# セットアップ手順

免責事項は [../DISCLAIMER.md](../DISCLAIMER.md)、セキュリティの注意は [../SECURITY.md](../SECURITY.md) を先に読んでください。

## 0. 必要なもの
- Windows 10 / 11（Windows PowerShell 5.1 は標準で入っています）
- Android SDK Platform-Tools（`adb.exe`）。必ず Google 公式（developer.android.com の「SDK Platform-Tools」）から入手してください。
- TCL の Google TV（Game Master / Game Bar 搭載機種）と PC が同じ自宅ネットワークにあること
- 切り替えたい解像度・リフレッシュレートが、Windows の表示モードとして選べること（手順 3）

## 1. TV の準備
1. 設定 → システム → デバイス情報 → 「Android TV OS ビルド」を 7 回押して、開発者向けオプションを有効にする（機種により場所が違います）。
2. 設定 → システム → 開発者向けオプション → **ネットワークデバッグ**（または「ADB デバッグ」）を ON。
3. 設定 → ネットワーク → ステータス で **IP アドレス**を確認する。ルーターで TV の IP を固定（DHCP 予約）しておくと楽です。

## 2. PC から TV に接続する
```powershell
adb connect 192.168.0.50:5555     # TV の IP に置き換える
adb devices -l                    # "device" と表示されれば OK
```
TV に「USB デバッグを許可しますか？」が出たら、**自分が今つないだときだけ**「許可」を選びます。

## 3. 目標のモードを Windows で選べるようにする
- 16:9 の 4K120 は、通常は TV の EDID に含まれています。
- 21:9 の 3840x1600@120 などは TV の EDID に無いので、GPU のコントロールパネルで**カスタム解像度**を作ります（NVIDIA：「解像度の変更」→「カスタマイズ」→「カスタム解像度の作成」）。
- **21:9 で Game Bar の画面位置を「トップ」にする場合は、垂直の合計を 2250 行にしたタイミング（下の表）で作ってください。** 自動（CVT 減少ブランキング、垂直合計 1694）のままだと、トップのときだけ画面の途中から下が 1 フレーム遅れて、映像全体の遅延と同期のずれが出ます（原因は [how-it-works.md](how-it-works.md) の 5 章）。このタイミングは「下」「中間」でも問題なく使えます。
- 32:9 の 3840x1080 は、TV が 32:9 のときの EDID には入っています。ただし Windows の EDID 上書きを使っている場合（[how-it-works.md](how-it-works.md) の 3 章）、Windows はその EDID を見ないので、これもカスタム解像度で作ります。
- 32:9 は TV と同じタイミングで作ると確実です。値は NVIDIA の「タイミング」の「標準」を「手作業」にして入力します。確認環境（85T8B）で使っている値：

  | 用途 | 解像度 | 水平：フロントポーチ / 同期幅 / 合計 | 垂直：フロントポーチ / 同期幅 / 合計 | 極性 | リフレッシュ（ピクセルクロック） |
  |---|---|---|---|---|---|
  | 21:9（トップ対応） | 3840x1600 | 48 / 32 / 4000 | 638 / 6 / 2250 | +/− | 120.000Hz（1080.00MHz） |
  | 32:9 | 3840x1080 | 48 / 32 / 4000 | 3 / 10 / 1111 | +/+ | 119.974Hz（533.16MHz） |
  | 32:9 予備 | 3840x1080 | 48 / 32 / 4000 | 3 / 10 / 1111 | +/+ | 59.968Hz（266.50MHz） |

  21:9 の 1080MHz は、確認環境では Windows の EDID 上書きで最大 FRL を 8G にした状態で映っています（[how-it-works.md](how-it-works.md) の 3 章）。
- 32:9 で画面位置を変えた場合に同じ症状が出るかは未確認です。出る場合は、32:9 も垂直の合計を 2250 行（前ポーチ 1150、同期 10、1080MHz）にすると、同じ理屈で直る見込みです（未検証）。
- NVIDIA の「テスト」のあとの「この解像度を保存しますか」は、約 15 秒で自動的に元に戻ります。映ったらすぐに「はい」を押してください。今使っている解像度は編集できないので、編集するときは先に別の解像度（例：`TclAutoRes.ps1 -Apply 0`）に切り替えます。

- EDID の範囲外のカスタム解像度は、Windows の通常のモード一覧に出ないことがあります（確認環境では 3840x1080@120 がそうでした）。TclAutoRes は、通常の一覧に無いときは生の一覧（EDS_RAWMODE）からも探し、`-ListDisplays` では「Raw-only modes」として表示します。
- 作ったら一度手動で切り替えて、映ることを確認してください（`TclAutoRes.ps1 -Apply 2` など）。映らない場合は [how-it-works.md](how-it-works.md) の 3 章 を参照してください。

## 4. 設定ファイル
```powershell
copy config\config.example.json config\config.json
notepad config\config.json
```
- `adb.address`：TV の `IP:5555`
- `profiles`：比率番号（0 = 16:9、1 = 21:9、2 = 32:9）ごとの解像度・リフレッシュレートと、映らなかったときの `fallback`
- MediaTek 以外の TV では `verify.enabled` を `false` に

## 5. 確認（何も変更しません）
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Setup.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\TclAutoRes.ps1 -ListDisplays
```
`[NG]` の行があれば、その項目を直します。

## 6. 試す
```powershell
# 手動で 1 回だけ切替（1 = 21:9 のプロファイル）
powershell -NoProfile -ExecutionPolicy Bypass -File .\TclAutoRes.ps1 -Apply 1
# 常駐（Ctrl+C で終了）。-DryRun を付けると、切り替えずにログだけ出します
powershell -NoProfile -ExecutionPolicy Bypass -File .\TclAutoRes.ps1
```
常駐中に TV の Game Bar で比率を変えると、数秒後に PC の表示モードが切り替わります。

## 7. 自動起動とトレイアイコン
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1          # 登録して開始（トレイアイコン付き）
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Install-Autostart.ps1 -Remove  # 解除
```
- `TclAutoRes.exe`（トレイアイコンの起動役）は、[Releases](https://github.com/YAHOaaaaa/tcl-gamemaster-autores/releases) の zip に入っていて、ダブルクリックでも起動できます。コード署名は無いので、Windows が警告を出すことがあります。zip の中の `SHA256SUMS.txt` で、ファイルが壊れたり差し替えられたりしていないか確かめられます。
- 登録のときは、`tools\Build-Exe.ps1` で `TclAutoRes.exe` を同梱のソース（`src\TclAutoResLauncher.cs`）から作り直して、それを使います。Windows 標準の C# コンパイラーを使うので、管理者権限もダウンロードも不要です。
- Windows にサインインすると `TclAutoRes.exe` が起動し、通知領域（システムトレイ）に TV の形のアイコンが出て、裏で監視が始まります。窓は出ません。タスクバーの設定やタスクマネージャーでは「TclAutoRes」と表示されます。
- 初めて `TclAutoRes.exe` で登録したときは、アイコンが「^」の中に隠れていることがあります。設定 → 個人用設定 → タスクバー → その他のシステム トレイ アイコン で「TclAutoRes」をオンにすると、常に表示されます（以前の「Windows PowerShell」の項目は不要です）。
- 登録し直すと、動いている TclAutoRes をいったん止めてから、`TclAutoRes.exe` を作り直して起動します。
- アイコンの色：緑 = ON、灰 = OFF、橙 = 再起動中。右クリックのメニューで、ON/OFF、今すぐ TV に合わせる、手動切替、ログを開く、終了ができます。ON/OFF は次回の起動にも引き継がれます。
- 監視が止まっても自動で再起動します。短時間に 3 回止まった場合は、その回だけ OFF にして通知します（別の常駐が動いている、設定の誤りなど）。
- アイコン無しで動かしたい場合は `-NoTray` を付けて登録します。`.exe` を使わず、これまでどおり powershell.exe でトレイを動かす場合は `-NoExe` を付けます（一覧での名前は「Windows PowerShell」になります）。
- 先に手動で `TclAutoRes.ps1` を常駐させている場合は、その窓を閉じてから登録してください（同時に 2 つは動きません）。

ログ：`%LOCALAPPDATA%\TclAutoRes\tclautores.log`

## やめるとき
1. `tools\Install-Autostart.ps1 -Remove`
2. TV の開発者向けオプションで、ネットワークデバッグを OFF にし、「USB デバッグの承認を取り消す」を実行
3. 不要ならフォルダを削除

`-ExecutionPolicy Bypass` は、そのスクリプトの実行時だけポリシーを外す指定です。PC 全体の設定は変えません。実行前にスクリプトの中身を確認してください。
