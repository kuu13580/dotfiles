# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-08

### Changed

- **記録の形式を規約から外した。**章立て・順序・表かプロースかはそのセッションが素材に合わせて決める。固定なのは置き場とファイル名 (フックが `CONTEXT.md` を名前で読む) と、冒頭のタスク一行説明だけ。規約が持つのは**何を残すかの判断基準**に絞った
  - v0.1.0 は3章をすべて表で固定し、雛形が決定の `理由` 欄を `<1行>` と指定していたため、**圧縮が追記時ではなく最初に書く時点で強制され**、「要約による圧縮は禁止」と正面から矛盾していた。手順・コード・エラー文・因果の連鎖はセルに入らず落ちる
- **潰した仮説を残す側へ移した** (仮説 + 潰した根拠のペア)。v0.1.0 は「調査の過程 (探索経路・棄却した仮説・ツール出力)」として一括除外していたが、「後続で再現不要」が成り立つのは調査が決着して結論が事実として残った場合だけ。除外は探索の経路とツール出力の生ログのみとした
- **未決着の調査の現在地** (症状・再現手順・次に見る場所) を残すものに追加。compact が最も走るのは長い調査の途中で、v0.1.0 の3章はすべて「確定したもの」の器だったため引き継げるものがゼロになる穴があった
- `CONTEXT.archive.md` の役目を**撤回・置き換えられたものの保管に限定**した。現役の根拠は移さない (注入されないため、移すと後続には失われたのと同じになる)。上限超過時は撤回済みから移し、それでも超える場合のみ現役の詳細も移せるが `CONTEXT.md` にポインタを残す

### Removed

- `skills/prepare-context/references/template.md`。形式を任せる方針と両立しない (雛形は埋める枠として機能してしまう)

## [0.1.0] - 2026-09-04

### Added

- 初期リリース
- `/prepare-context <調査 | 設計 | 実装 | pr>` で引き継ぎ記録を書き出す・追記する (英語エイリアス `research` / `design` / `implement` / `pr` も受ける)
- 記録は `~/.claude/contexts/<repo>/<key>/` の2ファイル構成。`CONTEXT.md` (上限 400行 / 24KB、`SessionStart` で注入) と `CONTEXT.archive.md` (注入しない退避先)
- `scripts/resolve-key.sh`: 非 default branch は `<repo>/<branch>`、default branch は `git config --worktree prepare-context.key` の明示設定を要求。detached HEAD / 非 git は exit 1
- `scripts/load-record.sh` (`SessionStart`): キー未解決なら無音、記録が無ければ書き出しを促し、あれば全文を stdout で注入。上限超過時は archive への移動を促し (要約は禁止)、`source=compact` のときは圧縮サマリとの差分確認を促す
