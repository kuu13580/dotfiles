#!/usr/bin/env bash
# detect-state.sh
# review-kit 用: ローカルと GitHub の状態から、合うスキルを判定して JSON で出す
# Usage: bash detect-state.sh [<PR番号|PR URL>]
# Exit codes: 0 = 成功 / 1 = エラー

set -euo pipefail

target="${1:-}"
for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません。" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh が未認証です。\`gh auth login\` を実行してください。" >&2; exit 1; }
me=$(gh api user --jq .login)

in_git=false; branch=""; default_branch=""; dirty=false; ahead=0; repo=""
# ahead: 比較元 (origin/<default>) が無ければ null
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  in_git=true
  branch=$(git branch --show-current 2>/dev/null || echo "")
  [[ -n "$(git status --porcelain 2>/dev/null)" ]] && dirty=true
  if info=$(gh repo view --json nameWithOwner,defaultBranchRef 2>/dev/null); then
    repo=$(echo "$info" | jq -r .nameWithOwner)
    default_branch=$(echo "$info" | jq -r .defaultBranchRef.name)
    ahead=$(git rev-list --count "origin/$default_branch..HEAD" 2>/dev/null || echo null)
  fi
fi

number=""
if [[ -z "$target" ]]; then
  [[ "$in_git" == true && -n "$branch" && "$branch" != "$default_branch" ]] \
    && number=$(gh pr view --json number --jq .number 2>/dev/null || echo "")
elif [[ "$target" =~ ^[0-9]+$ ]]; then
  [[ -z "$repo" ]] && { echo "カレントディレクトリの GitHub リポジトリを特定できません。PR の URL を指定してください。" >&2; exit 1; }
  number="$target"
