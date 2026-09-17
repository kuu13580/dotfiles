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

if [ ! -f "$RECORD" ]; then
  printf 'prepare-context: `%s` の引き継ぎ記録はまだありません。設計が固まった時点で `/prepare-context 設計` を実行し、%s に書き出してください。\n' \
    "$KEY" "$RECORD"
  exit 0
fi

printf '<!-- prepare-context: %s を自動読み込み。このタスクで確定済みの事実と決定です -->\n\n' "$RECORD"
cat "$RECORD"

bytes=$(wc -c < "$RECORD")
if [ "$bytes" -gt "$MAX_BYTES" ]; then
  printf '\n---\nprepare-context: 記録が警報水準を超えています (%s bytes / 水準 %s bytes)。これは分量の上限ではなく、記録が決定記録からログへ変質した可能性を知らせる合図です。次に `/prepare-context` を実行する際、以下だけ点検してください。\n\n- 決着した調査の「現在地」が残っていないか → 結論を事実として残し、現在地は CONTEXT.archive.md へ\n- 撤回・置き換えられた決定が残っていないか → CONTEXT.archive.md へ\n- 探索の経路・ツール出力の生ログが混ざっていないか → そもそも残さないものなので取り除く\n\n**該当が無ければそのままでよい。**現役の根拠は移さず、要約による圧縮もしない (archive は注入されないため、移した時点で後続には失われたのと同じになります)。判断がつかないものは残す側に倒す。\n' \
    "$bytes" "$MAX_BYTES"
fi

if [ "$SOURCE" = "compact" ]; then
  printf '\n---\nprepare-context: 直前に compact が発生しました。上の記録と圧縮サマリを突き合わせ、記録に無い決定・確認した事実があれば、作業を再開する前に `/prepare-context <フェーズ>` で追記してください。\n'
fi
