# ほかの TCL TV で使う（移植ガイド）

免責事項は [../DISCLAIMER.md](../DISCLAIMER.md) を参照。AI に作業させる場合は、[../AGENTS.md](../AGENTS.md) を読ませてください。

TCL の Google TV は、多くの機種で同じ Game Bar（`com.tcl.gamebar`）と、MediaTek 系の映像処理を使っています。そのため、同系統の機種（例：85Q7C、C755、C855、T7B など）では、同じ仕組みで動く可能性があります。ただし、ログの出方、比率の番号、TV が申告する解像度は、機種やソフトウェアの版で違うことがあります。**下の表で「確認済み」以外は、すべて未確認です。**

## 手順

1. [setup.md](setup.md) の 1〜2 を行い、PC から TV に adb で接続する。
2. 調査ツールを実行し、記録中に TV の Game Bar で画面比率を **16:9 → 21:9 → 32:9 → 16:9** と変える（それぞれ 5 秒ほど待つ）。
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Discover-TvSignals.ps1 -Address 192.168.0.50:5555 -OpenGameBar
   ```
3. `discover-output\report-*.md` を開く。
   - 「Known ratio patterns found」に行があれば、「Suggested config.json "tv" section」をそのまま `config.json` に使えます。
   - 無ければ、「Candidate log lines」から比率を変えたときだけ出る行を選び、`(?<ratio>\d+)` を含む正規表現を書きます。
   - 「Wide-screen timings」は、TV が 21:9 / 32:9 のときに申告する解像度です。
4. `profiles` を決め、必要ならカスタム解像度を作る（[setup.md](setup.md) の 3）。
5. [setup.md](setup.md) の 5〜7 で確認し、常駐させる。
6. 結果を下の表に追記して、プルリクエストやフォークで共有してもらえると、ほかの人の役に立ちます（IP アドレスなどの個人情報は入れないでください）。

## 機種表

| 機種 | clientType / SoC | Game Bar | 検知に使うログ | 比率番号 | 確認状況 |
|---|---|---|---|---|---|
| 85T8B（日本） | TCL-JP-MT9653-S1 / MT9653 | 3.00.19 | `sita.thal` `fpi_edid_set_wide_screen_mode`、`VIDEOFUNC` `setWideScreenRatio` | 0 = 16:9、1 = 21:9、2 = 32:9 | 検知・切替・自動復帰・21:9@120・32:9@120：確認済み（Windows 11 + RTX 3070、21:9@120 は EDID 上書きで最大 FRL 8G、32:9@120 は TV と同じタイミングのカスタム解像度） |
| 85Q7C ほか | ? | ? | ? | ? | 未確認 |

## うまくいかないとき

| 症状 | 確認すること |
|---|---|
| `TV not reachable` | TV の IP、ネットワークデバッグが ON か、TV がスタンバイでないか |
| `unauthorized` | TV の画面に出ている許可の確認に答える |
| 比率を変えても反応しない | `-Verbose` で起動してログを見る。`tv.logTags` と `detectors` が機種に合っているか（調査ツールで確認） |
| `nomode` | Windows にそのモードが無い。カスタム解像度を作る。TV が別の比率のときは EDID が違うので、モード一覧も変わる |
| 切り替わった後に無信号 → `fallback` | そのモードが TV やケーブルで通っていない。[how-it-works.md](how-it-works.md) の 3 章 |
| 切り替えた直後に元に戻る | `timing.settleMs` を 4000 程度に増やす |
