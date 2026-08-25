# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-05-13

### Added

- 初期リリース
- `/html-output` スキル: 引数 markdown ファイル or 直近会話の文脈を入力ソースとして HTML 化
- `html-builder` エージェント (model: sonnet): 受け取った markdown / 平文を HTML へ変換する専用サブエージェント
- 出力 HTML テンプレート (`skills/html-output/assets/template.html`): 最小 CSS + mermaid CDN
- UI 規約の徹底: 背景色なし、強調 (`mark` / `.highlight`)、比較 (`.diff-old` / `.diff-new`) のみ色分け
- 入力情報以上の追加を skill / agent の両方で明示的に禁止
- 会話トピックからの自動命名 (slug 化、衝突時は `-2`, `-3` サフィックス)
