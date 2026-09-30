# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.2] - 2026-09-30

### Fixed

- 自分が作った pending に 2 回目を投げると exit 6 で止まる (行番号の取り直し・【確認】の追加が不可能だった)。`post-pending-review.sh --append <review_id>` で ID が一致する pending にだけ追記する
- PR ブランチ上でも手元が古いと「チェックアウト済み」扱いで古いコードを検証していた。`HEAD` と PR の head の一致 (`head_matches`) で判定し、ずれていれば `gh pr checkout` で揃える
- 別リポジトリの PR で、カレントリポジトリの同番号 PR を checkout し得た。Step 3 で `same_repository` を最初に判定する
- 追加 commit の判定を committedDate から SHA ベースに変更。レビュー前に作られ後で push された commit を見逃していた。force push でレビュー時点の commit が消えた場合は `review_commit_found: false` を返す
- 自分の最新レビューを `reviews(author:, states:)` で取得。bot のレビューが多いと直近 N 件から漏れていた
- 規約ファイルをチェックアウト後に取り直す。別リポジトリの PR には手元の規約を渡さない
- フェーズB の diff 取得を `git fetch origin <branch>` 依存から外した (fork の PR で失敗していた)
- 非 ASCII のファイル名 (git の引用符付き 8 進エスケープ) を diff 解析で復元
- 解決済みスレッドと同趣旨でも、今のコードで再発していれば落とさない

## [0.4.1] - 2026-09-29

### Fixed

- GitHub 上で直接 Approve した場合に引き継ぎメモが残り、Approve 後の再レビューで決着済みの判断を読み込む問題。実行のたびに冒頭で `prune-review-memos.sh` が MERGED / CLOSED / 自分が APPROVED 済みの PR のメモを削除する

## [0.4.0] - 2026-09-25

### Added

- 引き継ぎメモ。フェーズA の最後に、変更の要点・各指摘の根拠・検証に使ったテスト本文・**閉じる条件**・投稿しなかった指摘だけを `~/.claude/pr-review/<owner>/<repo>/<N>.md` に残し、フェーズB はそこから始める。同じ worktree でレビューと修正確認のセッションが分かれても、PR の理解を作り直すトークンを使わない
  - 置き場を prepare-context の `~/.claude/contexts/` と分けたのは、あちらは git の共通ディレクトリ名とブランチ名をキーに SessionStart で自動読み込みするため。PR 単位のメモは GitHub の owner/repo をキーにし、明示的に読む
  - フェーズB では GitHub のスレッドを正とする。submit 前にユーザーが pending を編集・削除するため、メモにだけある指摘は扱わず、スレッドにだけある指摘は本文で判定する
  - 再レビューでは「投稿しなかった指摘」「仕様・設計の確認事項」に既にあるものを新規として出さない
  - フェーズB の終わりにメモを現状へ更新し、Approve まで済んだら削除する
- `fetch-pr-context.sh` / `fetch-review-threads.sh` が `review_memo: {path, exists}` を返す

## [0.3.0] - 2026-09-18

### Changed

- 系統3 (仕様・設計パス) の軸を「仕様書に書かれた要件との照合」から **「実装された仕様の妥当性」** に組み替え、4 観点に整理
  - `[妥当性]` コードからはこう実装されていると読めるが、事業・運用・アーキテクチャの観点でそれを決めてよいのか
  - `[要件担保]` 書かれた要件のうち壊れたら影響が大きいものが実装で閉じているか (「書かれているから通す」をしない)
  - `[エッジ]` 仕様書にも実装にも扱いが現れていない入力・状態 (考慮した結果なのか未考慮なのかが読み取れないもの)
  - `[アーキ]` 責務の置き場所・既存の抽象との重複・依存の向き・状態の持ち方
- 件数を「最大5件」から **「詳細3件 + その他1行×最大5件 (合計8件上限)」** に変更。PR が大きいと3件では取りこぼすため、詳細を絞って一覧は残す形にした
- レポートに観点ラベルを付与。多いと感じたときに軸単位で削れるようにした
- PR の説明にある仕様書・チケットの URL は読めるなら読む。読めない場合は参照不可として進め、その限界をレポートに明記する (読めた前提で書くと書かれていない要件を補ってしまうため)

## [0.2.0] - 2026-09-18

### Added

- 洗い出しに「仕様・設計パス」を追加 (系統3)。エラーケース / エッジケース (空・0件・上限超過・境界値・同時実行・権限なし・通信断) / 仕様の穴 / アーキテクチャ (責務の置き場所・既存の抽象との重複・依存の向き・状態の持ち方) を最大5件。コードベースの中では整合しているが判断が要る点は、既存の2系統では出てこないため専用パスにした
- 分類に【確認】を追加。検証で真偽が決まらないため既定では投稿せず、レポートの【仕様・設計の確認事項】に出してユーザーが選んだものだけ pending に加える (断定形で送ると実装者が反論に時間を使うため)
- `--explain` オプション。洗い出しの前に `explain-change` スキルで変更の解説 Artifact を作る。未導入の環境ではターミナルに5行以内の要約を出すだけに留める

### Changed

- 系統1・2 由来の指摘が「壊れる経路を示せず規約も引用できないが仕様として引っかかる」場合は、落とさず【確認】に移す
- フェーズB の追加 commit 再レビューでも【確認】を別枠で出す

## [0.1.0] - 2026-09-18

### Added

- 初期リリース
- `/pr-review [<PR番号> | <PR URL>] [--review | --verify] [medium|high|max]` で他人の PR のレビューを通す
- PR の状態 (自分の最新レビュー) からフェーズA (レビュー作成) / フェーズB (修正確認) を自動判定
- `scripts/list-review-prs.sh`: `review-requested:@me` はチーム経由の依頼も返すため `reviewRequests` の User 一致で個人指名だけに絞る。自分が CHANGES_REQUESTED を出した後に commit が積まれた PR を修正確認待ちとして別バケツで出す
- `scripts/fetch-pr-context.sh`: PR メタ・既存スレッド (重複判定用)・ローカルのブランチ/dirty 状態・規約ファイル候補・フェーズ判定材料を 1 クエリで取得
- `scripts/post-pending-review.sh`: GitHub は diff に無い行へのコメントを 422 で弾き 1 件でも不正だと全件落ちるため、投稿前に diff を解析して行番号を検証し除外する。`--dry-run` あり
- `scripts/fetch-review-threads.sh` / `resolve-threads.sh` / `reply-thread.sh`: 修正確認フェーズ用
- 分類は「規約ファイルの行を引用できるか」で【規約】/【不具合】を決め、引用できない好みは投稿しない
- 投稿対象は検証で裏が取れたものだけ。不成立 / 検証手段なし (実機確認候補) / 規約にない好み は投稿せずターミナルの別枠で報告
- 書き込み境界: pending 投稿は確認不要、submit は行わない、Resolve / 返信 / Approve はユーザーの承認後にのみ実行
