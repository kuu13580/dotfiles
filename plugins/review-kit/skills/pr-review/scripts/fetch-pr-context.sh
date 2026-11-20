#!/usr/bin/env bash
# fetch-pr-context.sh
# pr-review 用: レビュー対象 PR のメタ情報・既存スレッド・ローカル状態・規約ファイル候補を JSON で出力する
# Usage:
#   bash fetch-pr-context.sh            # カレントブランチに対応する PR
#   bash fetch-pr-context.sh 123
#   bash fetch-pr-context.sh https://github.com/owner/repo/pull/123
# Exit codes: 0 = 成功 / 1 = エラー / 4 = カレントブランチから PR を特定できない

set -euo pipefail

arg="${1:-}"

for cmd in gh jq git; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません。インストールしてください。" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "gh が未認証です。\`gh auth login\` を実行してください。" >&2; exit 1; }

current_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1) || {
  echo "カレントディレクトリの GitHub リポジトリを特定できませんでした: $current_repo" >&2
  exit 1
}
current_branch=$(git branch --show-current 2>/dev/null || echo "")
current_oid=$(git rev-parse HEAD 2>/dev/null || echo "")
repo_root=$(git rev-parse --show-toplevel)
if [[ -n "$(git status --porcelain 2>/dev/null || echo "")" ]]; then dirty=true; else dirty=false; fi

target_repo="$current_repo"
if [[ -z "$arg" ]]; then
  target_number=$(gh pr view --json number --jq .number 2>/dev/null) || target_number=""
  if [[ -z "$target_number" ]]; then
    echo "カレントブランチ (${current_branch:-detached HEAD}) に対応する PR が見つかりませんでした。\`/pr-review <PR番号|PR URL>\` で対象を指定してください。" >&2
    exit 4
  fi
elif [[ "$arg" =~ ^[0-9]+$ ]]; then
  target_number="$arg"
elif [[ "$arg" =~ ^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  target_repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  target_number="${BASH_REMATCH[3]}"
else
  echo "引数の形式が不正です: '$arg' (PR 番号または PR の URL を指定してください)" >&2
  exit 1
fi

me=$(gh api user --jq .login)
owner="${target_repo%%/*}"
name="${target_repo##*/}"

query=$(cat <<'GQL'
query($owner: String!, $name: String!, $number: Int!, $me: String!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number title url body state isDraft
      baseRefName headRefName headRefOid
      author { login }
      reviews(states: PENDING, first: 1) { nodes { id comments(first: 1) { totalCount } } }
      myReviews: reviews(author: $me, states: [CHANGES_REQUESTED, APPROVED], last: 1) { nodes { state submittedAt commit { oid } } }
      commits(last: 50) { nodes { commit { oid messageHeadline committedDate } } }
      reviewThreads(first: 100) {
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 3) { nodes { databaseId author { login } body } }
        }
      }
      files(first: 100) { nodes { path additions deletions } }
    }
  }
}
GQL
)

raw=$(gh api graphql -f owner="$owner" -f name="$name" -F number="$target_number" -f me="$me" -f query="$query" 2>&1) || true
msg=$(echo "$raw" | jq -r '[.errors[]?.message] | join(" / ")' 2>/dev/null || echo "")
if [[ -n "$msg" ]]; then
  echo "GitHub API がエラーを返しました: $msg" >&2
  exit 1
fi
echo "$raw" | jq -e '.data' >/dev/null 2>&1 || {
  echo "GitHub API の呼び出しに失敗しました: $(echo "$raw" | head -3)" >&2
  exit 1
}

pr=$(echo "$raw" | jq '.data.repository.pullRequest')
[[ "$pr" == "null" ]] && { echo "$target_repo に PR #$target_number が見つかりません。" >&2; exit 1; }

head_ref=$(echo "$pr" | jq -r '.headRefName')
same_repo=$([[ "$target_repo" == "$current_repo" ]] && echo true || echo false)
on_head=$([[ "$same_repo" == "true" && "$current_branch" == "$head_ref" ]] && echo true || echo false)
head_matches=$([[ "$on_head" == "true" && "$current_oid" == "$(echo "$pr" | jq -r '.headRefOid')" ]] && echo true || echo false)

# --- 規約ファイル候補 (変更ファイルの祖先 CLAUDE.md も含む)。別リポジトリの PR には手元の規約を渡さない ---
rule_files='[]'
[[ "$same_repo" == "true" ]] && rule_files=$(
  {
    for p in CLAUDE.md .claude/CLAUDE.md .cursorrules AGENTS.md; do
      [[ -f "$repo_root/$p" ]] && echo "$p"
    done
    for d in .claude/rules agent/instructions .github/instructions .cursor/rules; do
      # 規約ディレクトリ同士が symlink で繋がっている場合があるため realpath で重複を潰す
      [[ -d "$repo_root/$d" ]] && find -L "$repo_root/$d" -maxdepth 2 -type f \( -name '*.md' -o -name '*.mdc' \) -exec realpath {} \; \
        | sed "s|^$repo_root/||"
    done
    echo "$pr" | jq -r '.files.nodes[].path' | while read -r f; do
      d=$(dirname "$f")
      while [[ "$d" != "." && "$d" != "/" ]]; do
        [[ -f "$repo_root/$d/CLAUDE.md" ]] && echo "$d/CLAUDE.md"
        d=$(dirname "$d")
      done
    done
  } 2>/dev/null | sort -u | jq -R . | jq -s .
)

# フェーズA が残す引き継ぎメモ。PR は GitHub の概念なので owner/repo をキーにする
memo_path="$HOME/.claude/pr-review/$target_repo/$target_number.md"
memo_exists=$([[ -f "$memo_path" ]] && echo true || echo false)

jq -n \
  --arg memo_path "$memo_path" --argjson memo_exists "$memo_exists" \
  --arg repo "$target_repo" --arg me "$me" --arg current_repo "$current_repo" \
  --arg current_branch "$current_branch" --arg repo_root "$repo_root" \
  --argjson dirty "$dirty" --argjson same_repo "$same_repo" --argjson on_head "$on_head" --argjson head_matches "$head_matches" \
  --argjson pr "$pr" --argjson rule_files "$rule_files" \
  '{
     repo: $repo,
     me: $me,
     pr: {
       number: $pr.number, title: $pr.title, url: $pr.url, body: $pr.body,
       state: $pr.state, is_draft: $pr.isDraft, author: $pr.author.login,
       base: $pr.baseRefName, head: $pr.headRefName, head_oid: $pr.headRefOid,
       changed_files: [$pr.files.nodes[] | {path, additions, deletions}]
     },
     local: {
       repo: $current_repo, repo_root: $repo_root, branch: $current_branch,
       dirty: $dirty, same_repository: $same_repo, on_head_branch: $on_head, head_matches: $head_matches
     },
     my_pending_review: ($pr.reviews.nodes | length > 0),
     my_last_review: ($pr.myReviews.nodes[0]
       | if . == null then null else {state, submitted_at: .submittedAt, commit: .commit.oid} end),
     # レビュー時点の commit が直近 50 件に無い (force push 等) ときは review_commit_found: false で全件を返す
     new_commits_since_my_review: ($pr.myReviews.nodes[0] as $mine
       | if $mine == null then [] else
           ($pr.commits.nodes | map(.commit)) as $cs
           | ($cs | map(.oid) | index($mine.commit.oid)) as $i
           | (if $i == null then $cs else $cs[$i + 1:] end)
           | map({oid, headline: .messageHeadline, at: .committedDate}) end),
     review_commit_found: ($pr.myReviews.nodes[0] as $mine
       | if $mine == null then null else ($pr.commits.nodes | map(.commit.oid) | index($mine.commit.oid)) != null end),
     existing_threads: [$pr.reviewThreads.nodes[] | {
       id, path, line: (.line // .originalLine), is_resolved: .isResolved, is_outdated: .isOutdated,
       author: .comments.nodes[0].author.login,
       body: .comments.nodes[0].body,
       reply_count: (.comments.nodes | length - 1)
     }],
     rule_files: $rule_files,
     review_memo: {path: $memo_path, exists: $memo_exists}
   }'
