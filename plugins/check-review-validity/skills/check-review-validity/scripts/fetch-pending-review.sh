#!/usr/bin/env bash
# fetch-pending-review.sh
# check-review-validity 用: 自分 (viewer) の未 submit ドラフトレビューと判定材料を JSON で出力する
# Usage:
#   bash fetch-pending-review.sh                  # カレントブランチに対応する PR
#   bash fetch-pending-review.sh 123              # PR 番号指定 (カレントリポジトリ)
#   bash fetch-pending-review.sh https://github.com/owner/repo/pull/123
# Exit codes:
#   0 = ドラフトレビュー検出 (stdout に JSON)
#   1 = エラー (依存不足 / 未認証 / API 失敗 / 引数不正)
#   3 = ドラフトレビューなし
#   4 = カレントブランチから PR を特定できない

set -euo pipefail

arg="${1:-}"

# --- 依存チェック ---

command -v gh >/dev/null 2>&1 || {
  echo "gh CLI が見つかりません。インストールしてください。" >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  echo "jq が見つかりません。インストールしてください。" >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  echo "gh が未認証です。\`gh auth login\` を実行してください。" >&2
  exit 1
}

# --- カレントリポジトリ / ブランチ / 作業ツリー状態 ---

current_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>&1) || {
  echo "カレントディレクトリの GitHub リポジトリを特定できませんでした: $current_repo" >&2
  exit 1
}
current_branch=$(git branch --show-current 2>/dev/null || echo "")
if [[ -n "$(git status --porcelain 2>/dev/null || echo "")" ]]; then
  dirty=true
else
  dirty=false
fi

# --- 対象 PR の決定 ---

target_repo="$current_repo"
target_number=""

if [[ -z "$arg" ]]; then
  target_number=$(gh pr view --json number --jq .number 2>/dev/null) || target_number=""
  if [[ -z "$target_number" ]]; then
    echo "カレントブランチ (${current_branch:-detached HEAD}) に対応する PR が見つかりませんでした。\`/check-review-validity <PR番号|PR URL>\` で対象を指定してください。" >&2
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

owner="${target_repo%%/*}"
name="${target_repo##*/}"

# --- GraphQL 一括取得 ---
# pending review (未 submit ドラフト) のコメントは REST の pulls/comments には現れないため
# GraphQL の reviews(states: PENDING) 経由で取得する。pending review は本人にのみ可視。

query=$(
  cat <<'GQL'
query($owner: String!, $name: String!, $number: Int!) {
  viewer { login }
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      number title url body state baseRefName headRefName
      author { login }
      pending: reviews(first: 5, states: PENDING) {
        nodes {
          id body
          author { login }
          comments(first: 100) {
            nodes {
              id path line originalLine startLine originalStartLine
              diffHunk body outdated url
            }
          }
        }
      }
      submitted: reviews(first: 30, states: [COMMENTED, APPROVED, CHANGES_REQUESTED, DISMISSED]) {
        nodes { state body submittedAt author { login } }
      }
      reviewThreads(first: 50) {
        nodes {
          isResolved isOutdated
          comments(first: 1) { nodes { id author { login } path line body } }
        }
      }
    }
  }
}
GQL
)

resp=$(gh api graphql -f query="$query" -f owner="$owner" -f name="$name" -F number="$target_number" 2>&1) || {
  if echo "$resp" | grep -q "Could not resolve to a PullRequest"; then
    echo "PR #$target_number ($target_repo) が見つかりませんでした。" >&2
  elif echo "$resp" | grep -q "Could not resolve to a Repository"; then
    echo "リポジトリ $target_repo が見つかりませんでした (アクセス権限がない可能性もあります)。" >&2
  else
    echo "GitHub API の呼び出しに失敗しました: $resp" >&2
  fi
  exit 1
}
if echo "$resp" | jq -e 'has("errors")' >/dev/null 2>&1; then
  echo "GitHub API がエラーを返しました: $(echo "$resp" | jq -c '.errors')" >&2
  exit 1
fi

pr=$(echo "$resp" | jq '.data.repository.pullRequest')
if [[ "$pr" == "null" ]]; then
  echo "PR #$target_number ($target_repo) が見つかりませんでした。" >&2
  exit 1
