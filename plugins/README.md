# plugins

個人用の Claude Code プラグイン群。`.claude-plugin/marketplace.json` でマーケットプレイス (`kuu13580-marketplace`) として束ねている。各プラグインの詳細は同梱の個別 README を参照。

## プラグイン一覧

### sparkline-statusline (v1.3.2)

スパークラインゲージでコンテキスト使用率・レートリミット (5h / 7d)・prompt cache を Claude Code のステータスラインに表示する。Desktop app では同梱の mod がプロンプト上の band に同じ形式で表示する。PR 番号は Claude Code 標準の footer PR バッジが担当 (clickable にならない端末は `FORCE_HYPERLINK=1 claude` で起動)。
→ [sparkline-statusline/README.md](sparkline-statusline/README.md)

### pr-bot-watcher (v0.2.2)

GitHub PR の bot レビューコメント (Copilot / Claude / Gemini 等) を3分間隔で監視し、検出時点で cron を自己削除して修正要否を提案するワンショット型ウォッチャー。`/pr-bot-watcher [<PR番号> | stop]`。
→ [pr-bot-watcher/README.md](pr-bot-watcher/README.md)

### wt-manager (v1.10.1)

git worktree を fzf ベースの `wt` 系コマンドで管理し、各 worktree の用途を git config に記録する。Claude には `git worktree add` の直叩きを避け `wt new` 経由での作成を促す。
→ [wt-manager/README.md](wt-manager/README.md)

### web-search (v0.1.1)

揺らぐ事実 (ライブラリのバージョン、料金、リリース、最新動向など) が話題になったら、内部知識で即答せず WebSearch / WebFetch で一次情報を取りに行ってから回答させる skill。
→ [web-search/README.md](web-search/README.md)

### check-review-validity (v1.0.0)

自分が書いた未 submit のドラフトレビュー (GitHub の Pending review) を submit 前に検証し、各指摘を ✅ 妥当 / ✏️ 要修正 / ❌ 取り下げ推奨 / ❓ 要確認 に分類して理由付きでレポートする read-only スキル。`/check-review-validity [<PR番号> | <PR URL>]`。
→ [check-review-validity/README.md](check-review-validity/README.md)

### explain-change (v1.0.0)

PR / commit / ブランチ / 現 worktree の変更を調査し、その領域を知らない読者がゼロから読み解ける長文解説を Artifact として publish する read-only スキル。`/explain-change [<PR番号> | <PR URL> | <commit> | <A..B> | <ブランチ名>]`。
→ [explain-change/README.md](explain-change/README.md)

### prepare-context (v0.4.0)

セッションや compact を跨いでも設計判断が失われないよう、確認した事実と決定を `~/.claude/contexts/<repo>/<key>/CONTEXT.md` に残し、`SessionStart` フックが (compact 後も含めて) 自動的に読み戻す。`/prepare-context <調査 | 設計 | 実装 | pr>`。
→ [prepare-context/README.md](prepare-context/README.md)

### rebase-with-context (v0.1.0)

rebase のコンフリクトを、base 側で該当行を変更した PR と自分のコミット・PR の文脈を読んだ上で解消する。引用できる根拠がある箇所だけ自動で解消して完了後にサマリで報告し、根拠のない箇所は承認モードにかかわらずユーザーに確認する。`/rebase-with-context [<base>]`。
→ [rebase-with-context/README.md](rebase-with-context/README.md)

### pr-review (v0.4.2)

他人の PR をレビューする作法を通すスキル。個人指名の依頼抽出 → 不具合 / 規約 / 仕様・設計の確認事項に切り分け (規約は引用必須) → テストによる再検証 → 検証できたものだけ pending 投稿 → 修正確認 → Resolve / Approve。submit は行わず、Approve / 返信 / Resolve は承認後にのみ実行する。`/pr-review [<PR番号> | <PR URL>] [--review | --verify] [--explain]`。
→ [pr-review/README.md](pr-review/README.md)

### code-peek (v0.1.0)

返答中の `path:line` をクリックすると、そのファイルを pane に開いて該当行までスクロールする mod (fullscreen 表示の端末のみ)。ファイル名だけの参照も `git ls-files` から解決する。クリックできない環境では `/peek <path>:<line>`。
→ [code-peek/README.md](code-peek/README.md)

### remove-ai-tone (v1.0.0)

抽象的・演出的な AI 特有のトーンを排し、具体的で直接伝わる日本語で出力させる出力スタイル (output style) プラグイン。`/output-style Remove AI Tone`。
→ [remove-ai-tone/README.md](remove-ai-tone/README.md)

---

新しいプラグインを追加したら、この一覧と `.claude-plugin/marketplace.json` に追記する。
廃止するプラグインは削除せず `deprecated/` に退避する → [deprecated/README.md](deprecated/README.md)
