#!/usr/bin/env bash
# 開始前の状態判定と base の決定 (read-only)。結果を JSON で stdout に出す。
#
# usage: prepare.sh [<base>]
# exit: 0=決定 / 1=エラー / 2=base を決められない (候補を JSON で出す) / 3=未コミット変更あり / 4=detached HEAD
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
require_tools

ARG="${1:-}"
GH_REPO=$(github_repo) || GH_REPO=""

# ---------------------------------------------------------------- 途中引き継ぎ
if in_rebase; then
  rd=$(rebase_dir)
  unmerged=$(git diff --name-only --diff-filter=U | to_json_array)
  # マーカーが無いのに unmerged = rerere が当てた or ユーザーが編集して未 add
  no_marker=$(git diff --name-only --diff-filter=U | while IFS= read -r f; do
    [ -f "$f" ] && ! grep -qE '^<{7}( |$)' "$f" && echo "$f"
  done | to_json_array)
  jq -n \
    --arg branch "$(rebase_branch)" \
    --arg onto "$(cat "$rd/onto" 2>/dev/null)" \
    --arg orig_head "$(cat "$rd/orig-head" 2>/dev/null)" \
    --arg msgnum "$(cat "$rd/msgnum" 2>/dev/null)" \
    --arg end "$(cat "$rd/end" 2>/dev/null)" \
    --argjson has_state "$([ -f "$(state_file)" ] && echo true || echo false)" \
    --argjson unmerged "$unmerged" --argjson no_marker "$no_marker" \
    --arg repo "$GH_REPO" \
    '{mode: "resume", branch: $branch, onto: $onto, orig_head: $orig_head,
      progress: "\($msgnum)/\($end)", has_state: $has_state,
      unmerged: $unmerged, unmerged_without_markers: $no_marker,
      github_repo: (if $repo == "" then null else $repo end)}'
  exit 0
fi

BRANCH=$(git symbolic-ref --quiet --short HEAD) || { echo "detached HEAD では実行できません。ブランチを checkout してください。" >&2; exit 4; }

if [ -f "$(state_file)" ]; then
  die "前回の実行の状態ファイルが残っています ($(state_file))。rebase-step.sh abort で片付けてから再実行してください。"
fi

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  echo "未コミットの変更があります。commit するか退避してから再実行してください (stash は worktree 間で共有されるため自動では行いません)。" >&2
  exit 3
fi

HAS_ORIGIN=false
git remote get-url origin >/dev/null 2>&1 && HAS_ORIGIN=true

# origin/<name> を優先し、無ければローカル。どちらも無ければ任意の rev として解決を試みる
resolve_ref() {
  local name="${1#refs/heads/}"
  name="${name#refs/remotes/}"
  name="${name#origin/}"
  if $HAS_ORIGIN; then
    git fetch --quiet origin "$name" 2>/dev/null
    if git rev-parse --verify --quiet "refs/remotes/origin/$name" >/dev/null; then echo "origin/$name"; return 0; fi
  fi
  if git rev-parse --verify --quiet "refs/heads/$name" >/dev/null; then echo "$name"; return 0; fi
  git rev-parse --verify --quiet "$1^{commit}" >/dev/null && { echo "$1"; return 0; }
  return 1
}

normalize() { local n="${1#refs/heads/}"; n="${n#refs/remotes/}"; echo "${n#origin/}"; }

SRC_PR=""
[ -n "$GH_REPO" ] && SRC_PR=$(gh pr view "$BRANCH" --json baseRefName -q .baseRefName 2>/dev/null) || true
SRC_REFLOG=$(git reflog show --format=%gs "refs/heads/$BRANCH" 2>/dev/null | tail -n 1 | sed -n 's/^branch: Created from //p')
case "$SRC_REFLOG" in HEAD | "") SRC_REFLOG="" ;; *) SRC_REFLOG=$(normalize "$SRC_REFLOG") ;; esac
SRC_UPSTREAM=$(git config "branch.$BRANCH.merge" 2>/dev/null) || SRC_UPSTREAM=""
SRC_UPSTREAM=$(normalize "$SRC_UPSTREAM")
[ "$SRC_UPSTREAM" = "$BRANCH" ] && SRC_UPSTREAM=""

SOURCE=""; CHOSEN=""
if [ -n "$ARG" ]; then SOURCE="arg"; CHOSEN="$ARG"
elif [ -n "$SRC_PR" ]; then SOURCE="pr"; CHOSEN="$SRC_PR"
elif [ -n "$SRC_REFLOG" ]; then SOURCE="reflog"; CHOSEN="$SRC_REFLOG"
elif [ -n "$SRC_UPSTREAM" ]; then SOURCE="upstream"; CHOSEN="$SRC_UPSTREAM"
fi

sources_json=$(jq -n --arg pr "$SRC_PR" --arg reflog "$SRC_REFLOG" --arg upstream "$SRC_UPSTREAM" \
  '{pr: $pr, reflog: $reflog, upstream: $upstream} | with_entries(.value |= if . == "" then null else . end)')

if [ -z "$CHOSEN" ]; then
  # 候補: デフォルトブランチ + merge-base からの自分のコミット数が少ないリモートブランチ
  default=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)
  near=$(git for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | grep -vE "^origin(/HEAD)?$|^origin/$BRANCH$" | head -n 50 | \
    while IFS= read -r r; do
      mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
      printf '%s\t%s\n' "$(git rev-list --count "$mb..HEAD")" "$r"
    done | sort -n | head -n 3 | cut -f2)
  { [ -n "$default" ] && echo "$default"; echo "$near"; } | awk 'NF && !seen[$0]++' | to_json_array | \
    jq --argjson sources "$sources_json" '{mode: "new", base: null, sources: $sources, candidates: .}'
  exit 2
fi

BASE=$(resolve_ref "$CHOSEN") || die "base '$CHOSEN' ($SOURCE) を解決できません。"

conflict=false
[ -n "$SRC_PR" ] && [ -n "$SRC_REFLOG" ] && [ "$SRC_PR" != "$SRC_REFLOG" ] && conflict=true

# base..HEAD の途中を指している他ブランチ (--update-refs は使わないので置き去りになる)
MB=$(git merge-base HEAD "$BASE")
mids=$(git for-each-ref --format='%(objectname) %(refname:short)' refs/heads | \
  awk 'NR == FNR { own[$1] = 1; next } own[$1] { print $2 }' <(git rev-list "$MB..HEAD~1" 2>/dev/null) - | to_json_array)

jq -n \
  --arg branch "$BRANCH" --arg head "$(git rev-parse HEAD)" \
  --arg base "$BASE" --arg source "$SOURCE" --argjson sources "$sources_json" \
  --argjson conflict "$conflict" --argjson mids "$mids" \
  --arg merge_base "$MB" \
  --argjson behind "$(git rev-list --count "HEAD..$BASE")" \
  --argjson commits "$(git log --format='%h %s' --reverse "$MB..HEAD" | to_json_array)" \
  --arg repo "$GH_REPO" \
  '{mode: "new", branch: $branch, head: $head, base: $base, base_source: $source,
    sources: $sources, sources_disagree: $conflict, merge_base: $merge_base,
    base_ahead_by: $behind, commits: $commits, intermediate_branches: $mids,
    github_repo: (if $repo == "" then null else $repo end)}'
