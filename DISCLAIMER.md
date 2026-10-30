# 免責事項 / Disclaimer

## 日本語

1. このリポジトリ（プログラム、設定例、文書、調査結果のすべて）は、個人が自分の機器で試した結果を公開しているものです。正しく動くこと、安全であること、特定の目的に合うこと、ほかの機種・環境で同じ結果になることは、**一切保証しません。**
2. **このリポジトリのプログラム、`TclAutoRes.exe`、文書は、AI（Claude などの生成 AI）を使って作ったものです。** 作者がすべての内容を検証・理解しているわけではなく、誤り、不正確な説明、危険な動作が含まれている可能性があります。**参考用として公開しているもので、そのまま使うことを勧めるものではありません。作者は責任を取れません。**
3. TCL、Google、Microsoft、NVIDIA、AMD、Intel、MediaTek その他のメーカーとは関係がなく、各社が認めた方法でも推奨した方法でもありません。製品名・商標は各社のものです。
4. このプログラムは、TV の開発者向け機能（ADB／ネットワークデバッグ）を使い、PC の表示モード（解像度・リフレッシュレート）を自動で変更します。規格外のカスタム解像度を使う場合もあります。これにより、**TV・PC・GPU・ケーブルその他の機器の故障、画面が映らなくなること、設定やデータの消失、メーカー保証の対象外になること、ネットワーク上の第三者からの不正アクセス、その他あらゆる直接・間接の損害**が起きる可能性があります。
5. **使用はすべて利用者自身の判断と責任で行ってください。このリポジトリの内容（リリースで配布する `TclAutoRes.exe` を含む）を使ったこと、または使えなかったことによって利用者や第三者に損害が生じても、作者は一切の責任を負いません。**
6. **故障・不具合・損害が起きても、作者に対して文句、苦情、対応の要求、損害賠償その他いかなる請求も行わないことに同意したうえで使ってください。** 同意できない場合は使わないでください。
7. AI（生成 AI を含む）にこのリポジトリを渡して別の機種向けに改変・実行させた場合の結果も、すべて利用者の責任です。AI が出力した手順やコードは、実行前に必ず自分で内容を確認してください。
8. リリースで配布する `TclAutoRes.exe` には、コード署名がありません。Windows が警告を出すことがあります。不安な場合は使わず、`tools/Build-Exe.ps1` で同梱のソースから自分で作ってください。
9. 内容は予告なく変更・削除することがあります。サポートは行いません。

## English

1. Everything in this repository (code, example configuration, documents and findings) is a personal record of experiments on the author's own equipment. It is provided **"AS IS", without warranty of any kind**, express or implied, including correctness, safety, merchantability, fitness for a particular purpose, or that it works on other models or setups.
2. **The code, `TclAutoRes.exe` and documents in this repository were made with AI (generative AI such as Claude).** The author has not verified or fully understood all of it; it may contain errors, inaccurate explanations or unsafe behaviour. **It is published for reference only, not as a recommendation to use it as is. The author cannot take responsibility for it.**
3. It is not affiliated with, endorsed or supported by TCL, Google, Microsoft, NVIDIA, AMD, Intel, MediaTek or any other vendor. Trademarks belong to their owners.
4. The software uses the TV's developer features (ADB / network debugging) and automatically changes your PC's display mode, possibly to non-standard custom timings. This may **damage your TV, PC, GPU, cables or other hardware, leave you without a picture, lose settings or data, void your warranty, expose the TV to unauthorised access on your network, or cause any other direct or indirect loss.**
5. **You use it entirely at your own risk. The author accepts no liability whatsoever for any damage or loss to you or anyone else arising from the use of, or inability to use, this material (including the `TclAutoRes.exe` distributed in Releases).**
6. **By using it you agree not to make any complaint, demand or claim of any kind against the author for any failure, malfunction or damage.** If you do not agree, do not use it.
7. If you give this repository to an AI system to adapt or run it for another model, the outcome is also entirely your responsibility. Review any steps or code an AI produces before running them.
8. The `TclAutoRes.exe` distributed in Releases is not code-signed and Windows may warn about it. If in doubt, do not use it; build it yourself from the included source with `tools/Build-Exe.ps1`.
9. Content may change or be removed without notice. No support is provided.
