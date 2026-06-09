# plugins

個人用の Claude Code プラグイン群。`.claude-plugin/marketplace.json` でマーケットプレイス (`kuu13580-marketplace`) として束ねている。各プラグインの詳細は同梱の個別 README を参照。

## プラグイン一覧

### sparkline-statusline (v1.0.0)

スパークラインゲージでコンテキスト使用率・レートリミット (5h / 7d) を Claude Code のステータスラインに表示する。
→ [sparkline-statusline/README.md](sparkline-statusline/README.md)

### pr-bot-watcher (v0.2.2)

GitHub PR の bot レビューコメント (Copilot / Claude / Gemini 等) を3分間隔で監視し、検出時点で cron を自己削除して修正要否を提案するワンショット型ウォッチャー。`/pr-bot-watcher [<PR番号> | stop]`。
→ [pr-bot-watcher/README.md](pr-bot-watcher/README.md)

### html-output-generator (v1.0.0)

会話内容や markdown ファイルを sonnet サブエージェント経由でシンプルで見やすい HTML に変換する (重い生成処理を委譲してトークン消費を抑制)。`/html-output [<markdown-file-path>]`。
→ [html-output-generator/README.md](html-output-generator/README.md)

### wt-manager (v1.7.0)

git worktree を fzf ベースの `wt` 系コマンドで管理し、各 worktree の用途を git config に記録する。Claude には `git worktree add` の直叩きを避け `wt new` 経由での作成を促す。
→ [wt-manager/README.md](wt-manager/README.md)

---

新しいプラグインを追加したら、この一覧と `.claude-plugin/marketplace.json` に追記する。
