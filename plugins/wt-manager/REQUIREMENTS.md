# wt-manager 要件定義

## 背景・目的

Claude Code Agent View (2026/5 GA, v2.1.139+) で並列セッションを回す運用が前提になった。worktreeを増やしながら作業するスタイルだが、現状は3つの痛みがある。

| # | 課題 | 補足 |
|---|---|---|
| ❶ | どのworktreeが何用か分からない | `git worktree list` ではブランチ名しか分からず、Claudeが自律的に作ったものは特に不明 |
| ❷ | 並列Claude Codeセッションを1ターミナルから総覧したい | Agent View で実現可能、tmuxは不要 (Windows/WSL運用で不便) |
| ❸ | worktreeが増えすぎる | 古いものを畳む動線がない |

### ユースケース

| 優先 | ユースケース | 内容 |
|---|---|---|
| メイン | **Claude Code並列実行** | 各worktreeで `claude --bg` で背景セッション起動、Agent Viewで総覧 |
| 副次 | 複数タスク並行作業 | 機能A実装中に緊急機能Bを別worktreeで開始（ビルドキャッシュ衝突回避） |
| 副次 | PRレビュー専用 | レビュー対象ブランチを別worktreeで開いて閲覧、終わったら削除 |
| 副次 | 実験・検証用 | 破壊的な変更を安全に試す。気軽に作って気軽に捨てる |

### Agent View 利用時の注意

並列N セッション = クォータN倍消費。Pro/Maxプランは特に注意。

## 設計方針

- **VSCodeColorizerから脱却**: 色機能・`~/.vscode-workspaces/*.code-workspace` 自動生成を不要化。毎回workspaceファイルを開く手間を削減
- **`vcw` / `delete-vcw` 廃止**: dotfilesの既存zsh関数を`wt`系コマンドに統合
- **Agent View 一本化**: `claude --bg -n "<label>"` で背景 idle セッション起動、Agent Viewで総覧
- **メタデータ管理**: `git config --worktree wt.description` に「何用か」を保存。自律作成worktreeにも後付け可能
- **fzfベースUX**: `vcw` の操作感を踏襲、プレビューで情報を表示
- **配布形態**: シェル関数本体は **dotfiles 側を正本**とする (`~/dotfiles/dotfiles/wt.zsh`、`.zshrc` と同ディレクトリ)。`.zshrc` から**相対パス**で source (`source "${${(%):-%x}:A:h}/wt.zsh"`)。プラグインのインストールパス (キャッシュ位置) に依存させないため。marketplaceプラグイン `wt-manager` には Claude 向け SKILL と**配布用スナップショット** (`skills/wt-manager/scripts/wt.zsh`、正本のコピー) を同梱する
- **Claudeからの一律動線**: skillで「worktree切って作業して」等のトリガーに乗せる

## コマンド体系

```bash
wt                                          # 引数なし: fzf選択 → エディタ(code/zed)選択 → 起動
wt new -b <branch> <dir> [base] [-d desc]   # 新規作成 + description記録 (作成のみ、後続操作なし)
wt ls                                       # メタデータ付き一覧
wt set                                      # fzf選択 → $EDITOR or プロンプトでdescription編集
wt rm                                       # fzf複数選択 → 削除 (branch削除は対話確認)
wt claude                                   # fzf選択 → claude --bg -n "<desc>" で Agent View に (idle)
wt cd <name>                                # cd (シェル関数として実装、※後述)
```

### fzfプレビュー仕様

選択中の項目について、プレビュー欄に以下を表示:

```
BRANCH:      feature/PROJ_foo
PATH:        /home/m-tojo/myApplication/task-foo
AGE:         3 days ago
DESCRIPTION:
  PR#1234 検証中
  Agent View 対応で並列セッション張ってる
```

### `wt` (引数なし) 詳細

`vcw` 後継。fzfでworktree選択 → エディタを `code` / `zed` の中から fzf で選ぶ → 起動。

- `code` 選択時: `code <worktreeディレクトリ>` で直接開く (workspaceファイルは使わない)
- `zed` 選択時: `zed <worktreeディレクトリ>`

### `wt new` 詳細

- 引数体系は `gwta` (= `git worktree add`) 互換 + `-d` でdescription
- `<dir>` 引数は**ディレクトリ名のみ**を受け付ける (絶対パス/相対パスはエラー)。配置先は自動検出で決定
- 例:
  ```bash
  wt new -b feature/PROJ_hogehoge_task-description task-description origin/develop \
         -d "PR#XXXX 検証用"
  ```
