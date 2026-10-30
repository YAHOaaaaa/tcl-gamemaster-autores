# 仕組みと調査結果 / How it works

免責事項は [../DISCLAIMER.md](../DISCLAIMER.md) を参照。ここに書いたことは、下の「確認環境」で観測した事実と、そこからの推定です。

## 確認環境

| 項目 | 値 |
|---|---|
| TV | TCL 85T8B（日本向け）。`ro.product.model=Smart TV Pro`、`ro.product.clientType=TCL-JP-MT9653-S1` |
| SoC | MediaTek MT9653（`ro.hardware=mt5896`）、32bit ユーザーランド（armeabi-v7a） |
| Game Bar | `com.tcl.gamebar` 3.00.19（`/product/app/GameBar_OS/GameBar_OS.apk`） |
| PC | Windows 11、NVIDIA GeForce RTX 3070、TV の HDMI 1 に接続 |

## 1. TV で比率を変えると何が起きるか

Game Bar → メニュー → 画面比率 で 16:9 / 21:9 / 32:9 を選ぶと、TV は次を行います（logcat で確認）。

```
I/VIDEOFUNC: TclDisplay [setWideScreenRatio,371] windowID is 198 wideScreenRatio is [1], act is [2], ret is [1]
I/sita.thal: fpi_edid_set_wide_screen_mode, port: 1, display_ratio: 1
I/sita.thal: fpi_edid_set_desc_dtd_reso 1111 ,Wide Screen mode with 144HZ not selected
```

- 比率番号：**0 = 16:9、1 = 21:9、2 = 32:9**。
- `fpi_edid_set_wide_screen_mode` で、TV は **PC に見せる EDID を差し替え**、ホットプラグを送ります。PC は EDID を読み直し、Windows は「その EDID で最後に使ったモード」か推奨モードを選びます。
- 16:9 に戻すと `Recover from Wide Screen mode ...` が出て、元の EDID に戻ります。

TclAutoRes は、この 2 種類のログ行（タグ `sita.thal` と `VIDEOFUNC`）を `adb logcat` で監視し、比率番号に対応するプロファイルの解像度・リフレッシュレートに Windows の表示モードを切り替えます。

## 2. なぜ自動では 60Hz になるのか

21:9 用 EDID の詳細タイミング（DTD）は、TV の設定ファイルから読まれます。

- ライブラリ：`/vendor/lib/libtos_hdmi_service.so`（`wide_screen_resolution_init`、`fpi_edid_set_desc_dtd_reso`）。
- 設定キー：`edid.ZOOM.Refresh_N`、`edid.ZOOM.H_ACTIVE_PIXELS_N` など。設定が無いときだけ既定値（"Default Wide Screen EDID ..."）を使う。
- 確認環境の値（`/tclconfig/hardware/param/edid/EDID_DOBLYVISION_JP_1080P_240HZ/edid-ARC-HDMI1-144Hz.ini` の `ZOOM`）：

| N | 解像度 | リフレッシュ |
|---|---|---|
| 1 | 2560x1080 | 60.000 |
| 2 | 3840x1600 | 59.963 |
| 3 | 3840x1080 | 59.968 |
| 4 | 3840x1080 | 119.974 |

つまり 21:9 で TV が申告する 3840x1600 は 60Hz だけです。120Hz にするには PC 側でカスタム解像度を作る必要があります。

### TV 側だけで 120Hz にできない理由
- `/tclconfig` は読み取り専用（ext4、`ro`、root 所有）。書き換えには root 化が必要で、文鎮化の危険があります。**このリポジトリは TV の改造を扱いません。**
- 仮に書き換えられても、DTD のピクセルクロック欄の上限は 655.35MHz です。3840x1600@120 は CVT-RB2 でも約 774MHz なので、DTD には書けません（DTD で書ける上限は約 99Hz）。
- `/data/local/tmp/HDMI%d_*.bin` という文字列はありますが、EDID を書き出すだけ（`fopen(..., "wb")`）で、読み込み先ではありません。

## 3. 3840x1600@120 が映らない場合（FRL の問題）

確認環境では、カスタム解像度の 3840x1600@120 を送ると、NVIDIA ドライバーは TV が申告する最大の FRL 速度（12Gbps×4）でリンクを張りました。その場合、映像は映りませんでした（TV の HDMI 受信部で `DE Stable=0`）。4K144 も同じく無信号です。

同じタイミングでも、Windows の EDID 上書きで HF-VSDB の Max_FRL_Rate を 12G→8G に下げると、FRL 8Gbps×4 で映りました。必要な帯域は約 22Gbps なので、8G×4 に収まります。詳しい手順と記録は、元の調査リポジトリ [YAHOaaaaa/tcl-85t8b-219-bottom-120hz](https://github.com/YAHOaaaaa/tcl-85t8b-219-bottom-120hz) にあります。この方法は管理者権限とレジストリ変更が必要なので、このリポジトリには含めていません。

**EDID 上書きを使う場合の注意：** 上書き中、Windows は TV の EDID 差し替えを見ません。そのため、比率を変えても Windows は自動でモードを変えません。この状態でも、TclAutoRes が TV のログを見て切り替えるので動作します。

## 4. 切替が正しく行われたかの確認（MediaTek のみ）

`/sys/devices/platform/mtk_srccap0/mtk_dbg/hdmirx/HDMI_INFO` は、shell 権限で読めます。各 HDMI ポートの `DE Stable`、`Width`、`Height`、`Refresh Rate(mHz)`、`FRL Rate` などが列で並びます。確認環境では、HDMI 1 は「Port 3」の列でした。

TclAutoRes の `verify` を有効にすると、切替後にこれを読みます。目的の解像度・リフレッシュレートで安定した信号が来なければ、`fallback` のモード（例：同じ解像度の 60Hz）に戻します。

## 5. Game Bar の開き方（調査用）

`am start -a com.tcl.gamebar.main` で開けます（Game Bar 3.x）。画面の構成は `uiautomator dump` で読めます。このTVでは `screencap` は使えませんでした（空ファイルになる、またはクラッシュ）。
