---
name: wt-manager
description: 'git worktree を扱う際は必ず `wt` 系コマンドを使う (内包化済みで Claude の Bash からも直接実行できる)。「worktree切って」「並列で別タスク」「PR検証用にworktree」「実験用に別ブランチで」などの依頼で必ず発動する。`git worktree add` を直接叩かず `wt new -d "<目的>"` で作成する、PR作成後は `wt set <name> "<内容>"` で description を更新する、並列実行は `wt claude <name>` で Agent View に乗せる、worktree への移動は `EnterWorktree({path})` を使う (name モードでの新規作成と ExitWorktree remove は hook が deny)、というルールを Claude に守らせるためのスキル。'
---

# wt-manager

`wt` 系コマンドは `.zshrc` から source された **zsh 関数** で、各worktreeの「何用か」をメタデータとして `git config --worktree wt.description` に保存しつつ運用する仕組み。直接 `git worktree add` を叩くと description が抜け落ち、後で何用のworktreeか分からなくなるので、**worktree操作はすべて `wt` 経由で行う**。

## いつ発動するか

以下の依頼パターンを検知したら、このスキルのルールに従って動く:

- 「worktree切って〜作業して」「別worktreeで〜実装して」
- 「並列で〜進めて」「同時に〜も走らせて」「別タスクとして〜」
- 「PR検証用にworktree作って」「レビュー用に〜のブランチ開いて」
- 「実験的に〜試したい」「破壊的な変更を別worktreeで」
- 既に worktree 内にいる状態で「これをPRにして」と言われた場合 (→ description更新ルール発動)

明示的に「`git worktree add` を使って」と指定された場合のみ、直接叩いてよい。

## 必ず守るルール

### Rule 1: 新規worktreeは必ず `wt new -d` で作る

`git worktree add` を直接叩かない。代わりに:

```bash
wt new -b <new-branch> <dir> [base-ref] -d "<目的を自然文で>"
```

- `<dir>` は**ディレクトリ名のみ** (絶対パス・相対パス禁止)。配置先は自動検出される
- `-d` の description は必須扱い。後で「何用か分からない」を防ぐため、PR番号 / 検証対象 / 目的 を含める
- `[base-ref]` 省略時は `git config wt.baseRef` → 現在のHEAD の順でフォールバック
- **作成後の挙動**: worktree作成のみ。`cd` / `claude --bg` 起動は連動しない。次の操作は `wt cd` / `wt claude` で別途呼ぶ

例:

```bash
wt new -b feature/PROJ_foo_pr-1234-verify task-pr-1234 origin/develop \
       -d "PR#1234 検証用 / Agent Viewで並列レビュー"
```

### Rule 2: PR作成後は description を更新する

PRを作ったら、そのworktreeの description に PR 番号・状態を反映する:

```bash
wt set <worktree名> "PR#5678 レビュー待ち / レビュアー: @xxx"
```

- 現在の worktree 内からなら `git config --worktree wt.description "<内容>"` でも同じ (名前解決が不要なだけで、書き込まれるキーは同一)

更新タイミング:

- PR を `gh pr create` で作成した直後
- レビュー指摘の対応が完了した時 (「修正反映済み・再レビュー待ち」等)
- マージ済み or クローズ時 (「マージ済み・削除候補」等)

### Rule 3: 並列実行は `wt claude` で Agent View に乗せる

ユーザーが「別タスクを並列で進めて」「同時に走らせて」と言ったら、`wt claude` を使う:

```bash
wt claude                  # fzf選択 → claude --bg (idle、プロンプト無しで起動だけ)
wt claude <name>           # name指定でfzfスキップ (Claude起点の非対話用)
wt claude <name> -n "<表示名>"   # 表示名を明示指定
```

- **常に idle 起動**: セッションを立ち上げるだけで、最初のプロンプトは人間が Agent View で送る。タスクの自動投入は行わない
- **表示名 (`-n`)**: `claude --bg -n "<label>"` でセッションに表示名を付ける (Agent View / 端末タイトルで識別)。既定は `wt.description`、無ければディレクトリ名。`-n "<表示名>"` で上書き
- バックグラウンドセッションは Agent View で総覧できる
- **クォータ消費に注意**: 並列N セッション = クォータN倍消費。Pro/Maxプランでは多重起動前に一言確認すること

