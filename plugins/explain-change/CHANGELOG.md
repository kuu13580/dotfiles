# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-10-21

### Changed

- 5 章構成の長文解説をやめ、「全体像 (3 行サマリ + 一枚絵) → 種類別の中段 → 動作確認すると良い点」の構成に変更。段落は各ブロック 2 文までにし、詳細はコードリンクに任せる
- 変更の種類 (リファクタリング / 不具合修正 / 新機能) を PR のタイプ欄・ラベル・コミット接頭辞から判定し、構成を変える
  - リファクタリング: 一枚絵は小さめ。挙動が変わる可能性のある箇所ごとに `変わる / 変わらない / 未確認` を判定し、変更前後のフローと根拠を示す。PR description の主張もコードで検証する
  - 不具合修正: 一枚絵で症状と処理経路を修正前後で比較し、再現条件 / 原因 / 修正をカードにする
  - 新機能: 一枚絵を画面構成図にし、追加 / 変更・削除 / 既存を塗り分ける
- 引数なしの対象を「未コミット変更を優先」から「カレントブランチの PR を優先」に変更。PR に未反映の手元の変更 (未 push のコミット・未コミット) は `local_changes` として足す。未追跡ファイルが 1 つ残っているだけで PR 全体ではなく未コミット分だけが対象になっていたため

- `disable-model-invocation` を外し、pr-review から Skill ツールで呼べるようにした。description で起動する場面を「解説を明示的に求められたとき / pr-review から」に絞る
- 報告に「動作確認すると良い点」を `path:line` と手順付きで含める (pr-review が取り込むため)

### Added

- `assets/base.css`: 全解説で共通のトークンと部品。色の意味を固定し、毎回同じ見た目にする。表の列に最小幅を設け、狭い場所で列が潰れてセルが縦に伸びるのを防ぐ
- `resolve-target.sh`: PR 対象のとき `code_links` (`blob_base` / `after` / `before`) を返す。コードリンクを commit 固定にし、変更前のコードにもリンクできるようにする

## [1.0.0] - 2026-08-26

### Added

- 初期リリース
- `/explain-change [<PR番号> | <PR URL> | <commit> | <A..B> | <ブランチ名>]` で変更の長文解説を Artifact として publish
- `scripts/resolve-target.sh`: 引数の形から worktree / pr / commit / range / branch を自動判別し、`diff_command` / `stat` / `files` / `commits` / `untracked` / PR description をまとめて JSON 出力
- 解説は 5 章構成 (この変更は何か / 背景 / 直感 / コードの歩き方 / 押さえどころ)。gist 由来の 3 章に「押さえどころ」を追加し、読後に行動が残る形にした
- 事実と推測の分離: 本文は一次情報から確かめられたことのみ断定で書き、動機の推測は根拠付きコールアウトに隔離
- 図は各章に最低 1 枚を要求し、型は 3-4 種に固定。インライン SVG (機構そのもの、`currentColor` で両テーマ対応) を第一候補に、mermaid (分岐の多いフロー / 依存グラフ) と HTML+CSS (before/after 対比 / 整列) を使い分ける。矢印にラベル、図に具体値、1 図 1 主張。ASCII 図は禁止
- exit code による分岐 (0=解決 / 1=エラー / 2=対象を特定できずユーザーに確認)。エラー経路はコマンド置換のサブシェル内で終了するため、呼び出し側で `|| exit $?` により伝播させる
- ブランチ対象は完全 ref に解決してから git に渡す (git は bare name を `refs/remotes/origin/*` に DWIM しないため、リモートのみのブランチが解決できない)
- `A...B` 指定時は log レンジを `merge-base..B` に揃える (`git diff` は merge-base 基準、`git log` は対称差なので、揃えないと files と commits が食い違う)
- `local_code` (`exact` / `contains` / `absent`) と `dirty_worktree` を返し、調査方法を決定。マージ済み PR は `contains` と判定して diff ベースへ不要に縮退しない (merge commit は HEAD の祖先、squash / rebase merge は `mergeCommit` 経由で判定)。手元に無い場合も checkout させず精度限定を明記して続行
- `diff_command` に埋め込む ref は `printf %q` でクォートする。git は ref 名に `$( )` / `` ` `` / `;` / `>` / `'` を許すため、生のまま連結すると SKILL.md が許可している「そのまま実行」でコマンド注入になる
- SHA 接頭辞と同名のブランチがあるときは exit 2 で確認を求め、全長 SHA か `refs/heads/<名前>` を案内する。git は refname を SHA より優先するため `<sha>^{commit}` では回避できない。候補は commit に peel できるものだけを見る (`--disambiguate` は blob / tree / tag も返すため、blob と衝突しただけのブランチ名を弾いてしまう)
- `gh pr diff --name-only` の失敗を exit 1 で伝播する (取得失敗を「変更ファイル 0 件」として扱わない)
