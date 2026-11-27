---
name: pr-review
description: "他人の PR をレビューする。自分宛 (個人指名) のレビュー依頼の選択、3軸 (正しさ / 仕様・使う人 / 保守・構造) と追加観点での洗い出し、テストによる検証、3軸の議論で決めた重さを文面に出した pending コメントの投稿、修正後の対応確認・Resolve・Approve までを通す。submit はせず、Approve・返信・Resolve はユーザーの承認後にのみ行う。「PR #123 をレビューして」「レビュー依頼を見て」「修正されたか確認して」などの依頼で発動する。引数で PR 番号か URL、省略時は自分宛の依頼一覧から選ぶ。自分の PR の見直しや、自分の PR に来た指摘への対応には使わない。"
argument-hint: "[<PR番号> | <PR URL>] [--review | --verify] [--no-explain] [medium | high | xhigh | max] [+security | +behavior | +ui | +migration | +test | +failure | +destructive]"
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Skill, Artifact, AskUserQuestion, SendMessage
---

# PR Review

他人の PR を **指摘を出す (フェーズA)** → **修正を確認して閉じる (フェーズB)** の 2 段で回す。洗い出し・検証・3軸の議論の基準は `${CLAUDE_PLUGIN_ROOT}/references/principles.md` (以下「原則」) にある。

レビューの本当のコストは、実装者が「それは違います」と返すために使う時間だ。成立しない指摘を 1 件混ぜるだけでレビュー全体の信頼が落ち、以降の正しい指摘まで軽く扱われる。だからこのスキルは **量ではなく、裏が取れているかどうか** で投稿を決める。

## 一貫して守ること

**1. 相手に届けるのは検証できたもの (確度: 高) だけ。**
「たぶん落ちる」は指摘ではなく仮説 (確度: 中)。テストを書いて再現するか、コードを追って到達経路を確定させるまでは投稿しない。確定していないもの (確度: 中、仕様・設計の判断が要るもの、3軸が割れたもの) は断定せず、`【確認/<重要度>】` の問いとして pending に置く。diff 外を指すものは、きっかけの変更行に `【参照・diff外】<本当の場所>` を添えて置く。取り下げは否定する行を引用できたものだけで、件数だけを報告する。この 3 つ (高 / 中 / 取り下げ) を混ぜないことが、このスキルで一番効く。

**2. 【不具合】と【規約】を分け、重さを文面に出す。**
受け取る側は「動かないから直すもの」と「このリポジトリの決めごとだから直すもの」で対応の重さが変わる。判定は主観を挟まず **規約ファイルの該当行を引用できるか** で決める。引用できれば【規約】、できなければ【不具合】。どちらでもない (規約に書いていない好み) は投稿しない。保守・構造の整理系 (再利用・簡素化など) は、具体的なコストを示せるものだけ【改善】として出す。【不具合】と【改善】は3軸の議論の結論を、直すかではなく指摘の重さ (必須 / 任意 / 別 PR でよい) として文面に出す。

**3. 確認が要るものはすべて pending に置き、そのまま送れる文面にする。**
ユーザーはターミナルの報告を基本的に読まず、pending だけを確かめる前提で動く。ユーザーに見てほしいもの (仕様・設計の確認、確定していない不具合の疑い、重さを決められない指摘、動作確認) は、すべて pending に置く。ユーザーは pending を直さずに submit することが多いので、目印を外す・文面を直すといった手直しを前提にしない。`【確認/major】` のように重要度を付けるのは、相手に送っても温度感が伝わるのでよい。ターミナルには、見なくてよいもの (件数・minor・取り下げ・少数意見) だけを出す。

**4. ユーザーが目を通していない文言を送らない。**
pending review は本人にしか見えないので、投稿は確認なしでよい。一方 **submit / Approve / 返信 / Resolve は相手に届く**ので、必ず内容を見せて承認を得てから実行する。ユーザーが承認したら、そこは遠慮せず実行してよい。