### Rule 4: 自律作成・既存worktreeにも description を後付けする

Claudeが過去に `git worktree add` で作ってしまったものや、`~/myApplication/<task>/` のような既存資産にも description を付ける運用にする。

```bash
wt set                  # fzfで対象選択 → $EDITOR or インラインでdescription入力
wt set <name> "<desc>"  # 非対話で直接設定 ("" でクリア)
```

「このworktree何用？」と分からなくなったら `wt ls` で一覧確認 → 不明なものに `wt set` で後付け。

## Claude（Bashツール）からworktreeを扱う場合

ここまでの Rule 1〜4 は **人間が対話 zsh シェルから `wt` を使う**前提の動線。Claude 起点では以下を加える。

**前提**: `wt` は internal ヘルパ (`_wt_*`) を `wt()` 内に内包しており、Claude の `Bash`(zsh) からも動作する。fzf 対話を避けるため**引数指定の非対話形**を使うこと:

```bash
wt new -b <branch> <dir> [base] -d "<目的>"   # 新規作成
wt ls -p                                       # 一覧 (-p で絶対PATH列付き)
wt set <name> "<desc>"                         # description設定 ("" でクリア)
wt rm <name> -y [-b]                           # 削除 (-y必須。-bでブランチも)
wt claude <name>                               # 並列セッション投入 (idle)
```

**`wt cd` だけは効かない**(後述「`wt cd` の制約」)。worktree モデルの二重化(harness の `.claude/worktrees/` と wt 規約 `<repo親>/<dir>`)を避けるため、worktree の「移動」「削除」は Rule 5/6 に従う。これらは wt-manager の **PreToolUse hook で機械的に強制**される(`EnterWorktree` の name モードと `ExitWorktree` の `remove` を deny)。

### Rule 5: Claude が worktree を移動/退出する場合は `EnterWorktree({ path })` を使う

`wt cd` は呼び出し元シェルの cwd を変える関数で、Claude の `Bash`(毎回独立シェル)には効かない。Claude がセッションを別 worktree へ移すときは harness の `EnterWorktree` を使う:

- 既存 worktree へ移る: `EnterWorktree({ path: "<絶対パス>" })` (パスは `wt ls -p` / `git worktree list` で取得)
- 退出: `ExitWorktree({ action: "keep" })` のみ。`"remove"` は使わない (削除は `wt rm` が担当)
- `EnterWorktree` の **name モード (新規作成) は使わない** — `.claude/worktrees/` 配下に `origin/<default>` から切る挙動で、`wt` の description も配置規約 (parent パターン) も無視するため

> hook が `EnterWorktree`(name あり) と `ExitWorktree`(`action:"remove"`) を deny し、deny 理由で正しいフローへ誘導する。

### Rule 6: Claude が新規 worktree を作るときも `wt new` を使う

内包化により `wt new` は Claude の `Bash` から動くので、新規作成も人間と同じく `wt` 経由にする (引数をフル指定すれば fzf を介さず非対話で完結):

```bash
wt new -b <branch> <dir> [base-ref] -d "<目的>"
# 作成された絶対パス (出力 "wt new: created <path>" / wt ls で確認) に対して
EnterWorktree({ path: "<作成された絶対パス>" })
```

- `wt new` は作成のみで `cd` は連動しない。入るのは `EnterWorktree({ path })` (Rule 5)
- `git worktree add` の直叩きは従来どおり禁止 (description が抜けるため)。Claude 起点でも例外なし

> 人間は `wt new -d "<目的>"` → `wt cd`、Claude は `wt new -d "<目的>"` → `EnterWorktree({ path })`。**作成コマンドは共通、入り方だけが違う**。

## コマンドリファレンス

