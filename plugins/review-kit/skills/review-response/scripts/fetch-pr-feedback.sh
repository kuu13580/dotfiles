#!/usr/bin/env bash
# fetch-pr-feedback.sh
# review-response 用: 自分の PR に来た未解決の指摘 (スレッド・レビュー本文・PR コメント) と、レビュアーの状態を JSON で出す
# Usage: bash fetch-pr-feedback.sh [<PR番号|PR URL>]
# Exit codes: 0 = 成功 / 1 = エラー / 3 = 未解決の指摘が無い / 4 = カレントブランチに PR が無い

set -euo pipefail

target="${1:-}"
for cmd in gh jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません。" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh が未認証です。\`gh auth login\` を実行してください。" >&2; exit 1; }

if [[ -z "$target" ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  if ! number=$(gh pr view --json number --jq .number 2>&1); then
    if [[ "$number" == *"no pull requests found"* ]]; then
      echo "カレントブランチに対応する PR が見つかりません。PR 番号を指定してください。" >&2; exit 4
    fi
    echo "PR の取得に失敗しました: $number" >&2; exit 1
  fi
elif [[ "$target" =~ ^[0-9]+$ ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner); number="$target"
elif [[ "$target" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
else
  echo "引数の形式が不正です (github.com の PR URL か PR 番号のみ対応): '$target'" >&2; exit 1
fi
me=$(gh api user --jq .login)

raw=$(gh api graphql -f owner="${repo%%/*}" -f name="${repo##*/}" -F number="$number" -f query='
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      number title url state isDraft headRefName headRefOid baseRefName
      headRepository { nameWithOwner }
      author { login }
      reviewThreads(first:100){ pageInfo { hasNextPage } nodes {
        id isResolved isOutdated path line originalLine
        comments(first:50){ totalCount nodes { databaseId author { __typename login } body createdAt } }
        last: comments(last:1){ nodes { author { __typename login } body createdAt } }
      } }
      reviews(last:50){ nodes { author { __typename login } state body submittedAt url } }
      latestReviews(first:50){ nodes { author { __typename login } state submittedAt } }
      reviewRequests(first:30){ nodes { requestedReviewer { __typename ... on User { login } ... on Bot { login } ... on Mannequin { login } ... on Team { slug } } } }
      comments(last:100){ nodes { databaseId author { __typename login } body createdAt url } }
    }
  }
}' 2>&1) || true
msg=$(echo "$raw" | jq -r '[.errors[]?.message] | join(" / ")' 2>/dev/null || echo "")
[[ -n "$msg" ]] && { echo "GitHub API がエラーを返しました: $msg" >&2; exit 1; }
echo "$raw" | jq -e '.data.repository.pullRequest' >/dev/null 2>&1 || {
  echo "GitHub API の呼び出しに失敗しました: $(echo "$raw" | head -3)" >&2; exit 1; }

out=$(echo "$raw" | jq --arg me "$me" --arg repo "$repo" '
  def bot: . == null or .__typename == "Bot" or ((.login // "") | test("\\[bot\\]$"));
  def who: .login // "ghost";
  .data.repository.pullRequest as $pr
  # PR 作成者のコメント本文。元の指摘の URL を含むものだけを、その指摘への返信とみなす
  | ([$pr.comments.nodes[] | select(.author.login == $pr.author.login) | .body] | join("\n")) as $replies
  | {repo: $repo, me: $me,
     pr: {number: $pr.number, title: $pr.title, url: $pr.url, state: $pr.state, is_draft: $pr.isDraft,
          author: $pr.author.login, is_mine: ($pr.author.login == $me),
          head: $pr.headRefName, head_oid: $pr.headRefOid, head_repo: $pr.headRepository.nameWithOwner,
          base: $pr.baseRefName},
     threads_truncated: $pr.reviewThreads.pageInfo.hasNextPage,
     # 人のレビューが1件でもあれば、修正は amend せず追加 commit にする (latestReviews はレビュアーごとの最新なので件数で漏れにくい)
     human_reviewed: ([$pr.latestReviews.nodes[] | select(.author.login != $me and .author.login != $pr.author.login)
                       | select(.author | bot | not)] | length > 0),
     threads: [$pr.reviewThreads.nodes[] | select(.isResolved | not)
       | select(.comments.nodes[0].author.login != $me)
       | {id, path, line: (.line // .originalLine), is_outdated: .isOutdated,
          reply_to_comment_id: .comments.nodes[0].databaseId,
          author: (.comments.nodes[0].author | who), is_bot: (.comments.nodes[0].author | bot),
          last_by_me: (.last.nodes[0].author.login == $me),
          comments_truncated: (.comments.totalCount > (.comments.nodes | length)),
          comments: [.comments.nodes[] | {author: (.author | who), body, at: .createdAt}],
          last_comment: (.last.nodes[0] | {author: (.author | who), body, at: .createdAt})}],
     review_bodies: [$pr.reviews.nodes[] | select(.author.login != $me and .author.login != $pr.author.login)
       | select(.body != "")
       | {author: (.author | who), is_bot: (.author | bot), state, body, at: .submittedAt, url,
          answered: (.url as $u | $replies | contains($u))}],
     pr_comments: [$pr.comments.nodes[] | select(.author.login != $me and .author.login != $pr.author.login)
       | {id: .databaseId, author: (.author | who), is_bot: (.author | bot), body, at: .createdAt, url,
          answered: (.url as $u | $replies | contains($u))}],
     latest_reviews: [$pr.latestReviews.nodes[] | {author: (.author | who), is_bot: (.author | bot), state, at: .submittedAt}],
     pending_requests: [$pr.reviewRequests.nodes[].requestedReviewer | select(. != null)
       | if .slug then "team:" + .slug else .login end]}')

# 長い本文は途中で切ると指摘が落ちる (bot のレビュー本文は数万字になる) ため、全文をファイルに置いて先頭だけ JSON に残す
body_dir="${TMPDIR:-/tmp}/review-kit-feedback/${repo//\//_}-$number"
out=$(echo "$out" | python3 -c '
import json, os, sys
d = json.load(sys.stdin); body_dir = sys.argv[1]; limit = 4000
def spill(item, name):
    if len(item.get("body") or "") <= limit:
        return
    os.makedirs(body_dir, exist_ok=True)
    path = os.path.join(body_dir, name + ".md")
    with open(path, "w") as f:
        f.write(item["body"])
    item["body"] = item["body"][:limit] + "\n…(続きは body_file)"
    item["body_file"] = path
for i, r in enumerate(d["review_bodies"]): spill(r, f"review-{i}")
for i, c in enumerate(d["pr_comments"]): spill(c, f"comment-{i}")
for i, t in enumerate(d["threads"]):
    for j, c in enumerate(t["comments"]): spill(c, f"thread-{i}-{j}")
    spill(t["last_comment"], f"thread-{i}-last")
print(json.dumps(d, ensure_ascii=False, indent=2))
' "$body_dir")

echo "$out"
# 取り切れていないときは「指摘が無い」と言い切れないので exit 3 にしない
[[ "$(echo "$out" | jq .threads_truncated)" == "true" ]] && exit 0
open_count=$(echo "$out" | jq '([.threads[] | select(.last_by_me | not)] | length)
  + ([.review_bodies[] | select(.answered | not)] | length) + ([.pr_comments[] | select(.answered | not)] | length)')
[[ "$open_count" == "0" ]] && exit 3
exit 0
