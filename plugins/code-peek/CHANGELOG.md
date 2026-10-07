# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-07

### Added

- `/peek` (引数なし) で直近 3 回の返答に出てきた `path:line` を pane に一覧表示し、ボタンで選んで開く。リンクのクリックが届かない通常表示の端末でも使える。pane を開いたままにすると返答のたびに一覧が更新される
- コード表示のヘッダーに「← 一覧」ボタン

### Fixed

- 行番号のないパスが開けなかった。`/` を含むパス (`src/app/api.ts`) と、拡張子が許可リストにあるファイル名 (`tsconfig.json`) は、バッククォートの有無にかかわらずリンク・一覧・`/peek` の対象にし、ファイルの先頭から開く
- 絶対パスの参照や、チャット内のリンク (端末が `file:///...` に解決して渡す) から開くと、ヘッダーが絶対パスになっていた。リポジトリ内のファイルはルートからの相対パスで表示する

## [0.1.0] - 2026-10-07

### Added

- 返答中の `path:line` / `path:10-20` / `path#L10-L20` をクリックするとファイルを pane に開き、対象行を中央に表示する。最上段に相対パスのヘッダーを固定する (fullscreen 表示の端末のみ)
- ファイル名だけの参照を `git ls-files` から解決し、複数候補は行数と変更ファイルで絞り込む
- `/peek <path>:<line>[-<end>]` コマンド