| コマンド                                    | 用途                                                         | 補足                                           |
| ------------------------------------------- | ------------------------------------------------------------ | ---------------------------------------------- |
| `wt`                                        | (引数なし) fzfでworktree選択 → エディタ(code/zed)選択 → 起動 | `vcw` 後継。code選択時はディレクトリを直接開く |
| `wt new -b <branch> <dir> [base] [-d desc]` | 新規作成 + description記録                                   | 作成のみ、cd/claude起動は連動しない            |
| `wt ls [-p]`                                | メタデータ付き一覧                                           | DIR / BRANCH / AGE / DESC。`-p` で絶対PATH列を追加 |
| `wt set [<name>] ["<desc>"]`                | description編集/設定                                         | 無引数→fzf+$EDITOR。`<name> "<desc>"` で非対話 ("" でクリア) |
| `wt rm [<name>...] [-y] [-b]`               | worktree削除                                                 | 無引数→fzf複数選択+対話確認。`-y` 確認スキップ、`-b` ブランチも削除 |
| `wt claude [<name>] [-n <label>]`           | Agent View に背景セッション投入 (idle)                       | name指定でfzfスキップ。表示名は既定で `wt.description`、無ければディレクトリ名。`-n` で上書き |
| `wt cd <name>`                              | worktreeに移動                                               | cwd伝播のため Claudeの`Bash`/CIでは無意味 (→ `EnterWorktree({path})`) |

### 配置自動検出 (`wt new` の `<dir>` の解決ルール)

- `repo_root = git rev-parse --show-toplevel`
- `parent = dirname $repo_root`
- **direct パターン** (`parent == $HOME` かつ `basename($repo_root) != "main"`): `~/<repo>-worktrees/<dir>/`
- **parent パターン** (それ以外): `<parent>/<dir>/`

例:

- `~/m-tojo-marketplace/` で `wt new ... task-foo` → `~/m-tojo-marketplace-worktrees/task-foo/`
- `~/myApplication/main/` で `wt new ... task-foo` → `~/myApplication/task-foo/`

### `wt cd` の制約

内包化により他のサブコマンド (`wt new`/`ls`/`set`/`rm`/`claude`) は Claude の `Bash`(zsh) からも動くが、**`wt cd` だけは別**。`wt cd` は呼び出し元シェルの cwd を変える関数だが、Claude の `Bash` ツールは各呼び出しが独立シェルなので `cd` が次の呼び出しに残らない。

- ✅ 対話的な zsh プロンプトから呼ぶ → cwd が変わる
- ❌ Claude が `Bash` ツールで `wt cd` を呼んでも、次のコマンドは元のディレクトリで実行される

Claude がセッションごと別 worktree へ移るなら `EnterWorktree({ path })` (Rule 5)。単発で別 worktree のコマンドを叩くだけなら `git -C <path> ...`、または `cd <絶対パス> && <コマンド>` を1コマンドに連結する。

## メタデータ仕様

| キー             | スコープ                               | 内容                                                       |
| ---------------- | -------------------------------------- | ---------------------------------------------------------- |
| `wt.description` | per-worktree (`git config --worktree`) | 「何用か」を自然文で                                       |
| `wt.baseRef`     | per-repository (`git config`)          | `wt new` の base 省略時のデフォルト (例: `origin/develop`) |
| `wt.postNew`     | per-repository (`git config`)          | `wt new` 直後に実行する opt-in コマンド。cwd=新worktree、env: `WT_NEW_PATH` `WT_NEW_BRANCH` `WT_MAIN_WORKTREE` `WT_REPO_ROOT` (例: `cp "$WT_MAIN_WORKTREE/.env.keys" .env.keys`) |

description は自然文。status / PR番号 / レビュアー / 期限などはすべて description 内に書き込む (フィールド分割しない方針)。

## 実装ファイル

`wt.zsh` はトップレベルに公開関数 `wt` **1つだけ**を定義し、各サブコマンド (`wt new`/`ls`/`set`/`rm`/`claude`/`cd`) の実体 `_wt_*` は `wt()` の中に内包する (理由は「内包設計」節)。配置は以下の二重構成:

| 役割                   | パス                                                     | 用途                                                                                                        |
| ---------------------- | -------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 正本                   | `~/dotfiles/dotfiles/wt.zsh`                             | `.zshrc` から相対パスで source される実体。ユーザの対話シェルで `wt` が使えるのはこれが load されているため |
| 配布用スナップショット | `${CLAUDE_PLUGIN_ROOT}/skills/wt-manager/scripts/wt.zsh` | プラグイン同梱の参照用コピー。dotfiles を持たない環境でも実装を確認できる                                   |

