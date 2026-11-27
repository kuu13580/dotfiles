# 状態から合うスキルを選ぶ

各スキルの冒頭で実行する (引数に PR があれば渡す):

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/detect-state.sh [<PR番号|PR URL>]
```

`suggested` が次の表を上から順に当てて選んだスキル、`reason` がその理由。PR の行は PR が OPEN のときだけ当てる (MERGED / CLOSED の PR は無いものとして下の行へ進む)。PR を特定できて OPEN なら、未コミットの変更よりも PR の状態を優先する。

| 状態 | スキル |
| --- | --- |
| 自分の PR に未解決の指摘がある (自分が立てたスレッドと、最後の発言が自分のスレッドは数えない。head の commit より後に出た変更要求は数える) | review-response (直したあと self-review も回す) |
| 自分の PR で、スレッドが多すぎて取り切れない | review-response |
| 自分の PR で、head の commit より後の人のレビュー本文・PR コメントに未返信のものがある (APPROVED・DISMISSED の本文は数えない。件数は `pr.open_review_bodies`) | review-response |
| 自分の PR で、未解決の指摘は無い | self-review (PR 全体を見直す) |
| 他人の PR に自分の未 submit の下書きレビューがある | check-review-validity |
| 他人の PR | pr-review |
| 未コミットの変更、または PR を出す前の自分のブランチ (PR が MERGED / CLOSED の場合を含む) | self-review |
| 自分宛のレビュー依頼・修正確認待ちがある | pr-review |

`review_requests_error` が入っているときは、依頼の一覧を取得できていない。「依頼なし」と言わず、そのエラーを伝える。

扱い:

- 次のときは `suggested` に関わらず、聞かずに今のスキルで進む
  - 実装の区切りで Claude が自分から self-review を実行したとき
  - 他のスキルから Skill ツールで呼ばれたとき (review-response が修正の見直しに self-review を呼ぶなど)
- `suggested` が今のスキルと同じ → そのまま進む
- 違う → `reason` を1行で示し、`suggested` への切り替えを推奨として AskUserQuestion で1回だけ提案する。断られたら今のスキルで進む (例: 自分の PR に未解決の指摘があるが、指摘と関係なく PR を見直したい)。ただし pr-review は自分の PR を対象にできないので、断られたら終了する
- 切り替えるときは、対象の PR が決まっていればその URL を引数として切り替え先に渡す (渡さないと、切り替え先がカレントブランチから別の PR を選ぶことがある)
- `suggested: null` → レビューする対象を聞く
- exit 1 → stderr を伝え、引数の対象で進められるならそのまま進む

## トークン量の記録

各スキルの最後の報告の直前に実行し、出た1行を報告の末尾 (pr-review は控え) に付ける。結果は `~/.claude/review-kit/usage.tsv` にも追記される:

```bash
python3 ${CLAUDE_PLUGIN_ROOT}/scripts/usage-report.py --log --skill <今のスキル名>
```

他のスキルから呼ばれたとき (review-response から self-review など) は実行しない。呼び出し元が `--skill` で自分の呼び出しからの区間を数えるので、呼ばれた側の分も含まれる。
