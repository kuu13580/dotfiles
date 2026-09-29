---
name: rebase-with-context
description: "rebase のコンフリクトを、両側 (base 側で該当行を変更した PR / 適用中の自分のコミットと PR) の文脈を読んだ上で解消する。PR・コミットに引用できる根拠がある箇所だけ自動で解消して完了後にサマリで報告し、根拠のない箇所は承認モードにかかわらず必ずユーザーに確認する。引数で rebase 先を指定、省略時は分岐元 (PR の base → reflog → 追跡先) を推定。"
argument-hint: "[<base>]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, AskUserQuestion
disable-model-invocation: true
---

# Rebase With Context

rebase で最も高くつくのは、**文脈を知らずに片側を選び、それが rebase 後に誰にも気づかれないこと**だ。コンフリクトマーカーの両側はどちらも「誰かが意図して書いたコード」であり、その意図は PR 本文・コミットメッセージ・レビュースレッドに残っている。このスキルはそれを読んでから解消する。

判断の非対称性を常に意識する: **確認を1回挟むコストは小さく、誤った自動解消のコストは大きい**。迷ったら確認に倒す。

## 絶対に守ること

- **要確認の hunk は、承認モード (bypass / auto 含む) にかかわらず AskUserQuestion で確認する。**自己判断で解消しない
- rebase 系の操作は必ず `rebase-step.sh` を通す。`git rebase` を直接叩かない (rerere の無効化・backup・マーカー検査が抜ける)
- push しない。PR へのコメント投稿もしない
- stash しない (worktree 間で共有される)。サブエージェントを使わない (AskUserQuestion は本体からしか出せない)

## Step 1: 準備

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/prepare.sh $ARGUMENTS
```

| exit | 意味 | 対応 |
| --- | --- | --- |
| 0 | 決定 (stdout に JSON) | `mode` で分岐 |
| 1 | エラー | stderr をそのまま伝えて終了 |
| 2 | base を推定できない | `candidates` を選択肢に AskUserQuestion で rebase 先を確認し、選ばれた値を引数に prepare.sh を再実行 |
| 3 | 未コミット変更あり | stderr をそのまま伝えて終了。勝手に退避しない |
| 4 | detached HEAD | stderr をそのまま伝えて終了 |

### `mode: "new"`

1 行で宣言してから開始する: `feature/x → origin/shared-feature (推定元: PR の base) / 自分のコミット 5 件・base 側の新着 12 件`

- `sources_disagree: true` なら、PR の base を採用したことと reflog の値を併記する
- `intermediate_branches` が空でなければ「途中を指している <branch> は動かしません」と 1 行警告する (`--update-refs` は使わない)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/rebase-step.sh start <base>
```

### `mode: "resume"` (rebase 途中で呼ばれた)

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/rebase-step.sh adopt
```

`unmerged_without_markers` のファイルは、rerere が過去の解消を当てたか、ユーザーが手で直して未 `git add` のもの。ファイルごとに AskUserQuestion で確認する:

- **手で直したもの** → そのまま `git add`
- **分析し直す** → `git checkout -m -- <file>` でマーカー付きに戻してから Step 2 へ

前回「手で直す」で止めた続きなら、状態ファイルの判断記録はそのまま残っているので最終サマリに合流する。

## Step 2: 停止ごとのループ

`rebase-step.sh` の出力 `status` で分岐する。

| status | 対応 |
| --- | --- |
| `conflict` | 下記の分析 → 解消 → `rebase-step.sh continue` |
| `stopped` | 未解消ファイルの無い停止。再開直後 (ユーザーが手で直して `git add` 済み) なら `rebase-step.sh continue`。解消の結果コミットが空になった場合は `rebase-step.sh skip` (消えたコミットは finish が拾う)。それ以外は `git_output` を伝えて確認 |
| `blocked` | continue 前の検査で止めた (未 `git add` / マーカー残存)。`reason` を直して再度 continue |
| `done` | Step 3 へ |

### 2-1. 文脈を集める

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/collect-context.sh
```

JSON の主なフィールド:

- `files[].hunks[]`: `marker_lines` (作業ツリーのマーカー位置)、`head_lines` (HEAD 側の内容が HEAD のファイルの何行目か)、`head_commits` (その範囲を merge-base 以降に触ったコミット)
- `files[].head_commits`: マーカーが無いコンフリクト (modify/delete 等) のファイル単位の変更コミット
- `commits[sha].side`: `upstream` = base に入ったコミット / `own` = この rebase で先に適用した自分のコミット
- `prs[n]`: 本文・closing issue・**コンフリクトしたファイルに付いた**レビュースレッド
- `replay`: 適用中の自分のコミット。`own_pr`: 自分のブランチの PR
- `github_repo: null` なら PR は引けていない。**コミットメッセージしか根拠が無いので、要確認側に倒す**

### 2-2. hunk を読む

各 hunk について、マーカー部分だけでなく以下を読む:

- 作業ツリーのファイル (hunk の前後、関数全体)
- 共通祖先: `git show :1:<path>`、HEAD 側: `git show :2:<path>`、replay 側: `git show :3:<path>`
- replay 側の意図: `git show <replay.commit>`

**同じコミット内の hunk はまとめて見る。**同じ関数の複数箇所・呼び出し元と定義のように関連する hunk は、1 つの判断として扱う。

### 2-3. 3 分類

