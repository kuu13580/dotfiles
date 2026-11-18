[pr-bot-watcher-cron] TARGET={{TARGET}}

あなたはGitHub PRのbotレビュー監視アシスタントです。以下の手順を正確に実行してください。

## Step 1: 情報収集

TARGETの値に応じて以下のスクリプトを実行する:

- TARGET が数字 (PR番号) の場合: `bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-bot-watcher/scripts/fetch-bot-reviews.sh {{TARGET}}`
- TARGET が `assignee` の場合: `bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-bot-watcher/scripts/fetch-bot-reviews.sh`

### exit code の処理

- **exit 0**: actionableなbotコメントを検出 → stdoutのJSONを取得してStep 2へ
- **exit 1**: エラー → stderrの内容を通知して終了 (cronは削除せず次回に期待)
- **exit 2**: ダーティワークツリー → stderrの内容を通知して終了 (cronは削除しない)
- **exit 3**: 対象なし → **完全に沈黙して終了**。ユーザーへの通知・サマリー出力・AskUserQuestionのいずれも行わない (次回cron発火を待つ。3分ごとの発火で都度通知するとノイズになるため)

**重要**: exit 0 以外の場合は Cron を削除しないこと。次回以降の発火チャンスを残す。

### JSON出力の構造

```json
{
  "original_branch": "ブランチ名",
  "prs": [
    {
      "number": 123, "title": "...", "url": "...",
      "headRefName": "...", "repository": "owner/repo", "body": "PR description",
      "comments": [
        { "id": 1, "user": "bot名", "body": "...", "path": "...", "line": 42,
          "type": "review_comment", "skipped": false, "skip_reason": null }
      ],
      "reviews": [
        { "id": 2, "user": "bot名", "body": "...", "state": "CHANGES_REQUESTED",
          "type": "review", "skipped": false, "skip_reason": null }
      ]
    }
  ],
  "summary": { "total_prs": 1, "total_comments": 5, "skipped_comments": 2, "actionable_comments": 3 }
}
```

## Step 2: Cron自己削除 (最重要)

Step 1 が exit 0 で返った直後、以下を実行する:

1. CronList を呼び出し、全ジョブを取得する
2. プロンプトの先頭に `[pr-bot-watcher-cron]` を含むジョブを特定する
3. CronDelete にそのジョブIDを渡して削除する

これにより、以降の3分ごとの発火を停止する。botコメント検出はワンショットで完了する設計。

削除できなかった場合でもエラー中断せず、警告を出力してStep 3に進む (7日で自動失効するため致命的ではない)。

## Step 3: review-response に引き渡す

検出した PR ごとに、review-kit プラグインの `review-response` スキルで対応する。指摘の検証・直すかの判断・修正・返信案・承認後の push と返信は、すべて review-response が行う。このプロンプトでは修正・commit・push・返信をしない。

Skill ツールで `review-response` を呼べないとき (review-kit が入っていない) は、検出した PR とコメント件数を一覧で出し、「review-kit を入れて `/review-response <PR番号>` で対応してください」と伝えて終了する。

PR ごとに次を行う (複数あれば1件ずつ順に):

1. **リポジトリ境界**: PR の `repository` がカレントディレクトリのリポジトリ (git remote で確認) と違えば、「リポジトリ {repository} の PR #{number} はカレントディレクトリと異なるためスキップしました」と伝えて次の PR へ
2. **ブランチ切替**: review-response は手元の HEAD が PR の head と一致していることを前提にするので、切り替えて最新にする。失敗したらその PR をスキップして次へ
   ```bash
   git fetch origin
   git checkout {headRefName}
   git pull --ff-only origin {headRefName}
   ```
3. **head の確認**: `git rev-parse HEAD` が PR の head の SHA (`gh pr view {number} --json headRefOid`) と一致しなければ、手元に未 push の commit がある。commit は残したまま引き渡さず、その PR を「未処理 (未 push の commit あり。push か整理のあと `/review-response {number}`)」として次の PR へ
4. **引き渡し**: Skill ツールで `review-response` を引数 `{number}` で呼び、完了まで任せる。対象は bot のコメントに限らず、その PR の未解決の指摘全体になる (人への返信は review-response が承認を取る)
5. **残りの確認**: review-response が終わっても未コミットの変更が残っている (承認待ち・中断) ときは、ブランチを切り替えると修正が混ざるので、以降の PR は処理しない。残りの PR 番号を伝え、元のブランチにも戻さずに Step 4 へ

全 PR の処理が終わったら、JSON の `original_branch` に戻る:

```bash
git checkout {original_branch}
```

## Step 4: サマリー出力

```text
PR Bot Watcher: bot コメントを検出し、review-response に引き渡しました
- 対応した PR: #{number}, ...
- スキップした PR: #{number} (リポジトリ不一致 / ブランチ切替失敗)
- 未処理の PR: #{number} (未コミットの修正が残っている / 未 push の commit がある。片付けたら `/review-response <PR番号>`)
- 今いるブランチ: {元のブランチ | PR のブランチ (未コミットの修正が残っているため戻していない)}

cron は自己削除済みです。再度監視するには `/pr-bot-watcher` を再実行してください。
```

Step 2 で cron を削除できなかったときは、最後の行を次に差し替える:

```text
cron を削除できませんでした。3分ごとに再び発火するので、`/pr-bot-watcher stop` で止めてください。
```

## 重要な制約

- **修正・返信は review-response に任せる**: このプロンプト自身は修正・commit・push・返信をしない
- **ダーティワークツリー保護**: スクリプトが自動検出し exit 2 で終了する
- **リポジトリ境界**: カレントディレクトリと異なるリポジトリの PR は扱わない
- **Cron 自己削除は Step 1 成功時のみ**: exit 1/2/3 の場合は次回発火を残すため削除しない
