---
name: review-response
description: "自分が作者の PR に来たレビュー指摘 (人・bot) に対応する。各指摘を検証し、3軸 (正しさ / 仕様・使う人 / 保守・構造) で直すかを決めて直し、対応・見送りすべての返信案を出し、承認後に push・返信・指摘した人だけへの再レビュー依頼まで行う。「レビューの指摘に対応して」「PR のコメントを直して」「指摘に返信して」「bot (Copilot / CodeRabbit など) の指摘を見て」で発動し、pr-bot-watcher が bot コメントを検出したあとにも呼ばれる。他人の PR のレビューや自分が出した指摘の修正確認 (pr-review)、自分の下書きレビューの検証 (check-review-validity) には使わない。引数は PR 番号か URL、省略するとカレントブランチの PR。"
argument-hint: "[<PR番号> | <PR URL>]"
---

# Review Response

自分の PR に来た指摘を **検証する → 3軸で議論する → 直す → 返信案を出す → 承認後に push・返信・再レビュー依頼** の順で回す。洗い出しはしない (指摘はもう来ている)。判断の基準は `${CLAUDE_PLUGIN_ROOT}/references/principles.md` (以下「原則」)。`${CLAUDE_PLUGIN_ROOT}` が未設定のときは、このスキル専用のスクリプトは base directory 直下の `scripts/`、プラグイン共通のものは base directory から `../../references/` と `../../scripts/` を使う。

ユーザーの CLAUDE.md に修正・返信・確認の仕方のルールがあれば、そちらを優先する。

## Step 1: 合うスキルか確かめる

`${CLAUDE_PLUGIN_ROOT}/references/routing.md` の手順で `detect-state.sh` を実行し、扱いに従う。

## Step 2: 指摘を取る

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/review-response/scripts/fetch-pr-feedback.sh [<PR番号|URL>]
```

| exit | 意味 |
| --- | --- |
| 0 | JSON 出力 |
| 1 | エラー (stderr を伝えて終了) |
| 3 | 未解決の指摘が無い (伝えて終了) |
| 4 | カレントブランチから PR を特定できない (PR 番号の指定を促す) |

- `threads`: 未解決のスレッド。`last_by_me: true` は返信済みで相手の反応待ちなので対象から外す
- `review_bodies` / `pr_comments`: レビュー本文と PR へのコメント。`answered: true` (元の URL を含む返信を自分が PR コメントしている) は対応済みとして外す。bot の要約・CI の結果報告など、対応を求めていないものも外す
- `body_file` がある本文は長いので途中で切ってある。全文はそのファイルにある (bot のレビュー本文には、行コメントにしなかった軽微な指摘がまとめて入っていることが多い)
- スレッドの `comments_truncated: true` は会話が 50 件を超えて途中が欠けている。最新の発言は `last_comment` にある
- `threads_truncated: true` ならスレッドが 100 件を超えて取り切れていない。その旨を報告に書く (この場合は exit 3 にならない)
- `human_reviewed`: 人のレビューが既にあるか (Step 7 のコミットの仕方で使う)
- `pr.is_mine: false` なら自分の PR ではない。pr-review への切り替えを提案して止まる

次のときは、そのまま進めず状態を伝えて相談する。修正と一緒にコミット・push してしまうのを防ぐため。

- 手元の HEAD (`git rev-parse HEAD`) が `pr.head_oid` と違う (未 push の commit がある、別ブランチにいる)
- 今のブランチ名が `pr.head` と違う (同じ commit を指す別ブランチにいる。push 先を取り違えるため)

Step 7 の push に失敗して再開するときは、HEAD が `pr.head_oid` より先にあるのが正しい状態なので、この確認をせず push から再開する。
- 未コミットの変更がある

## Step 3: 指摘を検証する

各指摘を次に分ける:

| 種類 | 扱い |
| --- | --- |
| 指摘 (直すことを求めている) | 原則 §3 で高 / 中 / 取り下げに分ける。取り下げは否定する行を引用する。PR の説明に「意図的」「既知」「別 PR で対応」と書かれている指摘は、その記述を根拠に見送りの候補にする |
| 質問 | コードを読んで答えを用意する。答えから直す必要が分かれば指摘として扱う |
| 承認・感想・要約 | 対応しない (bot の要約・CI 報告を含む) |

同じ趣旨の指摘が複数 (人と bot など) あれば束ねて1件にし、返信は全スレッドに出す。

## Step 4: 3軸で議論して決める

原則 §4・§5 に従い、高・中の各件を「直す / 直さない / ユーザーに委ねる」に決める。

ユーザーに委ねるものと、設計判断が要るもの (意図や方針を決めないと直し方が決まらないもの) は、原則 §5 の聞き方で AskUserQuestion を使って聞く。設計判断が要るものは1件ずつ聞く。

## Step 5: 直す

- 「直す」に決まったものと、ユーザーが直すと決めたものを直す。修正はコミットせず working tree に残す
- 指摘に `` ```suggestion `` ブロックがあれば、それを直し方の第一候補にする (指摘者の意図に沿い、差分も小さくなる)
- 直したら Skill ツールで `self-review` を呼び、修正の差分を見直す
- 「直さない」と取り下げは触らない

