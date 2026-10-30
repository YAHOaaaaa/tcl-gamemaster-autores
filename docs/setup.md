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
- 21:9 の 3840x1600@120 などは TV の EDID に無いので、GPU のコントロールパネルで**カスタム解像度**を作ります（NVIDIA：「解像度の変更」→「カスタマイズ」→「カスタム解像度の作成」。タイミングは CVT 減少ブランキング）。
- 作ったら一度手動で切り替えて、映ることを確認してください。映らない場合は [how-it-works.md](how-it-works.md) の 3 章 を参照してください。

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
- Windows にサインインすると、通知領域（システムトレイ）に TV の形のアイコンが出て、裏で監視が始まります。
- アイコンの色：緑 = ON、灰 = OFF、橙 = 再起動中。右クリックのメニューで、ON/OFF、今すぐ TV に合わせる、手動切替、ログを開く、終了ができます。ON/OFF は次回の起動にも引き継がれます。
- 監視が止まっても自動で再起動します。短時間に 3 回止まった場合は、その回だけ OFF にして通知します（別の常駐が動いている、設定の誤りなど）。
- アイコン無しで動かしたい場合は `-NoTray` を付けて登録します。
- 先に手動で `TclAutoRes.ps1` を常駐させている場合は、その窓を閉じてから登録してください（同時に 2 つは動きません）。

ログ：`%LOCALAPPDATA%\TclAutoRes\tclautores.log`

## やめるとき
1. `tools\Install-Autostart.ps1 -Remove`
2. TV の開発者向けオプションで、ネットワークデバッグを OFF にし、「USB デバッグの承認を取り消す」を実行
3. 不要ならフォルダを削除

`-ExecutionPolicy Bypass` は、そのスクリプトの実行時だけポリシーを外す指定です。PC 全体の設定は変えません。実行前にスクリプトの中身を確認してください。