| 分類 | 条件 | 動作 |
| --- | --- | --- |
| **機械的解消** | 両側の変更が意味的に独立 (import 追加同士、隣接行の別変更、フォーマットのみ) | 両方取り込む。**サマリに載せない** |
| **文脈で判断** | PR 本文・コミットメッセージ・レビュースレッドに、片側を正とする**引用できる根拠**がある | 解消し、根拠を判断記録に残す |
| **要確認** | 上記以外すべて | AskUserQuestion |

「文脈で判断」に入れてよいのは、根拠を**原文から引用できる**場合だけ。例:

- base 側 PR「`fooApi` を廃止し `barApi` に統一」→ 自分側が `fooApi` を使っている → 自分の変更を `barApi` 側へ移植する
- レビュースレッドで「ここは null 許容にする」と決着している → その決定に沿う側を採る

以下は根拠にならない。**要確認に落とす**:

- 「コードを読むとたぶんこっちが新しい」「こっちのほうが良い実装に見える」という推論
- 両側が同じ値・同じロジックを別方向に変えている (例: `TIMEOUT = 20` と `TIMEOUT = 15`) のに、どちらの PR も理由を書いていない
- 仕様判断を含む (どちらの挙動が正しいかがプロダクトの判断になる)

### 2-4. 特殊なコンフリクト

| ケース | 扱い |
| --- | --- |
| modify/delete (`DU` / `UD`) | 削除側の PR・コミットに「移動」「廃止」の記述があれば移動先へ変更を移植 (文脈判断)。記述がなければ要確認 |
| rename | git が追跡できていればそのまま。できていなければ modify/delete と同じ |
| lockfile (`package-lock.json` 等) | base 側を採用し、自分側で追加した依存があれば再生成 (`npm install --package-lock-only` 等)。機械的解消 |
| 自動生成ファイル | 生成元を解消してから再生成。再生成コマンドが分からなければ要確認 |
| バイナリ | 常に要確認 |

### 2-5. 要確認をまとめて聞く

1 コミット分の hunk を全部分類してから、要確認分を AskUserQuestion でまとめて聞く (1 回最大 4 問、超えたら複数回)。前のコミットの解消結果が次のコンフリクトに影響するので、コミットを跨いで先に聞かない。

各問の選択肢:

| 選択肢 | preview に出すもの |
| --- | --- |
| HEAD 側 (base) | HEAD 側のコード + 根拠 PR の要点 (番号・タイトル・関係する一文) |
| replay 側 (自分) | replay 側のコード + 自分のコミット / PR の要点 |
| 統合案 | **具体的な解消後のコード** (説明だけで選ばせない) |
| 手で直す | 止めた後の手順 |

- 「手で直す」→ そのコミットで止める。rebase は進行中のまま残し、「編集して `git add` したら再度 `/rebase-with-context` を実行してください」と伝えて終了する
- Other で中断を指示された → `bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/rebase-step.sh abort` し、出力の `restore` を案内する

### 2-6. 解消して記録する

解消したら `git add` (削除は `git rm`)。文脈判断とユーザー判断は、continue の前に 1 件 1 行で記録する:

```bash
jq -nc --arg file a.ts --argjson line 42 --arg adopted "base 側 (#123)" \
  --arg evidence "#123「fooApi を廃止し barApi に統一」→ 自分側の呼び出しを barApi へ移植" \
  '{kind: "context", file: $file, line: $line, adopted: $adopted, evidence: $evidence}' \
  >> "$(git rev-parse --path-format=absolute --git-path rebase-with-context)/decisions.jsonl"
```

- `kind`: `context` (文脈で判断) / `user` (ユーザー判断)。`user` は `evidence` の代わりに `commit` (適用中コミットの短縮 SHA)
- 機械的解消は記録しない

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/rebase-step.sh continue
```

## Step 3: 検証 (rebase 完了後に 1 回)

リポジトリの `CLAUDE.md`・`package.json` の scripts・`Makefile` 等から build / typecheck / test のコマンドを特定して実行する。テキスト上のコンフリクトが無くても、base 側のリネームを自分のコミットが旧名で呼んでいる、といった壊れ方はここでしか見つからない。

- 失敗しても**自動で直さない**。原因と思われるコミット / PR を添えて報告し、修正方針を確認する (直すとしても rebase とは別のコミットになるため)
- コマンドが特定できなければ実行せず、サマリに「未検証」と書く

## Step 4: 後始末とサマリ

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/rebase-with-context/scripts/rebase-step.sh finish
```

判断記録 (`decisions`)・消えたコミット (`dropped_commits`)・戻し方 (`restore`) を出力し、backup ref と状態ファイルを削除する。この出力からサマリを組む:

```markdown
## rebase 完了: feature/x → origin/shared-feature (5 commits)

### 文脈で判断した箇所
| ファイル | 採用 | 根拠 |
| --- | --- | --- |
| src/a.ts:42 | base 側 (#123) | #123「fooApi を廃止し barApi に統一」→ 自分側の呼び出しを barApi へ移植 |

### ユーザー判断した箇所
- src/c.ts:88 → 統合案 (abc1234)

### 取り込み済みのため消えたコミット
- def5678 fix: shared を追加

### 検証
- build ✅ / test ✅

### 次の操作
git push --force-with-lease
(元に戻す: git reset --hard <orig_head>)
```

該当が無い節は省く。
