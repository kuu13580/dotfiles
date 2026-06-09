# wt-manager

git worktree を fzf ベースの `wt` 系コマンドで管理するプラグインです。各 worktree の「何用か」を `git config --worktree wt.description` に記録し、`git worktree list` だけでは分からない用途を一覧・プレビューできます。Claude Code Agent View での並列セッション運用を前提に設計しています。

## 構成

実装本体 (`wt.zsh`) は **dotfiles 側を正本**とし、プラグインには Claude 向けの SKILL と配布用スナップショットを同梱する 2 層構成です。

| 役割 | パス |
| --- | --- |
| 正本 (zsh関数の実体) | `~/dotfiles/dotfiles/wt.zsh` |
| 配布用スナップショット | `skills/wt-manager/scripts/wt.zsh` |
| テスト | `skills/wt-manager/scripts/wt.test.zsh` |
| Claude 向け動線 | `skills/wt-manager/SKILL.md` |

プラグインインストールパス(キャッシュ位置)は変動するため、`.zshrc` から source するのは **dotfiles 側の固定パス**です。

## セットアップ

1. `wt.zsh` を `.zshrc` と同じディレクトリに配置 (例: `~/dotfiles/dotfiles/wt.zsh`)
2. `.zshrc` 末尾に相対パスで source 行を追加:

   ```zsh
   source "${${(%):-%x}:A:h}/wt.zsh"
   ```

   `${${(%):-%x}:A:h}` は「現在 source 中のファイル (= `.zshrc`) の解決済み絶対ディレクトリ」を返す zsh イディオム。`:A` で symlink (`~/.zshrc` → dotfiles 内) も解決されるため、同居している `wt.zsh` を確実に拾えます。

3. 新しい zsh を起動し `wt help` で確認

## コマンド

| コマンド | 用途 |
| --- | --- |
| `wt` | fzf で worktree 選択 → エディタ (code/zed) 選択 → 起動 |
| `wt new -b <branch> <dir> [base] [-d desc]` | 新規作成 + description 記録 (`<dir>` はディレクトリ名のみ、配置先は自動検出)。引数なしで叩くと対話フォーム (下記、tty のみ) |
| `wt ls [-p]` | メタデータ付き一覧 (DIR / BRANCH / AGE / DESC)。`-p` で絶対 PATH 列を追加 |
| `wt set [<name>] ["<desc>"]` | description 編集/設定。無引数 → fzf + `$EDITOR`、`<name> "<desc>"` で非対話 (`""` でクリア) |
| `wt rm [<name>...] [-y] [-b]` | worktree 削除。無引数 → fzf 複数選択 + 対話確認、`-y` で確認スキップ、`-b` でブランチも削除 |
| `wt claude [<name>] [-n <label>]` | `claude --bg` で Agent View に idle 投入 (プロンプト無し)。name 指定で fzf スキップ。表示名 (`-n`) は既定で `wt.description`、無ければディレクトリ名。`-n <label>` で上書き |
| `wt cd [<name>]` | worktree に `cd` (zsh 関数のため対話シェルでのみ機能) |

### 配置自動検出 (`wt new`)

- **direct パターン** (`$HOME` 直下のリポジトリ、basename が `main` 以外): `~/<repo>-worktrees/<dir>/`
- **parent パターン** (それ以外): `<リポジトリの親ディレクトリ>/<dir>/`

### 対話フォーム (引数なし `wt new`)

引数の順番やフラグを覚えなくても、`wt new` を**引数なし**で叩けば対話フォームで作成できます。

- branch / dir / description … プロンプト入力 (dir の既定値は branch 名の末尾 = 最後の `/` 以降。例: `feature/hogehoge` → `hogehoge`)
- base ref … fzf で既存ブランチ (ローカル / リモート) + `(default)` から選択 (`(default)` / Esc で `wt.baseRef` → HEAD)
- 最後に内容サマリを表示し `Create? (Y/n)` で確認
- **発動条件**: 標準入力が tty のときのみ。非 tty (Claude の `Bash`、パイプ、CI) や引数付き呼び出しは従来どおりフラグ解析され、引数不足なら usage エラー。Claude に強制している `wt new -b ... -d` フローはフォームに落ちません

