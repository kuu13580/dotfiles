#!/usr/bin/env bash
# list-review-prs.sh
# pr-review 用: レビュー対象の PR を 2 バケツで出す
#   requested    = 自分が「個人指名」でレビュー依頼されている open PR (チーム依頼のみのものは除く)
#   awaiting_fix = 自分が CHANGES_REQUESTED を出した後に head が進んだ open PR
# Usage: bash list-review-prs.sh
# Exit codes: 0 = 成功 (stdout に JSON) / 1 = エラー / 3 = 対象 0 件

set -euo pipefail

for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません。インストールしてください。" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh が未認証です。\`gh auth login\` を実行してください。" >&2; exit 1; }

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1) || {
  echo "カレントディレクトリの GitHub リポジトリを特定できませんでした: $repo" >&2
  exit 1
}
me=$(gh api user --jq .login)

# --- requested: review-requested は チーム経由の依頼も拾うため、User 指名だけに絞る ---
requested=$(gh pr list --repo "$repo" --search "review-requested:@me" --state open --limit 50 \
  --json number,title,url,author,isDraft,reviewRequests,updatedAt 2>/dev/null \
  | jq --arg me "$me" '[ .[]
      | select(.isDraft | not)
      | select(any(.reviewRequests[]; .__typename == "User" and .login == $me))
      | {number, title, url, author: .author.login, updatedAt} ]')

# --- awaiting_fix: 自分の最新レビューが CHANGES_REQUESTED かつ head がレビュー時点の commit から進んでいる ---
reviewed=$(gh api graphql -f q="repo:$repo is:pr is:open reviewed-by:$me" -f me="$me" -f query='
query($q: String!, $me: String!) {
  search(query: $q, type: ISSUE, first: 50) {
    nodes {
      ... on PullRequest {
        number title url isDraft updatedAt headRefOid
        author { login }
        reviews(author: $me, states: [CHANGES_REQUESTED, APPROVED], last: 1) { nodes { state submittedAt commit { oid } } }
      }
    }
  }
}' 2>/dev/null) || reviewed='{}'

awaiting=$(echo "$reviewed" | jq '[ (.data.search.nodes // [])[]
    | select(.number != null)
    | select(.isDraft | not)
    | . as $pr
    | .reviews.nodes[0] as $mine
    | select($mine != null and $mine.state == "CHANGES_REQUESTED")
    | select($mine.commit.oid != $pr.headRefOid)
    | {number: $pr.number, title: $pr.title, url: $pr.url, author: $pr.author.login,
       reviewed_at: $mine.submittedAt} ]')

# 両方に出る PR (修正後に再依頼されたもの) は awaiting_fix 側だけに残す
jq -n --arg repo "$repo" --arg me "$me" \
  --argjson requested "$requested" --argjson awaiting "$awaiting" \
  '($awaiting | map(.number)) as $fix
   | {repo: $repo, me: $me,
      requested: ($requested | map(select(.number as $n | $fix | index($n) | not))),
      awaiting_fix: $awaiting}'

count=$(jq -n --argjson r "$requested" --argjson a "$awaiting" '($r | length) + ($a | length)')
if [[ "$count" == "0" ]]; then
  exit 3
fi
exit 0
