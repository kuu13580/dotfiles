# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.0] - 2026-06-25

### Added

- **対話フォームの dir 候補を `_` 区切りで段階提示**: `wt new` 引数なしフォームで、branch 名の末尾 (`:t`) を `_` 区切りに前半から1段ずつ削った候補を番号付きで提示するように。番号で選択 / 空 Enter は `1)` (フル) / それ以外の文字列は直接入力扱い。`_` を含まない場合は従来どおり `[既定値]` の単一入力。例: `feature/077_TICKET-5_update-translate` → `1) 077_TICKET-5_update-translate` `2) TICKET-5_update-translate` `3) update-translate`。候補生成は純粋ヘルパ `_wt_dir_candidates` に切り出し、テスト3件追加 (計 74 アサーション)

## [1.7.1] - 2026-06-21

### Documentation

- **background セッションでの隔離運用を明記 (SKILL Rule 7 / README)**: `wt claude` / `claude --bg` / Agent View の bg セッションでは PreToolUse hook (`guard-worktree.sh`) が発火しないことがあり、Rule 5/6 のガードが効かない前提を追記。対策として、ユーザーが `settings.json` に `"worktree": {"bgIsolation": "none"}` を手動設定し harness の自動隔離 (`.claude/worktrees/` への `wt` 規約無視の worktree 生成) を止めた上で、Claude が能動的に `wt new` → `EnterWorktree({ path })` で隔離する運用を文書化。`bgIsolation: "none"` は Edit/Write の隔離ブロックを無効化するだけで `wt new` (Bash 経由の `git worktree add`) には影響しない点も明記。ドキュメントのみで `wt.zsh` / hook の挙動変更なし

## [1.7.0] - 2026-06-10

### Added

- **`wt new` の対話フォーム (引数なし起動)**: コマンドの引数順・フラグを覚えなくても、`wt new` を引数なしで叩くと対話フォームで worktree を作れるように。branch / dir / description は `read` プロンプト (dir 既定値は branch 名の末尾 = 最後の `/` 以降。例: `feature/hogehoge` → `hogehoge`)、base ref は新ヘルパ `_wt_pick_base` が fzf で既存ブランチ (ローカル/リモート) + `(default)` から選ばせる。最後に summary を出して `Create? (Y/n)` で確認。フォームは **`[[ -t 0 ]]` が真 (tty) のときだけ** 発動し、Claude の非tty 呼び出し・フラグ付き呼び出しは従来どおり (hook で強制される `wt new -b ... -d` フローは不変)。テスト3件追加 (計 71 アサーション)

## [1.6.0] - 2026-06-10

### Added

- **`wt new` の postNew フック (`git config wt.postNew`)**: worktree 作成直後に repo 単位 opt-in のコマンドを実行できるように。cwd=新 worktree、env で `WT_NEW_PATH` / `WT_NEW_BRANCH` / `WT_MAIN_WORKTREE` / `WT_REPO_ROOT` を渡す。非ゼロ終了は警告のみで `wt new` は失敗扱いにしない。`.env` 復号鍵など gitignore されたファイルを新 worktree へ複製する用途を想定 (例: `git config wt.postNew 'cp "$WT_MAIN_WORKTREE/.env.keys" .env.keys'`)。`wt.baseRef` と同じ per-repo config パターンを踏襲。テスト9件追加 (計 68 アサーション)

## [1.5.0] - 2026-06-05

### Added

- **`wt claude` の `-n <label>` (セッション表示名)**: `claude --bg -n` でセッションに表示名を付与し、Agent View / `/resume` ピッカー / 端末タイトルで識別できるように。既定は `wt.description`、無ければディレクトリ名。`-n "<表示名>"` で上書き。テスト2件追加 (計 59 アサーション)

### Removed

- **`wt claude -t` (タスク自動投入) を廃止**: description を初期プロンプトに投入する機能を削除し、`wt claude` は常に idle 起動に統一。description は表示名 (`-n`) として活用する方針に変更 (単にセッションを開きたいだけのとき勝手にタスクが走り出す問題を構造的に解消)

## [1.4.0] - 2026-06-03

### Added

- `wt ls -p`: 絶対 PATH 列を追加表示。`EnterWorktree({ path })` に渡すパスを wt だけで取得できるように (Rule 5 / hook の deny 理由の案内と実体の不整合を解消)。テスト3件追加 (計 56 アサーション)

### Changed

- SKILL frontmatter description を現仕様に更新 (内包化で Claude の Bash から直接実行可、`wt set` への一本化、`EnterWorktree({path})` + hook deny)

### Removed

- **VSCodeColorizer プラグインを削除** (マイグレーション完了): `~/.vscode-workspaces/` の workspace 20件を棚卸しし、対応 worktree へ description を移行したうえで workspace ファイル群・dotfiles の旧 `vcw` / `delete-vcw` 関数とともに撤去。marketplace.json からもエントリ削除
- REQUIREMENTS の MIGRATION.md 参照を解消 (実ファイル未作成の dead reference。マイグレ節に完了ステータスを注記)

