#!/usr/bin/env bash
# prune-review-memos.sh
# pr-review 用: 役目を終えた引き継ぎメモ (~/.claude/pr-review/<owner>/<repo>/<N>.md) を削除する
# 削除対象: PR が MERGED / CLOSED、または自分の最新の CHANGES_REQUESTED/APPROVED が APPROVED
# Usage: bash prune-review-memos.sh
set -euo pipefail

root="$HOME/.claude/pr-review"
[[ -d "$root" ]] || exit 0
mapfile -t memos < <(find "$root" -mindepth 3 -maxdepth 3 -name '*.md' | sort)
[[ ${#memos[@]} -eq 0 ]] && exit 0

gh auth status >/dev/null 2>&1 || { echo "gh が未認証です。\`gh auth login\` を実行してください。" >&2; exit 1; }
me=$(gh api user --jq .login)

pruned=0; kept=0; failed=0
for f in "${memos[@]}"; do
  rel=${f#"$root/"}
  owner=${rel%%/*}; rest=${rel#*/}; repo=${rest%%/*}; number=$(basename "$f" .md)
  [[ "$number" =~ ^[0-9]+$ ]] || continue
  if ! res=$(gh api graphql -F o="$owner" -F r="$repo" -F n="$number" -f me="$me" -f query='
    query($o: String!, $r: String!, $n: Int!, $me: String!) {
      repository(owner: $o, name: $r) { pullRequest(number: $n) {
        state
        reviews(author: $me, states: [CHANGES_REQUESTED, APPROVED], last: 1) { nodes { state } }
      } }
    }' 2>/dev/null); then
    msg=$(echo "$res" | jq -r '[.errors[]?.message] | join("; ")' 2>/dev/null || true)
    echo "skip:   $owner/$repo#$number — ${msg:-gh api 失敗}" >&2
    failed=$((failed + 1)); continue
  fi
  reason=$(echo "$res" | jq -r '
    .data.repository.pullRequest as $pr
    | $pr.reviews.nodes[0].state as $mine
    | if $pr.state != "OPEN" then $pr.state elif $mine == "APPROVED" then "APPROVED" else "" end')
  if [[ -n "$reason" ]]; then
    rm -f "$f"
    echo "pruned: $owner/$repo#$number ($reason)"
    pruned=$((pruned + 1))
  else
    kept=$((kept + 1))
  fi
done
find "$root" -mindepth 1 -type d -empty -delete
echo "pruned ${pruned} / kept ${kept} / skipped ${failed}"
