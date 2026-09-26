#!/usr/bin/env bash
# Antigravity PreToolUse フック: run_command での git worktree 直接操作をブロックする
set -uo pipefail

INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '(.toolCall.args.CommandLine // .toolCall.args.command // empty)' 2>/dev/null)

if [ -z "$CMD" ]; then
  echo "{}"
  exit 0
fi

# git worktree add または git worktree remove (rm) を検出
# (git と worktree の間の -C 等のオプションも許容、引数内文字列は除外)
if echo "$CMD" | grep -E '(^|[;&|])\s*git(\s+[^;&|]+)?\s+worktree\s+(add|remove|rm)\b' >/dev/null 2>&1; then
  REASON="git worktree の直接操作 (add/remove) は禁止されています。worktree の新規作成には 'wt new'、削除には 'wt rm' を使用してください。"
  jq -n --arg reason "$REASON" '{
    "decision": "deny",
    "reason": $reason
  }'
  exit 0
fi

# 許可
echo '{"decision": "allow"}'
