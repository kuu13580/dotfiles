#!/usr/bin/env bash
# SessionStart フック: 引き継ぎ記録を stdout から文脈へ流し込む。
#
# 注入は stdout を使う。プラグイン同梱の SessionStart では hookSpecificOutput.additionalContext が
# Claude に渡らない既知の不具合があり修正予定もない (anthropics/claude-code#16538)。
set -uo pipefail

MAX_LINES=400
MAX_BYTES=24576

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

lines=$(wc -l < "$RECORD")
bytes=$(wc -c < "$RECORD")
if [ "$lines" -gt "$MAX_LINES" ] || [ "$bytes" -gt "$MAX_BYTES" ]; then
  printf '\n---\nprepare-context: 記録が上限を超えています (%s行 / %sbytes、上限 %s行 / %sbytes)。次に `/prepare-context` を実行する際、撤回された決定と詳細な根拠を CONTEXT.archive.md へ移せるか見直してください。**要約による圧縮はしないこと。**選択肢は「archive へ移す」か「そのまま残す」の2つだけです。\n' \
    "$lines" "$bytes" "$MAX_LINES" "$MAX_BYTES"
fi

if [ "$SOURCE" = "compact" ]; then
  printf '\n---\nprepare-context: 直前に compact が発生しました。上の記録と圧縮サマリを突き合わせ、記録に無い決定・確認した事実があれば、作業を再開する前に `/prepare-context <フェーズ>` で追記してください。\n'
fi