elif [[ "$target" =~ ^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
else
  echo "引数の形式が不正です (github.com の PR URL か PR 番号のみ対応): '$target'" >&2; exit 1
fi

errf=$(mktemp); trap 'rm -f "$errf"' EXIT
pr=null
if [[ -n "$number" ]]; then
  raw=$(gh api graphql -f owner="${repo%%/*}" -f name="${repo##*/}" -F number="$number" -f query='
query($owner:String!,$name:String!,$number:Int!){
  repository(owner:$owner,name:$name){
    pullRequest(number:$number){
      number url state isDraft author { login }
      commits(last:1){ nodes { commit { committedDate } } }
      reviewThreads(first:100){ pageInfo { hasNextPage } nodes { isResolved
        first: comments(first:1){ nodes { author { login } } }
        last: comments(last:1){ nodes { author { login } } } } }
      latestReviews(first:30){ nodes { state submittedAt author { login } } }
      pending: reviews(states:[PENDING], first:1){ totalCount }
    }
  }
}' 2>"$errf") || { echo "PR の取得に失敗しました: $(head -3 "$errf")" >&2; exit 1; }
  pr=$(echo "$raw" | jq --arg me "$me" --arg repo "$repo" '.data.repository.pullRequest
    | {repo: $repo, number, url, state, is_draft: .isDraft, author: (.author.login // "ghost"),
       is_mine: (.author.login == $me),
       # 最後の発言が自分のスレッドは返信済みとして数えない
       unresolved_feedback: [.reviewThreads.nodes[] | select(.isResolved | not)
         | select(.first.nodes[0].author.login != $me) | select(.last.nodes[0].author.login != $me)] | length,
       threads_truncated: .reviewThreads.pageInfo.hasNextPage,
       # head の commit より後に出た変更要求だけを未対応とみなす (前のものは修正済みで再レビュー待ちの可能性が高い)
       changes_requested: (.commits.nodes[0].commit.committedDate as $head_at
         | [.latestReviews.nodes[] | select(.state == "CHANGES_REQUESTED") | select(.submittedAt > $head_at)] | length),
       head_at: .commits.nodes[0].commit.committedDate,
       my_pending_review: (.pending.totalCount > 0)}')
fi

# 行スレッドに指摘が無い自分の PR でも、人がレビュー本文や PR コメントで修正を頼んでいることがある。
# changes_requested と同じく head の commit より後のものだけを数え、bot (要約が大半)・APPROVED・DISMISSED は数えない。
# 取得に失敗しても判定は止めず、open_review_bodies を null にして理由に添える
open_bodies=null; bodies_error=""
if [[ "$pr" != null ]] && echo "$pr" | jq -e '.state == "OPEN" and .is_mine and .unresolved_feedback == 0
    and .changes_requested == 0 and (.threads_truncated | not)' >/dev/null; then
  if bodies=$(bash "$(dirname "$0")/fetch-pr-bodies.sh" "$repo" "$number" "$me" 2>"$errf"); then
    open_bodies=$(echo "$bodies" | jq --arg head_at "$(echo "$pr" | jq -r .head_at)" '
      [(.review_bodies[] | select(.state != "APPROVED" and .state != "DISMISSED")), .pr_comments[]
       | select(.is_bot | not) | select(.answered | not) | select(.at > $head_at)] | length')
  else
    bodies_error=$(head -3 "$errf")
  fi
fi

# 依頼一覧は他に手掛かりが無いときだけ取る (API 呼び出しを減らすため)
requests=null; requests_error=""
if [[ ( "$pr" == null || "$(echo "$pr" | jq -r .state)" != OPEN ) && "$dirty" == false && "$ahead" == 0 && "$in_git" == true ]]; then
  list="$(dirname "$0")/../skills/pr-review/scripts/list-review-prs.sh"
  rc=0; listed=$(bash "$list" 2>"$errf") || rc=$?
  case "$rc" in
    0) requests=$(echo "$listed" | jq '(.requested | length) + (.awaiting_fix | length)') ;;
    3) requests=0 ;;
    *) requests_error=$(head -3 "$errf") ;;
  esac
fi

jq -n --arg me "$me" --argjson in_git "$in_git" --arg branch "$branch" --arg default_branch "$default_branch" \
  --argjson dirty "$dirty" --argjson ahead "$ahead" --argjson pr "$pr" --argjson requests "$requests" \
  --argjson open_bodies "$open_bodies" --arg bodies_error "$bodies_error" \
  --arg requests_error "$requests_error" '
  (if $pr != null and $pr.state == "OPEN" then
     (if $pr.is_mine then
        (if ($pr.unresolved_feedback + $pr.changes_requested) > 0
         then ["review-response", "自分の PR に未解決の指摘がある"]
         elif $pr.threads_truncated then ["review-response", "スレッドが 100 件を超えて取り切れず、未解決の指摘が無いと言い切れない"]
         elif ($open_bodies // 0) > 0 then ["review-response", "head の commit より後の人のレビュー本文・PR コメントに未返信のものがある"]
         elif $bodies_error != "" then ["self-review", "行スレッドに未解決の指摘は無い (レビュー本文・PR コメントは取得できず未確認: " + $bodies_error + ")"]
         else ["self-review", "自分の PR で、未解決の指摘は無い"] end)
      elif $pr.my_pending_review then ["check-review-validity", "他人の PR に未 submit の下書きレビューがある"]
      else ["pr-review", "他人の PR"] end)
   elif $dirty or ($ahead // 0) > 0 then ["self-review", "未コミットの変更、または PR を出す前のブランチ"]
   elif $ahead == null and $branch != $default_branch and $branch != "" then ["self-review", "比較元のブランチが手元に無いが、既定ブランチ以外にいる"]
   elif ($requests // 0) > 0 then ["pr-review", "自分宛のレビュー依頼・修正確認待ちがある"]
   elif $requests_error != "" then [null, "レビュー依頼の一覧を取得できなかった: " + $requests_error]
   else [null, "レビューする対象が見つからない"] end) as $s
  | {me: $me,
     local: {in_git: $in_git, branch: $branch, default_branch: $default_branch, dirty: $dirty, ahead: $ahead},
     # open_review_bodies: 数えていない (他人の PR・既に指摘がある・取得失敗) ときは null
     pr: (if $pr == null then null else $pr + {open_review_bodies: $open_bodies} end), review_requests: $requests, review_requests_error: (if $requests_error == "" then null else $requests_error end), suggested: $s[0], reason: $s[1]}'
