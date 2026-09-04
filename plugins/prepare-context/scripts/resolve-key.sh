#!/usr/bin/env bash
# 記録の置き場キー "<repo>/<key>" を解決する。hooks とスキルの両方から呼ばれる。
#
# 解決できたら stdout に1行出して exit 0、できなければ無出力で exit 1。
# default branch では自動解決を拒む。同一リポジトリの別タスクが同じキーを踏むと、
# 他タスクの決定表に追記して過去の決定を汚染するため (記録が無い状態より悪い)。
set -uo pipefail

git rev-parse --git-common-dir >/dev/null 2>&1 || exit 1

common_dir=$(git rev-parse --git-common-dir)
[ "${common_dir#/}" = "$common_dir" ] && common_dir="$(cd "$common_dir" && pwd)"
repo=$(basename "$(dirname "$common_dir")")

# パス区切りと空白を - に畳む
sanitize() { printf '%s' "$1" | tr '/[:space:]\\:*?"<>|' '-' ; }

is_default_branch() {
  case "$1" in
    main | master | develop | HEAD) return 0 ;;
  esac
  local origin_head
  origin_head=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null) || return 1
  [ "$1" = "${origin_head#origin/}" ]
}

# 明示キーが最優先。ブランチ名より先に見るのは、タスク途中でブランチを切っても
# 記録が孤立しないようにするため (main で調査 → ブランチを切って実装、が普通の流れ)
key=$(git config --worktree prepare-context.key 2>/dev/null) || key=""
[ -n "$key" ] || key=$(git config prepare-context.key 2>/dev/null) || key=""

if [ -n "$key" ]; then
  printf '%s/%s\n' "$repo" "$(sanitize "$key")"
  exit 0
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""

if [ -n "$branch" ] && ! is_default_branch "$branch"; then
  printf '%s/%s\n' "$repo" "$(sanitize "$branch")"
  exit 0
fi

exit 1