### メタデータ

| キー | スコープ | 内容 |
| --- | --- | --- |
| `wt.description` | per-worktree (`git config --worktree`) | 「何用か」を自然文で。PR番号・状態などを含める |
| `wt.baseRef` | per-repository | `wt new` の base 省略時のデフォルト ref (例: `origin/develop`) |
| `wt.postNew` | per-repository | `wt new` 直後に実行する opt-in コマンド (下記参照) |

`git config --worktree` を使うため、初回書き込み時に `extensions.worktreeConfig` を自動で有効化します。

### postNew フック (`wt.postNew`)

`wt new` で worktree を作成した直後に、リポジトリ単位で設定したコマンドを実行できます。gitignore されていて新 worktree に複製されないファイル (例: `.env` の復号鍵 `.env.keys`) を自動で持ち込む用途を想定しています。

```shell
# リポジトリ内で 1 回設定 (共有 .git/config に保存され、全 worktree で有効)
git config wt.postNew 'cp "$WT_MAIN_WORKTREE/.env.keys" .env.keys'
```

- **opt-in**: `wt.postNew` 未設定のリポジトリでは何もしません
- **実行コンテキスト**: cwd = 新しい worktree
- **渡される環境変数**:

  | 変数 | 内容 |
  | --- | --- |
  | `WT_NEW_PATH` | 新しい worktree の絶対パス |
  | `WT_NEW_BRANCH` | 新 worktree の branch 名 |
  | `WT_MAIN_WORKTREE` | main worktree のパス (コピー元に使う) |
  | `WT_REPO_ROOT` | `wt new` を呼んだリポジトリ root |

- **失敗時**: フックが非ゼロ終了しても警告を出すだけで、`wt new` 自体は成功扱い (worktree は既に作成済みのため)
- `&& pnpm install` のようにコマンドを連結すれば依存インストールまで自動化できますが、`wt new` が遅く・対話的になる点に注意

## テスト

```shell
zsh ~/dotfiles/dotfiles/wt.zsh   # 本体 (source 用)
zsh ~/dotfiles/dotfiles/wt.test.zsh   # テストスイート
```

fzf / `claude --bg` / `$EDITOR` 連動を除いた純粋ロジック + git 実操作を 71 アサーションで検証します (一時 git リポジトリを `mktemp` で作成し `trap` で削除)。internal ヘルパ (`_wt_*`) は `wt()` に内包されているため、テストは `WT_KEEP_INTERNAL=1` でヘルパを展開してから直接検証します。

## 前提環境

- git ≥ 2.x (worktree per-config 対応)
- fzf
- zsh (`wt cd` のシェル関数経由 cwd 変更、`wt` 引数なし時のエディタ選択)
- jq (PreToolUse hook `guard-worktree.sh` の判定に使用)
- Claude Code v2.1.139+ (`wt claude` の Agent View 連携)

## Claude からの利用 (SKILL)

`skills/wt-manager/SKILL.md` が、worktree 関連の依頼 (「worktree切って作業して」「並列で別タスク」「PR検証用に」など) を検知して以下のルールに乗せます:

- `git worktree add` を直接叩かず `wt new -d "<目的>"` 経由で作成
- PR 作成後は `wt set <name> "<内容>"` で description を更新
- 並列実行は `wt claude` で Agent View に投入
- Claude 自身が worktree を移動するときは `EnterWorktree({ path })` (cwd を変える `wt cd` は Claude の `Bash` では効かないため)

付属の PreToolUse hook (`hooks/`) が `EnterWorktree` の新規作成 (name) と `ExitWorktree` の `remove` を deny し、`wt new` / `wt rm` 動線へ誘導します。なお `wt.zsh` は internal ヘルパを `wt()` に内包しており、Claude の `Bash`(zsh) からも `wt new` 等が動作します。

## 注意

- 並列 N セッション = クォータ N 倍消費。Pro/Max プランでは多重起動に注意
- 自動 cleanup / マージ済み worktree の自動削除・しきい値警告は行わない (手動運用)
- `wt cd` は非対話シェル / CI では機能しない (cwd 変更がサブプロセスに閉じるため)