fi

viewer=$(echo "$resp" | jq -r '.data.viewer.login')

# 他人の pending review は API 上見えないが、念のため viewer 本人のものに絞る
pending=$(echo "$pr" | jq --arg v "$viewer" 'first(.pending.nodes[] | select(.author.login == $v)) // null')

if [[ "$pending" == "null" ]]; then
  echo "PR #$target_number に未 submit のドラフトレビューはありません。" >&2
  exit 3
fi

pending_comments=$(echo "$pending" | jq '.comments.nodes | length')
pending_body=$(echo "$pending" | jq -r '.body // ""')
if [[ "$pending_comments" -eq 0 && -z "$pending_body" ]]; then
  echo "PR #$target_number のドラフトレビューは空です (行コメント・レビュー本文ともになし)。" >&2
  exit 3
fi

# --- ローカルコードが判定に使えるか ---
# 同一リポジトリかつカレントブランチが PR の head ブランチなら実ファイルを読める。
# そうでなければ gh pr diff ベースの判定に落とす。

head_ref=$(echo "$pr" | jq -r '.headRefName')
if [[ "$target_repo" == "$current_repo" ]]; then
  same_repo=true
  if [[ -n "$current_branch" && "$current_branch" == "$head_ref" ]]; then
    local_code_available=true
  else
    local_code_available=false
  fi
else
  same_repo=false
  local_code_available=false
fi

# --- JSON 出力 ---

if ! output=$(jq -n \
  --arg viewer "$viewer" \
  --arg current_repo "$current_repo" \
  --arg current_branch "$current_branch" \
  --arg target_repo "$target_repo" \
  --argjson same_repo "$same_repo" \
  --argjson local_code_available "$local_code_available" \
  --argjson dirty "$dirty" \
  --argjson pr "$pr" \
  --argjson pending "$pending" \
  '
  # 自分の pending 行コメントは reviewThreads にもそのまま現れる。
  # そのまま other_threads に載せると「自分の指摘と重複」と誤判定するため ID で除外する。
  ([$pending.comments.nodes[].id]) as $pending_ids
  | ([
      $pr.reviewThreads.nodes[]
      | (.comments.nodes[0].id // "") as $thread_head_id
      | select(($pending_ids | index($thread_head_id)) == null)
      | {
          is_resolved: .isResolved,
          is_outdated: .isOutdated,
          author: (.comments.nodes[0].author.login // null),
          path: (.comments.nodes[0].path // null),
          line: (.comments.nodes[0].line // null),
          body: (.comments.nodes[0].body // "")
        }
    ]) as $threads
  | {
    viewer: $viewer,
    current_repository: $current_repo,
    current_branch: $current_branch,
    target_repository: $target_repo,
    same_repository: $same_repo,
    local_code_available: $local_code_available,
    dirty_worktree: $dirty,
    pr: {
      number: $pr.number,
      title: $pr.title,
      url: $pr.url,
      state: $pr.state,
      body: ($pr.body // ""),
      baseRefName: $pr.baseRefName,
      headRefName: $pr.headRefName,
      author: ($pr.author.login // null)
    },
    pending_review: {
      id: $pending.id,
      body: ($pending.body // ""),
      comments: [
        $pending.comments.nodes[] | {
          id, path, body,
          line: .line,
          original_line: .originalLine,
          start_line: .startLine,
          original_start_line: .originalStartLine,
          outdated: .outdated,
          diff_hunk: .diffHunk,
          url: .url
        }
      ]
    },
    submitted_reviews: [
      $pr.submitted.nodes[] | {
        state, submittedAt,
        author: (.author.login // null),
        body: (.body // "")
      }
    ],
    other_threads: $threads,
    summary: {
      pending_comments: ($pending.comments.nodes | length),
      outdated_comments: ([$pending.comments.nodes[] | select(.outdated == true)] | length),
      has_review_body: (($pending.body // "") != ""),
      submitted_reviews: ($pr.submitted.nodes | length),
      other_threads: ($threads | length),
      unresolved_other_threads: ([$threads[] | select(.is_resolved == false)] | length)
    }
  }'); then
  echo "取得結果の JSON 組み立てに失敗しました。" >&2
  exit 1
fi

printf '%s\n' "$output"