- **作成後の挙動**: worktree作成 + description記録のみ。`cd` や `claude --bg` 起動は連動しない。次の操作は人間が `wt cd` / `wt claude` で明示的に呼ぶ
- **配置自動検出**:
  - `repo_root = git rev-parse --show-toplevel`
  - `parent = dirname $repo_root`
  - `parent == $HOME && basename($repo_root) != "main"` の場合 (direct): `~/<repo>-worktrees/<dir>/`
  - それ以外 (parent パターン): `<parent>/<dir>/`
  - 結果例:
    - `~/m-tojo-marketplace/` → `~/m-tojo-marketplace-worktrees/<dir>/`
    - `~/myApplication/main/` → `~/myApplication/<dir>/`
- **base ブランチ**:
  - 第3引数で明示
  - 省略時は `git config wt.baseRef` を参照
  - それも未設定なら現在のHEAD

### `wt set` 詳細

- fzf選択 → 既存description表示
- `$EDITOR` が設定されていればテキストエディタを起動、未設定ならインライン プロンプト入力
- 保存内容を `git config --worktree wt.description` に書き込み
- **自律作成worktreeへの後付け運用**: Claudeが `git worktree add` で勝手に作ったworktree、または既存の `~/myApplication/*/` のような過去資産にも `wt set` で description を後付け可能

### `wt rm` 詳細

- fzf複数選択 (Tab で選択、Enter で確定)
- 削除前に対象一覧を表示し確認
- ブランチも削除するか対話で確認 (`y/N`)
- 内部: `git worktree remove <path>` + 必要に応じ `git branch -d <branch>`

### `wt claude` 詳細

- fzf選択 (descriptionをプレビュー表示)。`<name>` 指定で fzf スキップ
- **常に idle 起動**: `cd <worktree> && claude --bg -n "<label>"` で **idle セッション**を起動 (プロンプト無し)。最初の指示は Agent View で人間が送る。タスクの自動投入は行わない
- **表示名 (`-n`)**: `claude --bg -n` でセッションに表示名を付与 (Agent View / `/resume` ピッカー / 端末タイトルで識別)
  - 既定: `wt.description`、無ければディレクトリ名
  - `wt claude <name> -n "<表示名>"` → 表示名を明示指定で上書き
- 設計意図: description を初期プロンプトに自動投入すると、単にセッションを開きたいだけのとき勝手にタスクが走り出すため、投入機能 (旧 `-t`) は廃止。description は**セッション表示名 (`-n`)** として活用する

### `wt cd` 詳細

- **シェル関数として実装する必要がある** (zsh関数を `.zshrc` から source)
- 理由: スクリプトはサブプロセスで実行されるため、`cd` が親シェルのカレントディレクトリを変えられない。シェル関数なら親シェルで実行されるためcwd変更が反映される
- 結果として bash/zsh からの呼び出し時のみ機能する（CI/非対話シェルでは使えない）

### `wt ls` 詳細

```
DIR                  BRANCH                                  AGE   DESC
task-foo             feature/PROJ_foo                       3d    PR#1234 検証中
install-bench-yarn   detached@054a77c85                      45d   (no description)
```

- 増殖制御の自動警告は出さない（手動運用）

## メタデータ

`git config --worktree` を利用。フィールドは最小:

| キー | 内容 | 必須 |
|---|---|---|
| `wt.description` | 「何用か」を自然文で | 任意 (後付け可) |

リポジトリ単位の設定:

| キー | 内容 |
|---|---|
| `wt.baseRef` | `wt new` 時のbase省略時に使うref (例: `origin/develop`) |

PRを作成したら、Claude側でdescriptionを更新する運用 (skillに記述)。

## プラグイン構造 / 配置

実装本体 (`wt.zsh`) は zsh 関数群を 1ファイルに集約し、**dotfiles 側に正本**を置く。プラグインリポジトリは Claude 向け SKILL + 配布用スナップショットを担う。

### プラグインリポジトリ

```
plugins/wt-manager/
├── .claude-plugin/
│   └── plugin.json
├── README.md
├── CHANGELOG.md
├── REQUIREMENTS.md       # 本ファイル
├── hooks/
│   └── hooks.json        # PreToolUse: EnterWorktree(name)/ExitWorktree(remove) を deny
├── scripts/
│   └── guard-worktree.sh # 上記 hook の判定スクリプト (wt 動線へ誘導)
└── skills/
    └── wt-manager/
        ├── SKILL.md      # Claudeからの動線・運用ルール
        └── scripts/
            ├── wt.zsh       # 配布用スナップショット (正本のコピー、参照用)
            └── wt.test.zsh  # wt.zsh のテストスイート (スナップショット)
```

### dotfiles 側 (`wt` の実体)

```
~/dotfiles/dotfiles/
├── .zshrc                # 末尾で `source "${${(%):-%x}:A:h}/wt.zsh"` (相対)
└── wt.zsh                # 全関数の正本 (wt, wt new, wt ls, wt set, wt rm, wt claude, wt cd)
```

