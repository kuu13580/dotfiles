# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.1] - 2026-07-07

### Fixed

- `scripts/setup-statusline.sh` / `scripts/statusline.py` の実行権限 (`+x`) が抜けており、SessionStart hook / statusline レンダリングが `Permission denied` で失敗していた問題を修正 (1.0.0 → 1.1.0 で mode が `100755` から `100644` に落ちていた)

### Changed

- `setup-statusline.sh` を `SessionStart` に加え `UserPromptSubmit` にも登録。プラグイン更新後にセッション再起動を待たず、次のプロンプト送信時に `settings.json` の statusline パスが自動更新される (差分がない時は早期 return するので overhead は無視できる)

## [1.1.0] - 2026-07-07

### Added

- 現在ブランチに紐づく PR 番号を OSC 8 ハイパーリンクで表示 (Cmd/Ctrl+Click で PR ページを開ける)
- `pr.review_state` に応じたレビュー状態アイコン (approved: 緑 ✓ / changes_requested: 赤 ✗ / pending: 黄 • / draft: dim •)

### Changed

- レイアウトを 2 行構成に変更: 1 行目はモデル名 + PR (識別情報)、2 行目は使用率 (ctx / 5h / 7d)。狭い端末での truncate を避け、カテゴリを視覚的に分離

## [1.0.0] - 2026-03-25

### Added

- 初期リリース
- スパークラインゲージによるコンテキストウィンドウ使用率の表示
- 5時間レートリミット使用率の表示（リセット時刻付き）
- 7日間レートリミット使用率の表示
- 使用率に応じたグラデーションカラー（緑→赤）
