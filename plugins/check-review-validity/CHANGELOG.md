# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-11-18

### Changed

- 本体を review-kit プラグインに移した。このプラグインは `/check-review-validity` で呼ばれたときに review-kit の check-review-validity へ引き継ぐか、review-kit の導入を案内するだけにした

### Removed

- スキルの手順 (references) とスクリプト。review-kit 側にある

## [1.0.1] - 2026-11-16

### Changed

- 本文で指摘の対象として別の場所 (リンクや `path:line`) を示すコメント (diff 外の箇所を変更行から参照するもの) は、示された場所の今のコードを読み、置いた行の変更と結び付くかで判定する。diff ベースの判定で読めないときは `gh api` で PR の最新 commit から取得する。置いた行のファイルだけを読んで判定していたため

### Fixed

- ローカルのコードを読む判定 (`local_code_available`) を、ブランチ名の一致に加えて HEAD が PR の最新 commit と一致するときに限った。手元のブランチが古いと、古いコードで判定していた

## [1.0.0] - 2026-07-28

### Added

- 初期リリース
- `/check-review-validity [<PR番号> | <PR URL>]` で自分の未 submit ドラフトレビュー (GitHub の Pending review) を submit 前に検証
- `scripts/fetch-pending-review.sh`: GraphQL `reviews(states: PENDING)` からドラフトコメント・PR description・submit 済みレビュー・レビュースレッドを 1 クエリで取得し JSON 出力 (未 submit のドラフトは REST `pulls/comments` に現れないため GraphQL を使用)
- 判定 5 軸: 事実正しさ / プロジェクト規約との整合 / PR の文脈 (重複検出含む) / 伝わり方 / 外部事実の裏取り (WebSearch)
- 判定ラベル ✅ 妥当 / ✏️ 要修正 (文面案付き) / ❌ 取り下げ推奨 / ❓ 要確認
- 表サマリ + 詳細形式のレポート出力、末尾に見落とし候補を最大 3 件
- カレントブランチが PR の head と不一致の場合は `gh pr diff` ベースの判定に落とし、精度限定をレポートに明記
- exit code による分岐 (0=検出 / 1=エラー / 3=ドラフトなし / 4=PR 特定失敗)
- GitHub の `reviewThreads` は自分の未 submit コメントも返すため、重複検出を誤らせないよう ID 照合で `other_threads` から除外
