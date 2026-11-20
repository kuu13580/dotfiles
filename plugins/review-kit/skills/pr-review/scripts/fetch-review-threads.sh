#!/usr/bin/env bash
# fetch-review-threads.sh
# pr-review 用 (修正確認フェーズ): 自分が立てたレビュースレッドと、前回レビュー以降の変更を JSON で出力する
# Usage: bash fetch-review-threads.sh <PR番号|PR URL>
# Exit codes: 0 = 成功 / 1 = エラー / 3 = 自分のスレッドが 1 件もない

set -euo pipefail

target="${1:-}"
for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません。" >&2; exit 1; }
done

if [[ -z "$target" ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  number=$(gh pr view --json number --jq .number 2>/dev/null) || {
    echo "カレントブランチに対応する PR が見つかりません。PR 番号を指定してください。" >&2; exit 1; }
elif [[ "$target" =~ ^[0-9]+$ ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner); number="$target"
elif [[ "$target" =~ ^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
else
  echo "引数の形式が不正です: '$target'" >&2; exit 1
fi
owner="${repo%%/*}"; name="${repo##*/}"
me=$(gh api user --jq .login)

raw=$(gh api graphql -f owner="$owner" -f name="$name" -F number="$number" -f me="$me" -f query='
query($owner:String!,$name:String!,$number:Int!,$me:String!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      number title url state headRefOid headRefName baseRefName
      author { login }
      myReviews: reviews(author: $me, states: [CHANGES_REQUESTED, APPROVED], last: 1) { nodes { state submittedAt commit { oid } } }
      reviewThreads(first: 100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 20) { nodes { databaseId author { login } body createdAt } }
        }
      }
      commits(last: 50) { nodes { commit { oid messageHeadline committedDate } } }
    }
  }
}' 2>&1) || true
msg=$(echo "$raw" | jq -r '[.errors[]?.message] | join(" / ")' 2>/dev/null || echo "")
if [[ -n "$msg" ]]; then
  echo "GitHub API がエラーを返しました: $msg" >&2; exit 1
fi
echo "$raw" | jq -e '.data' >/dev/null 2>&1 || {
  echo "GitHub API の呼び出しに失敗しました: $(echo "$raw" | head -3)" >&2; exit 1
}

memo_path="$HOME/.claude/pr-review/$repo/$number.md"
memo_exists=$([[ -f "$memo_path" ]] && echo true || echo false)

out=$(echo "$raw" | jq --arg me "$me" --arg memo_path "$memo_path" --argjson memo_exists "$memo_exists" '
  .data.repository.pullRequest as $pr
  | $pr.myReviews.nodes[0] as $mine
  | ($pr.commits.nodes | map(.commit)) as $cs
  | (if $mine == null then null else ($cs | map(.oid) | index($mine.commit.oid)) end) as $i
  | {
      repo: "'"$repo"'", me: $me,
      pr: {number: $pr.number, title: $pr.title, url: $pr.url, state: $pr.state,
           author: $pr.author.login, head: $pr.headRefName, head_oid: $pr.headRefOid, base: $pr.baseRefName},
      my_last_review: (if $mine == null then null else
        {state: $mine.state, submitted_at: $mine.submittedAt, commit: $mine.commit.oid} end),
      # レビュー時点の commit が直近 50 件に無い (force push 等) ときは review_commit_found: false で全件を返す
      new_commits: (if $mine == null then [] else
        (if $i == null then $cs else $cs[$i + 1:] end) | map({oid, headline: .messageHeadline, at: .committedDate}) end),
      review_commit_found: (if $mine == null then null else $i != null end),
      my_threads: [$pr.reviewThreads.nodes[]
        | select(.comments.nodes[0].author.login == $me)
        | {id, path, line: (.line // .originalLine), is_resolved: .isResolved, is_outdated: .isOutdated,
           reply_to_comment_id: .comments.nodes[0].databaseId,
           body: .comments.nodes[0].body,
           replies: [.comments.nodes[1:][] | {author: .author.login, body, at: .createdAt}]}],
      other_threads: [$pr.reviewThreads.nodes[]
        | select(.comments.nodes[0].author.login != $me)
        | {path, line: (.line // .originalLine), is_resolved: .isResolved,
           author: .comments.nodes[0].author.login, body: .comments.nodes[0].body}],
      review_memo: {path: $memo_path, exists: $memo_exists}
    }')

echo "$out"
[[ "$(echo "$out" | jq '.my_threads | length')" == "0" ]] && exit 3
exit 0