### `.zshrc` 側のロード規約 (相対パス)

`wt.zsh` は `.zshrc` と**同一ディレクトリ**に配置し、相対パスで source する:

```zsh
# ~/dotfiles/dotfiles/.zshrc の末尾
source "${${(%):-%x}:A:h}/wt.zsh"
```

`${${(%):-%x}:A:h}` は zsh のイディオムで「現在 source 中のファイル (= `.zshrc` 本体) の**解決済み絶対ディレクトリ**」を返す。`:A` で symlink (`~/.zshrc` → `~/dotfiles/dotfiles/.zshrc` 等) も解決されるため、`~/.zshrc` がどこに置かれていても同居している `wt.zsh` を拾える。

### 実装詳細を確認したい時の Read 先

1. 実機に dotfiles がある (= `~/dotfiles/dotfiles/wt.zsh` が存在) → **正本** を優先で Read
2. dotfiles が無い (skill のみ配布された環境) → **同梱版** (`${CLAUDE_PLUGIN_ROOT}/skills/wt-manager/scripts/wt.zsh`) を Read

同梱版は正本のスナップショット (現状は手動同期)。正本を更新したらスナップショットにも反映する運用。乖離が疑われる場合は両方の `git log` / `diff` を確認する。

### 内包設計 (なぜ `wt()` に内包するか)

internal ヘルパ `_wt_*` は `wt()` 実行時に関数内で定義し、終了時に `unfunction -m '_wt_*'` で破棄する。狙いは2つ:

1. **対話シェルを汚さない**: `_wt_*` がグローバル名前空間や補完候補に常駐しない (公開ゼロ)
2. **Claude の `Bash` で動く**: Claude Code のシェルスナップショットは「先頭 `_` のトップレベル関数」を除外する。`_wt_*` をトップレベルに置くと Claude から `wt new` が `_wt_new not found` で落ちるが、`wt()` 内包なら snapshot に載るのは `wt` だけで、`wt` 経由で全サブコマンドが動く

テスト (`wt.test.zsh`) は `_wt_*` を直接呼ぶため、環境変数 `WT_KEEP_INTERNAL=1` で破棄を抑止し、一度 `wt` を呼んでヘルパをグローバル展開してからテストする。

### PreToolUse hook (`hooks/hooks.json` + `scripts/guard-worktree.sh`)

worktree モデルの二重化を防ぐガード。`EnterWorktree` / `ExitWorktree` を matcher にとり、deny 理由で正しいフローへ誘導する:

- `EnterWorktree` に `name` あり (新規作成) → **deny** (→ `wt new` → `EnterWorktree({ path })`)
- `ExitWorktree` の `action:"remove"` → **deny** (→ `ExitWorktree({ action:"keep" })` + `wt rm`)
- `EnterWorktree({ path })` / `ExitWorktree({ action:"keep" })` は許可

## やらないこと

- `git worktree add` を直接叩く (ルール違反、descriptionが抜ける。Claude 起点も `wt new` を使う＝例外なし)
- description なしで `wt new` を実行する
- 自動cleanup / マージ済みworktreeの自動削除 (`wt rm` での手動削除のみ)
- `wt cd` を非対話シェル / CI / Claude の `Bash` から使う (Claude は Rule 5 の `EnterWorktree({ path })`)
- `EnterWorktree` の name モード (新規作成) / `ExitWorktree({ action: "remove" })` を使う (配置規約・descriptionを無視 / 削除は `wt rm`)
- worktree数のしきい値警告 (手動運用)

## 関連プラグイン・既存資産

- `gwta` (= `git worktree add` エイリアス, `~/dotfiles/dotfiles/.zshrc`) は維持。`wt new` とは別物として共存
- 旧 `vcw` / `delete-vcw` zsh関数 (dotfiles) と VSCodeColorizer プラグインは、`wt` への統合完了に伴い **1.4.0 で削除済み**
