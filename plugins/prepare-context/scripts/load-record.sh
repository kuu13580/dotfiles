#!/usr/bin/env bash
# SessionStart フック: 引き継ぎ記録を stdout から文脈へ流し込む。
#
# 注入は stdout を使う。プラグイン同梱の SessionStart では hookSpecificOutput.additionalContext が
# Claude に渡らない既知の不具合があり修正予定もない (anthropics/claude-code#16538)。
set -uo pipefail

# 分量の上限ではなく、記録がログへ変質したことを知らせる警報の水準。
# 実運用の記録の実測 (中央値 19KB / 最大 61KB) の上に余裕を取っている。
MAX_BYTES=65536

INPUT=$(cat)
SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null) || SOURCE=""
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""

[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

KEY=$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-key.sh") || exit 0
DIR="$HOME/.claude/contexts/$KEY"
RECORD="$DIR/CONTEXT.md"

# set-key.sh 導入前 (v0.3.x 以前) に設定したキーは紐付けが無く、複製と区別できないため無視される
legacy_key=$(git config prepare-context.key 2>/dev/null) || legacy_key=""
if [ -n "$legacy_key" ] && [ -z "$(git config prepare-context.keyOwner 2>/dev/null)" ]; then
  printf 'prepare-context: 明示キー `%s` は worktree との紐付けが無いため無視し、`%s` で解決しました。この worktree のキーなら `%s/scripts/set-key.sh %s` を、別 worktree から複製されたものなら `git config --worktree --unset prepare-context.key` を実行してください。\n\n' \
    "$legacy_key" "$KEY" "$CLAUDE_PLUGIN_ROOT" "$legacy_key"
fi

if [ ! -f "$RECORD" ]; then
  printf 'prepare-context: `%s` の引き継ぎ記録はまだありません。設計が固まった時点で `/prepare-context 設計` を実行し、%s に書き出してください。\n' \
    "$KEY" "$RECORD"
  exit 0
fi

printf '<!-- prepare-context: %s を自動読み込み。このタスクで確定済みの事実と決定です -->\n\n' "$RECORD"
cat "$RECORD"

bytes=$(wc -c < "$RECORD")
if [ "$bytes" -gt "$MAX_BYTES" ]; then
  printf '\n---\nprepare-context: 記録が警報水準を超過 (%s / %s bytes)。上限ではなく、ログへの変質の合図。次の更新時に以下だけ点検し、該当が無ければそのままでよい。\n- 決着した調査の現在地 → 結論を事実に残し、現在地は CONTEXT.archive.md へ\n- 撤回・置き換えた決定 → archive へ\n- 探索の経路・生ログ → 取り除く\n- 同じ論点の食い違い → 事実・状態は今の値に書き換え、旧い決定は archive へ\n- 完了したタスク (マージ済みなど) → ユーザーに確認のうえディレクトリごと削除\n現役の根拠は archive へ移さない (注入されなくなる)。要約で縮めない。迷ったら残す。\n' \
    "$bytes" "$MAX_BYTES"
fi

if [ "$SOURCE" = "compact" ]; then
  printf '\n---\nprepare-context: 直前に compact が発生しました。上の記録と圧縮サマリを突き合わせ、記録に無い決定・確認した事実があれば、作業を再開する前に `/prepare-context <フェーズ>` で追記してください。\n'
fi
