# pr-bot-watcher

GitHub PRのbotレビューコメント (Copilot / Claude / Gemini 等) を **3分間隔** で監視するワンショット型スキル。コメント検出時点でcronを自己削除し、ユーザーに修正要否サマリを提示して、選択されたコメントのみ修正してcommit/pushする。

## 特徴

- **ワンショット監視**: 1回検出したら自動停止。継続監視したい場合は `review-fixer` プラグインを使用。
- **修正要否判定**: 各コメントについて「修正要/不要」を理由付きで判定して表示。
- **個別承認なし**: 選択されたコメントを連続で修正し、最後に1回だけ commit/push を確認。
- **PR指定柔軟**: 引数でPR番号指定、省略時は会話ログから推測 or 自分アサインPR全部から選択。

## 使い方

### 開始

```bash
# 特定PRを監視
/pr-bot-watcher 123

# 引数なし: 会話ログ/アサインから選択
/pr-bot-watcher
```

### 停止

```bash
/pr-bot-watcher stop
```

## 前提条件

- `gh` CLI がインストール済みかつ認証済み (`gh auth login`)
- `jq` がインストール済み
- 作業ツリーがクリーン (未コミットの変更がない状態)
- 対象PRのリポジトリがカレントディレクトリと一致すること

## フロー

1. `/pr-bot-watcher` 実行 → cron (3分間隔) 登録
2. 3分ごとに対象PRから bot コメントを取得
3. actionable なコメントを検出した時点で **cron 自己削除**
4. 各コメントに「修正要/不要」を理由付きで判定しサマリ表示
5. 「修正要」から選択する AskUserQuestion (multiSelect)
6. 選択コメントを連続で Edit (個別承認なし)
7. `git diff` を表示して1回だけ commit/push を確認
8. 承認されたら commit & push

## `review-fixer` との違い

| 観点             | review-fixer              | pr-bot-watcher            |
| ---------------- | ------------------------- | ------------------------- |
| 実行モデル       | 継続監視 (手動停止が必要) | ワンショット (自動停止)   |
| 間隔             | 30分                      | 3分                       |
| 対象PR           | 自分アサインのみ          | PR番号指定 or アサイン    |
| 修正要否判定     | なし (全て修正提案)       | あり (要/不要と理由を明記)|
| 個別承認         | 各コメントごとに確認      | 一括 (最後に1回)          |

短期集中で特定PRの bot レビューを片付けたいときは `pr-bot-watcher`、作業中のPR群を定期的に回したいときは `review-fixer`。

## ファイル構成

```
pr-bot-watcher/
├── .claude-plugin/
│   └── plugin.json
├── skills/
│   └── pr-bot-watcher/
│       ├── SKILL.md
│       ├── scripts/
│       │   └── fetch-bot-reviews.sh    # PR情報収集スクリプト
│       └── references/
│           └── cron-prompt.md          # cron実行時プロンプト
└── README.md
```

## セッション制約

- cron ジョブはClaude Codeセッション内でのみ有効
- 7日間検出されなかった場合は自動失効 (Claude Code の cron 仕様)
- セッション終了時にジョブは消える (`durable: false`)
