#!/bin/bash
# wt-manager PreToolUse hook
#
# worktree モデルの二重化を防ぐためのガード:
#   - EnterWorktree の name モード(新規worktree作成)を deny。新規作成は wt new で行う
#     (wt は internal ヘルパを wt() 内包化したため、Claude の zsh からも wt new が動く)
#   - ExitWorktree の action:"remove" を deny。削除は wt rm が担当する
# 既存 worktree へ入る EnterWorktree({ path }) / 退出 ExitWorktree({ action:"keep" }) は許可。
#
# stdin: PreToolUse イベント JSON。stdout: 何も出さなければ許可、deny JSON で拒否。

INPUT=$(cat)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')

deny() {
  jq -n --arg r "$1" \
    '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}'
  exit 0
}

case "$TOOL" in
  EnterWorktree)
    NAME=$(printf '%s' "$INPUT" | jq -r '.tool_input.name // empty')
    if [ -n "$NAME" ]; then
      deny "wt-manager: EnterWorktree の name モード(新規worktree作成)は禁止です。
理由: .claude/worktrees/ 配下に origin/<default> から切る挙動で、wt の description メタデータも配置規約(parent パターン)も無視されるため。

新規作成は wt で行ってください(wt new は Claude の zsh からも動作します):
  wt new -b <branch> <dir> [base-ref] -d \"<目的>\"
作成後、その絶対パスで入る:
  EnterWorktree({ path: \"<wt ls -p / git worktree list で得た絶対パス>\" })

既存 worktree へ移るだけなら name ではなく path を指定してください。"
    fi
    ;;
  ExitWorktree)
    ACTION=$(printf '%s' "$INPUT" | jq -r '.tool_input.action // empty')
    if [ "$ACTION" = "remove" ]; then
      deny "wt-manager: ExitWorktree の action:\"remove\" は禁止です。
退出は ExitWorktree({ action: \"keep\" }) を使い、worktree の削除は wt rm で行ってください(ブランチ削除の対話確認や description 管理を wt rm が担うため)。"
    fi
    ;;
esac

exit 0
