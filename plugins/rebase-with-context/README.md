# rebase-with-context

rebase のコンフリクトを、**両側の PR・コミットの文脈を読んだ上で**解消するスキル。

- base 側で該当行を変更した PR と、適用中の自分のコミット・PR の意図を読む
- PR 本文・コミットメッセージ・レビュースレッドに**引用できる根拠**がある箇所だけ自動で解消し、完了後にサマリで報告する
- 根拠のない箇所は、**承認モード (bypass / auto 含む) にかかわらず**ユーザーに確認する

## 使い方

```bash
/rebase-with-context                  # 分岐元を推定して rebase
/rebase-with-context shared-feature   # rebase 先を指定 (origin/shared-feature を優先、無ければローカル)
```

手で `git rebase` して止まった状態で呼んでもよい (そこから引き継ぐ)。

## 前提条件

- `git` 2.31 以上、`jq`
- PR の文脈を使うには `gh` CLI (認証済み) と GitHub のリモート。無い場合はコミットメッセージだけで判断し、確認が増える

## 挙動

### rebase 先の決定

引数があれば `git fetch` して `origin/<base>` を優先、無ければローカルの `<base>`。省略時は次の順で分岐元を推定する。

1. 自分のブランチの PR の base (`baseRefName`)
2. reflog のブランチ作成記録 (`branch: Created from X`)
3. `branch.<name>.merge` (自分と同名なら使わない)

どれも取れなければ、デフォルトブランチ決め打ちにせず候補を出して確認する。rebase 先を誤ると無関係なコンフリクトが大量に出て、分析がすべて無駄になるため。

### hunk の分類

| 分類 | 条件 | 動作 |
| --- | --- | --- |
| 機械的解消 | 両側の変更が意味的に独立 (import 追加同士など) | 自動。報告しない |
| 文脈で判断 | 片側を正とする根拠を PR・コミットから引用できる | 自動。サマリに根拠付きで報告 |
| 要確認 | 上記以外 (推論止まり・同じ値を別方向に変更・仕様判断) | 確認 |

確認はコミット単位でまとめて行う。前のコミットの解消結果が次のコンフリクトに影響するので、全体を先に聞くことはしない。

### 「前後の PR」の取り方

- **HEAD 側**: hunk の HEAD 側の行範囲を `git log -L` で merge-base まで辿り、触ったコミットすべて (直近 1 件だけだと途中の PR の意図が落ちる) → コミットごとの PR
- **replay 側**: 適用中のコミットと自分のブランチの PR
- PR からはタイトル・本文・closing issue と、**コンフリクトしたファイルに付いた**レビュースレッドだけを取る (PR 全体のコメントはノイズが多い)

## 意図的にやらないこと

| やらないこと | 理由 |
| --- | --- |
| rerere | 過去の解消を無言で再適用され、判断が素通りされる。スキル内の rebase 操作では毎回 `-c rerere.enabled=false` を付ける (設定ファイルは変えない) |
| `--autosquash` | レビュー済み PR は追加 commit で直す運用と衝突する |
| `--update-refs` | 他ブランチを勝手に動かすのは影響範囲が広い。途中を指すブランチがあれば警告のみ |
| stash | worktree 間で共有される。未コミット変更があれば中断する |
| 自動 push / PR へのコメント | 公開操作はユーザーが行う |
| 各コミットでの build | rebase が極端に遅くなる。完了後に 1 回だけ実行し、失敗しても自動では直さない |
| サブエージェント | 確認 (AskUserQuestion) は本体からしか出せない。判断の一貫性も保てない |

## 状態の置き場

- `<worktree の git dir>/rebase-with-context/`: 状態・判断記録・PR 取得のキャッシュ。完了時・abort 時に削除
- `refs/rebase-with-context/backup/<branch>`: 開始前の HEAD。完了時に削除し、**abort 時は残す**

## 構成

```
rebase-with-context/
  .claude-plugin/plugin.json
  skills/rebase-with-context/SKILL.md
  skills/rebase-with-context/scripts/lib.sh               共通ヘルパ (rerere 無効化の rebase ラッパ等)
  skills/rebase-with-context/scripts/prepare.sh           新規 / 途中引き継ぎの判定と base の決定 (read-only)
  skills/rebase-with-context/scripts/rebase-step.sh       start / adopt / continue / skip / status / abort / finish
  skills/rebase-with-context/scripts/collect-context.sh   hunk → コミット → PR の文脈を JSON 化
```
