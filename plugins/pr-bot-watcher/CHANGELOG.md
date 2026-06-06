# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.2] - 2026-05-14

### Changed

- Step 3 判定ロジック 4 (PRサマリ・運用通知コメント) を独立カテゴリ **📢 サマリ・運用通知 (返信スキップ)** に分離。「✓ 修正不要」とは別扱いにし、Step 6 の返信対象から完全に除外 (従来は `auto_no_fix` 経由で「💭 修正不要」が返信されていた)
- 最終分類タグに `summary_no_reply` を追加 (Step 5 / Step 6 共に対象外、`boundary_skip` と同じ振る舞い)
- Step 4b の対象範囲を `auto_no_fix` 候補のみと明示。📢 は「覆して修正」の選択肢に出さない
- Step 4 末尾の Step 5/6 スキップ条件に `summary_no_reply` を追加
- Step 7 サマリーに 📢 カウント・`summary_no_reply` 分類を追記
- 同 bot が同時に付ける個別行コメント (`type: review_comment`) は引き続き修正対象 (既存仕様維持)

## [0.2.1] - 2026-04-24

### Changed

- Step 3 判定ロジック 4 番を **運用通知・PRサマリコメント** に拡張。Preview デプロイ URL 通知、Copilot の `## Pull request overview` / CodeRabbit `Summary by CodeRabbit` 等の PR 全体サマリレビュー本文も ✓ 修正不要 に分類
- 同 bot が付ける個別の行コメント (`type: review_comment`) は修正対象に残すため、除外はレビュー本文サマリ (`type: review`) のみと明記

## [0.2.0] - 2026-04-23

### Added

- **Step 6: bot コメントへの返信投稿** を新設。修正したコメントには「✅ 修正しました + commit SHA」、修正不要コメントには「💭 修正不要と判断した理由」を GitHub 上で返信する
  - 行コメントは `gh api .../pulls/{pr}/comments` with `in_reply_to` でスレッド返信
  - レビュー全体は `gh pr comment` で `@mention` 付きの PR issue コメント
  - 返信失敗は rate limit 等を想定し Step 7 サマリーに「返信投稿: 成功/失敗」として記録
- **Step 4 を 3 サブステップに再編**し、ユーザー判断を最終分類タグとして管理
  - 4a: 🔧 修正要 から実際に修正するコメントを選択 (既存)
  - 4b: ✓ 修正不要 を覆して修正したいコメントを選択 (新規)
  - 4c: 4a で外された 🔧 コメントの「修正しない理由」を定型選択肢 + Other で収集 (新規)
- 最終分類タグ `fixed_by_user_pick` / `auto_no_fix` / `skipped_by_user` / `boundary_skip` を導入し、Step 5 / 6 の対象選定・返信本文をタグで一貫制御
- Step 3 判定ロジックに **運用指示コメント** (squash 警告、CI 設定依頼等) の ✓ 修正不要 ルールを追加
- Step 5b に **`suggestion` ブロックの優先流用** ルールを追加

### Changed

- 旧 Step 6 (サマリー出力) を Step 7 にリナンバリング
- Step 7 のサマリー項目を分類タグ別カウントに組み替え (修正・push完了 / 中断 / auto_no_fix / skipped_by_user / boundary_skip / 返信成否)
- 重要な制約に「ユーザー判断の尊重 (skipped_by_user は必ず 4c で理由を聞き、Claude が勝手に理由を創作しない)」を明記

## [0.1.1] - 2026-04-23

### Fixed

- `scripts/fetch-bot-reviews.sh`: `gh pr view --json` で存在しない `repository` フィールドを指定していた問題を修正。`headRepository` / `headRepositoryOwner` を使うように変更
- `scripts/fetch-bot-reviews.sh`: jq の `null.foo` が空文字列扱いになる挙動を考慮し、`owner` / `name` を個別抽出して片方だけ null のケースも検知するように null ハンドリングを強化

## [0.1.0] - 2026-04-22

### Added

- 初期リリース
- `/pr-bot-watcher` スラッシュコマンドで 3 分間隔の cron ジョブを登録・停止
- 引数で PR 番号指定、省略時は会話ログ参照または自分アサイン PR を対象にする 3 種類の起動モード
- botレビューコメント検出時点で cron を自己削除するワンショット監視モデル
- 修正要否サマリ（🔧 修正要 / ✓ 修正不要 / ⚠ リポジトリ不一致スキップ）と理由付き判定
- AskUserQuestion による修正対象の複数選択、連続 Edit 後に `git diff` を一括確認して commit/push
