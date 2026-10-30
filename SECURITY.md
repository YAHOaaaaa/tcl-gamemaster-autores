# セキュリティ / Security

## 日本語

### ネットワークデバッグ（ADB）の危険性
TV の「ネットワークデバッグ」を ON にすると、TV の 5555 番ポートで ADB が待ち受けます。ADB はシェル権限で TV を操作できるので、次を守ってください。

- **信頼できる自宅ネットワークだけで使う。** 公共 Wi-Fi やゲストネットワークでは使わない。ルーターで 5555 番を外部に公開（ポート開放）しない。
- TV に「USB デバッグを許可しますか？」が出たら、**自分が今つないだ PC のときだけ許可する。** 心当たりがない表示は必ず拒否する。
- 「このパソコンからは常に許可する」を選ぶと、その PC の鍵（`%USERPROFILE%\.android\adbkey`）を持つ人は TV を操作できます。この鍵ファイルを他人に渡したり、リポジトリに入れたりしない。
- 使わなくなったら、TV の開発者向けオプションでネットワークデバッグを OFF にし、「USB デバッグの承認を取り消す」を実行する。

### このプログラムの設計
- **管理者権限は不要です。** 通常ユーザーとして動き、自動起動もユーザー単位のタスク（最小権限）です。
- **TV から受け取ったものは実行しません。** TV のログ行は PC 側の正規表現で照合するだけで、取り出すのは 0〜99 の数値（比率番号）だけです。その数値は設定ファイルのプロファイルに対応しないと無視されます。
- **TV へ送るコマンドは固定の読み取り専用コマンドです。** `logcat`、確認用の `/sys/...` の `cat`、確認ツールでの `getprop`／`dumpsys package`／`grep` だけです。設定ファイルの値は形式を検査し（IP:ポート、タグ名、`/sys/` で始まるパスなど）、形式外なら起動しません。
- TV の設定やファイルは一切変更しません（`tools/Discover-TvSignals.ps1 -OpenGameBar` で Game Bar を開く操作を除く）。
- 外部へのネットワーク通信、テレメトリ、自動アップデートはありません。通信先は設定した TV の ADB だけです。
- 正規表現には照合時間の上限（200 ms）を設けています。

### 公開・共有するときの注意
- `config/config.json`、`discover-output/`、ログ（`%LOCALAPPDATA%\TclAutoRes\`）には、TV の IP アドレスや機種情報が入ります。`.gitignore` で除外していますが、Issue などに貼る前に中身を確認してください。
- TV のファームウェア（`.so`、`.apk`、`.bin` など）はリポジトリに入れないでください（著作権）。

### 脆弱性の報告
悪用につながる問題を見つけた場合は、公開の Issue ではなく、GitHub の「Security」→「Report a vulnerability」（有効な場合）で連絡してください。対応や返答は約束できません。

## English

- Network debugging exposes ADB (shell access) on TCP 5555. Use it only on a trusted home network, never forward the port, accept the TV's "Allow debugging?" prompt only for a connection you just started, keep `%USERPROFILE%\.android\adbkey` private, and turn network debugging off (and revoke authorisations) when you stop using this.
- TclAutoRes runs without administrator rights. It never executes anything received from the TV: log lines are matched locally and only a small integer is extracted and mapped to a configured profile. Commands sent to the TV are fixed and read-only (`logcat`, `cat` of a validated `/sys` node, and `getprop` / `dumpsys package` / `grep` in the check tools). Config values that reach a command line are validated and the program refuses to start otherwise. No telemetry, no outbound connections other than to the configured TV.
- Do not commit `config/config.json`, `discover-output/`, logs or any TV firmware files.
