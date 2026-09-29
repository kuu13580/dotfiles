# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-29

### Added

- 初期リリース
- `/rebase-with-context [<base>]`。省略時は分岐元を PR の base → reflog の作成元 → 追跡先の順で推定し、取れなければ候補を出して確認
- `scripts/prepare.sh`: 新規 / 途中引き継ぎの判定と base の決定 (read-only)。rerere が当たった「マーカーなしの unmerged」も検出
- `scripts/rebase-step.sh`: start / adopt / continue / skip / status / abort / finish。rerere を毎回無効化し、backup ref (完了時に削除、abort 時は残す)・判断記録・continue 前のマーカー検査を担う
- `scripts/collect-context.sh`: hunk の HEAD 側の行範囲を `git log -L` で辿って変更コミットを特定し、コミット → PR (本文・closing issue・コンフリクトしたファイルのレビュースレッド) を JSON 化
- hunk を 機械的解消 (報告なし) / 文脈で判断 (引用できる根拠がある場合のみ、サマリ報告) / 要確認 (承認モードにかかわらず確認) に分類