**5. ターミナル出力は短く、見なくてよいものだけにする。**
判断が要るものは 3 のとおり pending にあるので、ターミナルは件数と、pending に置かなかったものの控えに留める。場所は常にリポジトリ相対の `path:line` で書く。

## 引数の解釈

`$ARGUMENTS` を空白区切りで解釈する (順不同):

| トークン | 意味 |
| --- | --- |
| なし | 自分宛のレビュー依頼一覧から選ぶ |
| 正の整数 | カレントリポジトリのその PR |
| `https://github.com/<owner>/<repo>/pull/<N>` | その PR (別リポジトリ可) |
| `--review` | フェーズA を強制 |
| `--verify` | フェーズB を強制 |
| `--no-explain` | フェーズA の洗い出し前に作る変更の解説を省略する |
| `medium` / `high` / `xhigh` / `max` | `/code-review` の effort level (既定 `high`)。`max` のときだけ漏れ探しをする |
| `+<観点>` | 原則 §1 の追加観点を足す |

以降のスクリプトは `${CLAUDE_PLUGIN_ROOT}/skills/pr-review/scripts/` にある。`${CLAUDE_PLUGIN_ROOT}` が未設定のとき (マーケットプレイス未反映の検証中など) は、このスキルの base directory 直下の `scripts/` を使い、プラグイン共通のものは base directory から `../../references/` と `../../scripts/` を使う。

## Step 0: 役目を終えたメモを片付ける

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-review/scripts/prune-review-memos.sh
```

MERGED / CLOSED の PR と、自分が APPROVED 済みの PR の引き継ぎメモを削除する (GitHub 上で直接 Approve した場合も拾う)。`pruned:` 行があれば 1 行で伝え、`skip:` (PR を取得できなかった) はパスを添えて手動削除を案内する。exit 1 以外は続行する。

## Step 1: 対象 PR を決める

引数で PR が指定されていればそれを使う。指定がなければ:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-review/scripts/list-review-prs.sh
```

| exit | 意味 |
| --- | --- |
| 0 | JSON 出力 (`requested` / `awaiting_fix`) |
| 1 | エラー (stderr をそのまま伝えて終了) |
| 3 | 対象 0 件 (「自分宛のレビュー依頼はありません」と伝えて終了) |

`requested` は **個人指名だけ**に絞ってある。GitHub の `review-requested:@me` はチーム経由の依頼も返すため、`reviewRequests` の User 一致でフィルタ済み。`awaiting_fix` は自分が CHANGES_REQUESTED を出した後に commit が積まれた PR。

両方を AskUserQuestion で提示して選ばせる。`awaiting_fix` から選ばれたものはフェーズB に入る。

PR が決まったら、`${CLAUDE_PLUGIN_ROOT}/references/routing.md` の手順で `detect-state.sh <PR>` を実行し、扱いに従う (自分の PR なら self-review / review-response、自分の下書きレビューが残っていれば check-review-validity を提案する)。