- `wt.zsh` は `.zshrc` と**同一ディレクトリ**に置く前提。`.zshrc` から相対パスで source
- `${${(%):-%x}:A:h}` は zsh の prompt expansion を使い「source 中のスクリプト (= `.zshrc`) の解決済み絶対ディレクトリ」を取得するイディオム。symlink (`~/.zshrc` → dotfiles 内) も `:A` で解決される
- プラグイン同梱版 (`skills/wt-manager/scripts/wt.zsh`) と dotfiles 側 (`~/dotfiles/dotfiles/wt.zsh`) は手動同期。正本は dotfiles 側

## Claude側の動線 (skill)

- **トリガー例**: 「worktree切って作業して」「並列で別タスクを進めて」「PR検証用にworktree作って」
- **ルール**:
  - `git worktree add` を直接叩かず、必ず `wt new` 経由で作成する
  - 作成時は `-d "<目的>"` でdescriptionを必ず付ける
  - PRを作成したら `git config --worktree wt.description "<更新後>"` で内容を更新する
  - 並列実行が必要な場合は `wt claude` で Agent View に乗せる

## マイグレーション (VSCodeColorizer → wt-manager)

> **ステータス: 完了 (2026-06-03, wt-manager 1.4.0)** — MIGRATION.md は作成せず、Agent との対話セッションで以下のステップ相当 (棚卸し → description 付与 → workspace/旧関数/プラグイン削除) を実施した。以下は計画当時の記録。

スクリプト化はオーバースペックなので、**Claude向けの作業書 (`MIGRATION.md`) を残す**方式とする。Agent が読み下して実行する。

### MIGRATION.md に書くべきステップ

1. **既存workspaceファイルの棚卸し**
   - `~/.vscode-workspaces/*.code-workspace` を列挙
   - 各ファイルの `folders[0].path` を `jq` で読んで、対応する実worktree/リポジトリを特定

2. **descriptionの推測と付与**
   - workspace名 (例: `core-web-component-explore`) と branch名から目的を推測
   - 該当worktreeに対し `git -C <path> config --worktree wt.description "<推測desc>"` を実行
   - 推測が困難なものは人間に対話確認

3. **不要ファイルの削除**
   - 対応worktreeが既に削除されているworkspaceファイルは削除
   - メインリポを指すだけのworkspaceファイル (`*.lock`, `*.backup`含む) は削除

4. **VSCodeColorizerプラグインの無効化**
   - マイグレーション完了 + wt-manager動作確認後に `plugins/vscode-colorizer/` を削除
   - 並行運用期間中はVSCodeColorizerが新たに workspace を作らないよう hook を一時無効化する手順を記述

## やらないこと

- VSCodeの色機能 (Claude実行状態色変化) の再実装
- workspaceファイル (`~/.vscode-workspaces/*.code-workspace`) の管理
- 自動cleanup / マージ済みworktreeの自動削除
- worktree数のしきい値警告
- tmux連携
- bash/CI環境での `wt cd` 動作保証

## 関連する既存資産

| 資産 | パス | 扱い |
|---|---|---|
| `gwta` エイリアス | `~/dotfiles/dotfiles/.zshrc` | 維持 (`wt new` とは別物として共存) |
| `vcw` / `delete-vcw` zsh関数 | `~/dotfiles/dotfiles/.zshrc` | 削除済み (1.4.0、`wt` に統合) |
| VSCodeColorizer プラグイン | `plugins/vscode-colorizer/` | 削除済み (1.4.0) |
| 既存worktree配置 (parent型) | `~/myApplication/<task>/` | 維持 (parentパターン自動検出で対応)。マイグレ時に description を一括付与 |
| 既存workspaceファイル群 | `~/.vscode-workspaces/*.code-workspace` | 削除済み (1.4.0、棚卸し → description 移行後) |

## 前提環境

- git ≥ 2.x (worktree per-config 対応)
- fzf
- jq
- Claude Code v2.1.139+ (Agent View対応)
- zsh (シェル関数経由の `wt cd`、`wt` 引数なし時のエディタ選択)

## 設計外（議論済み・採用せず）

| 項目 | 経緯 |
|---|---|
| tmux paneでClaude Code並列起動 | Windows/WSLでtmuxが扱いづらいため却下、Agent Viewで代替 |
| `wt clean` (自動cleanup) | 手動運用 (`wt rm`) で十分との判断 |
| しきい値警告 | 手動運用方針に合わせ不要 |
| メタデータに status/PR番号フィールド | description自然文に含める方針で十分 |
| `wt new` の対話モード | フラグ指定で十分、複雑化を避ける |
