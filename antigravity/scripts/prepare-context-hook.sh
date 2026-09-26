#!/usr/bin/env bash
# Antigravity PreInvocation フック用アダプタ: prepare-context の記録を注入する
set -uo pipefail

INPUT=$(cat)

# 初回インボケーション (invocationNum == 1) のみ実行する
INVOCATION_NUM=$(printf '%s' "$INPUT" | jq -r '.invocationNum // 1' 2>/dev/null)
if [ "$INVOCATION_NUM" != "1" ]; then
  echo "{}"
  exit 0
fi

# 対象のワークスペースパスを取得
WORKSPACE=$(printf '%s' "$INPUT" | jq -r '(.workspacePaths[0] // empty)' 2>/dev/null)
if [ -n "$WORKSPACE" ] && [ -d "$WORKSPACE" ]; then
  cd "$WORKSPACE" 2>/dev/null || true
fi

PLUGIN_ROOT="$HOME/dotfiles/plugins/prepare-context"
if [ ! -d "$PLUGIN_ROOT" ]; then
  echo "{}"
  exit 0
fi

# キー解決
KEY=$(bash "$PLUGIN_ROOT/scripts/resolve-key.sh" 2>/dev/null) || {
  echo "{}"
  exit 0
}

DIR="$HOME/.claude/contexts/$KEY"
RECORD="$DIR/CONTEXT.md"

if [ ! -f "$RECORD" ]; then
  MSG=$(printf 'prepare-context: `%s` の引き継ぎ記録はまだありません。設計が固まった時点で `/prepare-context 設計` を実行し、%s に書き出してください。' "$KEY" "$RECORD")
  jq -n --arg msg "$MSG" '{"injectSteps": [{"ephemeralMessage": $msg}]}'
  exit 0
fi

# 記録を読み込み
CONTENT=$(cat "$RECORD")
HEADER=$(printf '<!-- prepare-context: %s を自動読み込み。確定済みの事実と決定です -->\n\n' "$RECORD")
FULL_MSG="${HEADER}${CONTENT}"

# 警報水準チェック
MAX_BYTES=65536
BYTES=$(wc -c < "$RECORD")
if [ "$BYTES" -gt "$MAX_BYTES" ]; then
  WARNING=$(printf '\n---\nprepare-context: 記録が警報水準を超えています (%s bytes / 水準 %s bytes)。肥大化していないか点検してください。' "$BYTES" "$MAX_BYTES")
  FULL_MSG="${FULL_MSG}${WARNING}"
fi

jq -n --arg msg "$FULL_MSG" '{"injectSteps": [{"ephemeralMessage": $msg}]}'