## Step 2: 状況を取る

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/pr-review/scripts/fetch-pr-context.sh <PR番号|URL>
```

exit 4 はカレントブランチから PR を特定できなかった場合。PR 番号の指定を促して終了する。

JSON の要点:

- `local.same_repository` / `local.head_matches` (手元の HEAD が PR の head と一致) / `local.dirty`: Step 3 の分岐
- `my_last_review` / `new_commits_since_my_review`: フェーズ判定
- `existing_threads`: 他レビュアーとの重複判定に使う
- `rule_files`: 規約チェックで読む候補
- `threads_truncated` / `pr.files_truncated`: 既存スレッド・変更ファイルが 100 件を超えて取り切れていない。重複判定や祖先 CLAUDE.md の収集が不完全になるので、その旨を報告に書く
- `my_pending_review`: `true` なら既に未 submit のドラフトがある (後述)
- `review_memo`: 前回のレビューで残した引き継ぎメモ (`~/.claude/pr-review/<owner>/<repo>/<N>.md`)。フェーズB はここから始める

`pr.state` が `OPEN` でない (closed / merged) 場合と `pr.is_draft: true` の場合は、そのまま進めず「レビューしますか？」と一度確認する。

## Step 3: 対象のコードを手元に置く

検証にテストを書いて走らせるので、diff だけでなく実ファイルが要る。

上から順に判定する:

1. `same_repository: false` (別リポジトリの URL 指定) → ここでは checkout しない (`gh pr checkout <N>` がカレントリポジトリの同番号 PR を取ってしまう)。clone がある場所を聞き、あればそのディレクトリで Step 2 からやり直す。なければ `gh pr diff` ベースの精度限定モードになる旨を伝えた上で続行し、テスト検証はできないと明記する
2. `dirty: true` → **停止して相談する**。`git stash` も `git checkout -- .` も勝手に実行しない (他のセッションの作業中かもしれない)。HEAD が一致していても、未コミットの変更が検証のテストに混ざるので先に止まる
3. `head_matches: true` → **何もしない**
4. それ以外 (別ブランチ、または PR ブランチ上だが head より古い) → `gh pr checkout <N>` する。別ブランチから切り替えた場合は、切り替え前のブランチ名を控えておき、報告で checkout した事実だけを伝える (元に戻すかは聞かない)。force push で fast-forward できず失敗したら、手元にしか無い commit を `git log --oneline <ブランチ> --not <remote>/<ブランチ> <remote>/<ブランチ>@{1}` で見る (`@{1}` は fetch 前の remote の head で、force push で消えた PR の古い commit を除く)。コマンドが成功して出力が空なら確認せず `gh pr checkout <N> --force` で合わせる。commit が出た、または `<remote>/<ブランチ>` や `@{1}` が無くて判定できない (fork の PR など) ときは、`--force` せず一覧を示して相談する。`git checkout --detach` で開かない (VS Code などがブランチから PR を探せなくなる)

checkout した場合は `fetch-pr-context.sh` をもう一度実行し、`rule_files` を PR 側のツリーから取り直す (PR 自身が追加・変更した規約を拾うため)。

## Step 4: フェーズを決めて分岐する

`--review` / `--verify` があればそれに従う。なければ `my_last_review` で判定する:

| 状態 | フェーズ |
| --- | --- |
| `null`、または COMMENTED しか出していない | **A** (レビュー作成) |
| `CHANGES_REQUESTED` | **B** (修正確認) |
| `APPROVED` | 既に Approve 済み。`new_commits_since_my_review` があれば「Approve 後に N commit 積まれています。再レビューしますか？」と聞く |

`my_pending_review: true` のときは、前回の作業が submit されずに残っている。フェーズA なら「作り直すなら GitHub 上のドラフトを破棄してから再実行してください」と伝えて終了する (Step 1 で check-review-validity への切り替えを提案済みのため、ここでは聞き直さない) (1 ユーザーが 1 PR に持てる pending review は 1 つだけなので、追記すると混ざる)。

- フェーズA → `${CLAUDE_PLUGIN_ROOT}/skills/pr-review/references/review.md` を読んで進める
- フェーズB → `${CLAUDE_PLUGIN_ROOT}/skills/pr-review/references/verify.md` を読んで進める

## やらないこと

- **submit しない。** REQUEST_CHANGES も含め、pending を確定させるのはユーザーの操作。
- **Approve / Resolve / 返信を確認なしで実行しない。** 承認を得た後なら実行してよい。
- **PR のコードを書き換えない。** 検証で作ったファイル以外に触れない。
- **`git stash` / `git checkout -- .` / `git clean` を勝手に実行しない。** 消えて困るものを消す事故はレビューの価値を全部吹き飛ばす。
