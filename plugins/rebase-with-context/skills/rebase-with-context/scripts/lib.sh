# shellcheck shell=bash
# 各スクリプトから source する共通ヘルパ。

die() { echo "$1" >&2; exit 1; }

require_tools() {
  command -v git >/dev/null 2>&1 || die "git が見つかりません。"
  command -v jq  >/dev/null 2>&1 || die "jq が見つかりません (apt install jq / brew install jq)。"
  git rev-parse --git-dir >/dev/null 2>&1 || die "git リポジトリの中で実行してください。"
}

# rerere は過去の解消を無言で再適用し、判断を素通りさせるため、rebase 系は必ずこれを通す
git_rebase() { GIT_EDITOR=true git -c rerere.enabled=false rebase "$@"; }

# worktree ごとの git dir 配下 (他 worktree の rebase と混ざらない)
state_dir()  { git rev-parse --path-format=absolute --git-path rebase-with-context; }
state_file() { echo "$(state_dir)/state.json"; }

rebase_dir() {
  local d
  for d in rebase-merge rebase-apply; do
    d=$(git rev-parse --path-format=absolute --git-path "$d")
    [ -d "$d" ] && { echo "$d"; return 0; }
  done
  return 1
}
in_rebase() { rebase_dir >/dev/null; }

# rebase-merge/head-name は refs/heads/<branch>
rebase_branch() {
  local d; d=$(rebase_dir) || return 1
  sed 's#^refs/heads/##' "$d/head-name" 2>/dev/null
}

github_repo() {
  command -v gh >/dev/null 2>&1 || return 1
  gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null
}

to_json_array() { jq -R -s 'split("\n") | map(select(length > 0))'; }
