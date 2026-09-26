# Antigravity グローバルルール & Claude スキル読み替え規約

## 1. 共通開発・コミット規約 (dotfiles/CLAUDE.md より継承)

@[CLAUDE.md](~/dotfiles/CLAUDE.md)

---

## 2. Claude プラグイン・スキルの解釈・実行規約

`~/dotfiles/plugins/` 配下の Claude 向けスキル (`SKILL.md`) を実行する際は、以下のルールに従って自身 (Antigravity) の環境・ツールに読み替えて自律的に適応すること。

### ツール名のマッピング
スキル内の指示や手順に含まれる Claude 固有のツール名は、対応する Antigravity ツールに読み替えて実行する:
- `WebSearch` → `search_web`
- `WebFetch` → `read_url_content`
- `Bash` → `run_command`
- `Read` → `view_file`
- `Edit` / `Write` → `replace_file_content` / `write_to_file`
- `AskUserQuestion` → `ask_question`
- `CronCreate` → `schedule` ツール (引数: `CronExpression`, `Prompt`, `IsDaemon=false`)
- `CronList` / `CronDelete` → `manage_task` ツール (引数: `Action="list"` または `Action="kill"`)

### 環境変数 `${CLAUDE_PLUGIN_ROOT}` のパス解決
スキル内のスクリプト実行コマンドに含まれる `${CLAUDE_PLUGIN_ROOT}` は、該当プラグインのルートディレクトリパス（`~/dotfiles/plugins/<プラグイン名>`）として展開して実行すること。
- 例: `${CLAUDE_PLUGIN_ROOT}/skills/check-review-validity/scripts/fetch-pending-review.sh`
  → `~/dotfiles/plugins/check-review-validity/skills/check-review-validity/scripts/fetch-pending-review.sh`

### 成果物 (Artifact) の出力
成果物を Artifact として出力する指示（`explain-change` スキル等）がある場合は、Antigravity の Artifact ディレクトリ（`<appDataDir>/brain/<conversation-id>/`）に出力し、ユーザーが閲覧できるようにリンクを提示すること。

### Worktree 管理 (`wt-manager`)
Git worktree を作成・削除する際は、`git worktree add` / `remove` の直接実行を避け、`wt new` / `wt rm` コマンドを使用すること。
