---
name: pr-bot-watcher
description: "GitHub PRに付いたbotレビューコメント(Copilot/Claude/Gemini等)を3分間隔で監視するワンショット型スキル。コメント検出時点でcronを自己削除しユーザーに修正要否を確認する。引数でPR番号指定、省略時は会話ログ参照かアサインPR。stopで停止。"
argument-hint: "[<PR番号> | start | stop]"
allowed-tools: Bash, Read, AskUserQuestion, CronCreate, CronList, CronDelete
disable-model-invocation: true
---

# PR Bot Watcher

GitHub PRのbotレビューコメント(Copilot, Claude, Gemini等)を**3分間隔**で監視し、**コメント検出時点でcronを自己削除**する**ワンショット型**スキル。検出後はユーザーに修正要否サマリを提示し、選択されたコメントを修正してcommit/pushする。

## 引数パース

ユーザー引数 `$ARGUMENTS` を以下のルールで解釈する:

- 引数が正の整数 → **開始フロー (PR番号指定モード)** へ (`TARGET=<PR番号>`)
- 引数 `stop` → **停止フロー** へ
- 引数なし or `start` → **開始フロー (ターゲット確認モード)** へ
- それ以外 → 「引数が不正です」と通知して終了

---

## 開始フロー (ターゲット確認モード)

引数なしで呼ばれた場合。

### Step A: 会話ログから PR 番号候補を抽出

直近の会話コンテキストを確認し、以下のパターンから PR 番号を推測する:

- `https://github.com/owner/repo/pull/<N>` 形式のURL
- `PR #<N>` または `#<N>` の言及
- 直前に作成されたPRの番号 (PR作成直後の流れ)

### Step B: AskUserQuestion でターゲットを確認

- 候補PR番号が見つかった場合、選択肢にその番号を含める
- 選択肢:
  - 「PR #{推測番号} を監視」(候補がある場合のみ、推奨として1番目)
  - 「別のPR番号を指定」(ユーザーにPR番号を別途入力してもらう)
  - 「自分アサインの全オープンPRを監視」

ユーザーが「別のPR番号を指定」を選んだ場合は、再度 AskUserQuestion ではなくテキストでの再実行を促す:
「`/pr-bot-watcher <PR番号>` で再実行してください」と通知して終了。

他の選択肢が選ばれたら、それぞれ:

- PR番号選択 → `TARGET=<番号>` で **開始フロー (共通部)** へ
- アサイン全部 → `TARGET=assignee` で **開始フロー (共通部)** へ

---

## 開始フロー (PR番号指定モード)

引数に正の整数が渡された場合。`TARGET=<引数>` として **開始フロー (共通部)** へ直接進む。

---

## 開始フロー (共通部)

### Step 1: 重複チェック

CronList を呼び出し、プロンプトに `[pr-bot-watcher-cron]` を含むジョブが存在するか確認する。
存在する場合は「既に pr-bot-watcher の cron ジョブが稼働中です。停止するには `/pr-bot-watcher stop` を実行してください。」と通知して終了する。

### Step 2: 認証チェック

```bash
gh auth status 2>&1
```

失敗した場合は「`gh auth login` を実行してください」と案内して終了する。

### Step 3: Cron プロンプト準備

Read ツールで `${CLAUDE_PLUGIN_ROOT}/skills/pr-bot-watcher/references/cron-prompt.md` を読み取り、
内容中の `{{TARGET}}` プレースホルダーを `TARGET` の実値 (PR番号 or `assignee`) に置換する。

### Step 4: Cron ジョブ登録

CronCreate を以下のパラメータで呼び出す:

- **cron**: `"*/3 * * * *"` (3分間隔)
- **recurring**: `true`
- **prompt**: Step 3 で準備したプロンプト文字列 (先頭に `[pr-bot-watcher-cron]` タグを含む)

### Step 5: ユーザー通知

以下を出力する:

```
pr-bot-watcher の cron ジョブを登録しました。
- 対象: {PR #<番号> | 自分アサインの全オープンPR}
- 間隔: 3分ごと
- 動作: botコメント検出時点で cron を自動削除します (ワンショット)
- セッション内でのみ有効、検出されなければ7日後に自動失効します

手動で停止するには `/pr-bot-watcher stop` を実行してください。
```

---

## 停止フロー

### Step 1: ジョブ検索

CronList を呼び出し、プロンプトに `[pr-bot-watcher-cron]` を含むジョブを検索する。

### Step 2: ジョブ削除

- 見つかった場合: CronDelete でジョブIDを指定して削除
- 見つからない場合: 「pr-bot-watcher の cron ジョブは現在稼働していません。」と通知

### Step 3: 完了通知

削除時: 「pr-bot-watcher の cron ジョブを停止しました。」と出力する。

---

## エラーハンドリング

| ケース                      | 対処                                                             |
| --------------------------- | ---------------------------------------------------------------- |
| gh 未認証                   | `gh auth status` で検知、ユーザーに通知して中断                 |
| 引数の PR 番号が不正        | 「引数は正の整数、`start`、`stop` のいずれかです」と通知して終了 |
| 既存 cron ジョブあり        | 重複起動を防ぎ、停止コマンドを案内                               |
| CronCreate 失敗             | エラー内容を出力して中断                                         |

---

## 設計上の注意

- **ワンショットモデル**: 検出時点で cron は自己削除される。継続監視が必要な場合は `review-fixer` プラグインを利用すること。
- **修正フローは cron 側で定義**: この SKILL.md は「起動・停止」のみを担当し、検出後の修正判定・Ask・修正・push は `references/cron-prompt.md` に記述されている。
- **3分間隔の負荷**: 毎回 `gh api` を叩くため、7日で最大 3,360 回のAPI呼び出しになる (実際は検出時点で停止)。
