# pr-bot-watcher

GitHub PRのbotレビューコメント (Copilot / Claude / Gemini 等) を **3分間隔** で監視するワンショット型スキル。コメント検出時点でcronを自己削除し、[review-kit](../review-kit/README.md) の `review-response` に対応を引き渡す (検証・直すかの判断・修正・返信案・承認後の push と返信はそちらで行う)。

## 特徴

- **ワンショット監視**: 1回検出したら自動停止。継続監視したい場合は `review-fixer` プラグインを使用。
- **対応は review-response**: 検出後は PR のブランチに切り替えて review-response を呼ぶ。対象はその PR の未解決の指摘全体 (人の指摘を含む)。
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
- review-kit プラグイン (無いときは検出結果を伝えるだけで終わる)

## フロー

1. `/pr-bot-watcher` 実行 → cron (3分間隔) 登録
2. 3分ごとに対象PRから bot コメントを取得
3. actionable なコメントを検出した時点で **cron 自己削除**
4. PR のブランチに切り替えて review-response を呼ぶ (PR が複数なら1件ずつ。未 push の commit がある PR は未処理として報告する)
5. 全 PR が終わったら元のブランチに戻る (未コミットの修正が残っていれば、戻さずに残りの PR を伝える)

## `review-fixer` との違い

| 観点             | review-fixer              | pr-bot-watcher            |
| ---------------- | ------------------------- | ------------------------- |
| 実行モデル       | 継続監視 (手動停止が必要) | ワンショット (自動停止)   |
| 間隔             | 30分                      | 3分                       |
| 対象PR           | 自分アサインのみ          | PR番号指定 or アサイン    |
| 修正要否判定     | なし (全て修正提案)       | review-response の検証と3軸の議論 |
| 承認             | 各コメントごとに確認      | review-response の返信案と push をまとめて承認 |

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
