# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-04

### Added

- 初期リリース
- `/prepare-context <調査 | 設計 | 実装 | pr>` で引き継ぎ記録を書き出す・追記する (英語エイリアス `research` / `design` / `implement` / `pr` も受ける)
- 記録は `~/.claude/contexts/<repo>/<key>/` の2ファイル構成。`CONTEXT.md` (上限 400行 / 24KB、`SessionStart` で注入) と `CONTEXT.archive.md` (注入しない退避先)
- `scripts/resolve-key.sh`: 非 default branch は `<repo>/<branch>`、default branch は `git config --worktree prepare-context.key` の明示設定を要求。detached HEAD / 非 git は exit 1
- `scripts/load-record.sh` (`SessionStart`): キー未解決なら無音、記録が無ければ書き出しを促し、あれば全文を stdout で注入。上限超過時は archive への移動を促し (要約は禁止)、`source=compact` のときは圧縮サマリとの差分確認を促す