## Step 6: 返信案を出す

対応したもの・見送ったもの・取り下げたもの **すべて** に返信案を書き、まとめて提示する。

```
## PR #<N> 指摘への対応 (<n>件)

| # | 相手 | 場所 | 対応 | 返信案 |
|---|---|---|---|---|
| 1 | <login> (bot) | `path:line` | 直した | 修正しました。<何をどう直したか1行> |
| 2 | <login> | `path:line` | 見送り | <理由1行>。<別 PR で対応する場合はその旨> |
| 3 | <login> | `path:line` | 取り下げ | <否定する行を示して、起きない理由> |

コミット: <追加 commit | amend> / push 後に返信 → 再レビュー依頼: <login>, <login>
少数意見: <あれば1行ずつ>
```

- 返信は相手の言語に合わせる。見送り・取り下げは責める書き方をせず、根拠の行かコードの事実を示す
- 修正した返信には、push 後に commit の短縮ハッシュを添える

## Step 7: 承認を得て、コミット・push・返信・再レビュー依頼

ユーザーが返信案と push を承認するまで、コミット・push・返信をしない。bot への返信の文面は、push の承認に含めて個別の承認を要らないものとする。承認されたら次の順に行う:

1. **コミット**: `human_reviewed: true` (人のレビュー済み) なら追加 commit。未レビューなら amend / fixup してよい。コミットメッセージはリポジトリの慣例に合わせる
2. **push**: push 先は PR の head を明示する (`git push <remote> HEAD:<pr.head>`。`<remote>` は `pr.head_repo` を指す remote)。amend した場合だけ `--force-with-lease`。push に失敗したら返信はせず、作った commit と残りの手順 (push・返信・再レビュー依頼) を伝えて止まる。再開するときは commit を作り直さず push からやり直す
3. **返信**: スレッドには `bash ${CLAUDE_PLUGIN_ROOT}/scripts/reply-thread.sh <PR> <reply_to_comment_id> <本文ファイル>`。レビュー本文と PR コメントへの返信は `gh pr comment <PR> --body-file <本文ファイル>` で、冒頭に相手と元の指摘の URL (`url`) と要約を書く (次回の取得で、URL を含む返信がある指摘を対応済みとみなすため)
4. **再レビュー依頼**: 依頼の直前に `gh pr view <PR> --json reviews,reviewRequests` で最新の状態を取り直す。今回対応した指摘を出した人 (bot を除く) のうち、最新のレビューが APPROVED の人を外して `gh pr edit <PR> --add-reviewer <login>,...` で依頼する。記録上の「再レビュー待ち」は古い可能性があるため根拠にしない

## Step 8: 報告する

依頼した相手を名前で書く。ユーザーに委ねたまま保留になったもの、返信していない指摘があれば先頭に置く。末尾にトークン量の1行を付ける (routing.md の「トークン量の記録」)。
