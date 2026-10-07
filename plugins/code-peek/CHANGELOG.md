# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-10-07

### Added

- 返答中の `path:line` / `path:10-20` / `path#L10-L20` をクリックするとファイルを pane に開き、対象行を中央に表示する。最上段に相対パスのヘッダーを固定する (fullscreen 表示の端末のみ)
- ファイル名だけの参照を `git ls-files` から解決し、複数候補は行数と変更ファイルで絞り込む
- `/peek <path>:<line>[-<end>]` コマンド
