# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-11-10

### Added

- 返答中の mermaid を、端末は leaf の ASCII 図、Desktop / VS Code は mmdc の SVG で表示する。保存本文は書き換えない
- `/md [path]` で Markdown ファイルを pane に表示する。Write / Edit した .md への追従、1.5 秒ごとの更新検知、leaf 全面描画への切替
- 図にできない surface で返答に mermaid が出たとき、leaf / mermaid-cli の入れ方を toast で一度だけ知らせる
- 図にできる surface があるとき、mermaid を使ってよいことをシステムプロンプトに一節足す