## [1.3.0] - 2026-06-03

### Added

- **`wt set` / `wt rm` / `wt claude` の非対話形** (既存の無引数 fzf 動作は完全互換維持):
  - `wt set <name> "<desc>"`: fzf/`$EDITOR` を介さず description を直接設定 (`""` でクリア)。`wt set <name>` のみなら fzf だけスキップして `$EDITOR`/プロンプト編集
  - `wt rm <name>... [-y] [-b]`: name 指定で fzf スキップ。`-y` で確認スキップ (非対話必須)、`-b` でブランチも削除。`-y` 無しは従来の対話確認で止まる (誤爆防止)
  - `wt claude <name> [-t [task]]`: name 指定で fzf スキップ。Claude 起点の並列セッション投入が非対話で完結
- name 解決ロジックを `_wt_resolve_name` に共通化 (`wt cd` と同じ basename 一致 → パス末尾一致。cd/set/rm/claude で共用)
- テスト 17 件追加 (計 53 アサーション)

### Changed

- SKILL.md Rule 2 (PR 後の description 更新) を `wt set <name> "<desc>"` に一本化 (`git config --worktree` 直叩きは現 worktree 内の代替として併記)
- `wt claude <不明な位置引数>` は「unknown argument」ではなく worktree 名として解決を試み「no worktree matched」を返すように (オプション以外の引数が name になったため)

## [1.2.0] - 2026-06-02

### Added

- **`wt.zsh` 内包化**: 公開トップレベル関数を `wt` 1つに絞り、internal ヘルパ `_wt_*` を `wt()` 内で定義 → 終了時に `unfunction -m '_wt_*'` で破棄。狙いは (1) 対話シェルの名前空間・補完を汚さない (公開ゼロ)、(2) Claude Code のシェルスナップショット (先頭 `_` のトップレベル関数を除外) 経由でも `wt new` 等が動作させる。従来は `_wt_*` が snapshot から除外され、Claude の `Bash` から `wt new` が `_wt_new not found` で落ちていた
- **PreToolUse hook** (`hooks/hooks.json` + `scripts/guard-worktree.sh`): `EnterWorktree` の name モード (新規作成) と `ExitWorktree` の `action:"remove"` を deny し、deny 理由で `wt new` → `EnterWorktree({ path })` / `wt rm` へ誘導。harness の `.claude/worktrees/` と wt 規約 (`<repo親>/<dir>`) の二重化を防ぐ
- SKILL.md に「Claude（Bashツール）からworktreeを扱う場合」セクションを追加 (Rule 5: 移動/退出は `EnterWorktree({ path })` / `ExitWorktree({ action:"keep" })`、Rule 6: 新規作成も `wt new` → `EnterWorktree({ path })`)。内包設計・hook・`WT_KEEP_INTERNAL` の解説、「やらないこと」への追記も実施

### Changed

- `wt.test.zsh`: 内包化に伴い setup で `WT_KEEP_INTERNAL=1` を立て、一度 `wt` を呼んでヘルパをグローバル展開してからホワイトボックステストを実行 (全36アサーション維持)

## [1.1.0] - 2026-05-27

### Changed

- `wt claude` の既定挙動を変更: description を初期プロンプトに**必ず**渡す方式をやめ、`claude --bg` で **idle セッション**を起動するようにした (「単にセッションを立ち上げたいだけ」のとき勝手にタスクが走り出す問題への対応)

### Added

- `wt claude -t [task]`: タスク投入をオプトイン化。`-t` のみで `wt.description` をタスク投入、`-t "<文>"` で任意文を投入。`-t` 指定で description が空の場合のみプロンプトでタスク文を確認
- 不正引数 (`wt claude badarg`) を fzf/claude 起動前に拒否
- `wt.test.zsh` に `wt claude` 引数バリデーションのテストを追加 (計 36 アサーション)

## [1.0.0] - 2026-05-27

### Added

- 初期リリース
- `wt.zsh`: git worktree 管理の zsh 関数群 (`wt` / `wt new` / `wt ls` / `wt set` / `wt rm` / `wt claude` / `wt cd`)
  - fzf ベースの選択 UI + プレビュー (BRANCH / PATH / AGE / DESCRIPTION)
  - `wt new` の配置自動検出 (direct パターン `~/<repo>-worktrees/` / parent パターン)
  - `git config --worktree wt.description` による per-worktree メタデータ。初回書き込み時に `extensions.worktreeConfig` を自動有効化
  - `wt.baseRef` による `wt new` の base ref デフォルト
- `wt.test.zsh`: 32 アサーションのテストスイート (純粋ロジック + git 実操作、一時リポジトリで検証)
- `skills/wt-manager/SKILL.md`: Claude 向け動線。`git worktree add` 直叩きを避け `wt new -d` 経由で作成、PR 後の description 更新、並列実行の `wt claude` 化を規定
- 配布形態: 実装本体は dotfiles 側を正本とし、`.zshrc` から相対パス (`${${(%):-%x}:A:h}/wt.zsh`) で source。プラグインには参照用スナップショットを同梱
