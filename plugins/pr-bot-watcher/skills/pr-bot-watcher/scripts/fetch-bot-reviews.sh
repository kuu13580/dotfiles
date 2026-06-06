#!/usr/bin/env bash
# fetch-bot-reviews.sh
# pr-bot-watcher cron用: 情報収集フェーズを一括実行し、JSON形式で出力する
# Usage:
#   bash fetch-bot-reviews.sh            # 自分アサインの全オープンPR
#   bash fetch-bot-reviews.sh <PR番号>   # 指定PR番号のみ (カレントリポジトリ)
# Exit codes: 0=成功, 1=エラー, 2=ダーティワークツリー, 3=PR/コメントなし

set -euo pipefail

target_pr="${1:-}"

# --- Step 1: 事前チェック ---

dirty=$(git status --porcelain 2>&1) || {
  echo "git status の実行に失敗しました" >&2
  exit 1
}
if [[ -n "$dirty" ]]; then
  echo "作業ツリーに未コミットの変更があるため、pr-bot-watcherの実行をスキップしました。変更をcommitまたはstashしてください。" >&2
  exit 2
fi

original_branch=$(git branch --show-current 2>&1) || {
  echo "現在のブランチを取得できませんでした" >&2
  exit 1
}

# --- Step 2: 対象PR一覧取得 ---

if [[ -n "$target_pr" ]]; then
  # PR番号指定モード: カレントリポジトリから取得
  # gh pr view は `repository` フィールドを提供しない。headRepository / headRepositoryOwner を使う。
  single=$(gh pr view "$target_pr" --json number,title,url,headRefName,body,state,headRepository,headRepositoryOwner 2>&1) || {
    echo "PR #$target_pr の取得に失敗しました: $single" >&2
    exit 1
  }
  pr_state=$(echo "$single" | jq -r '.state')
  if [[ "$pr_state" != "OPEN" ]]; then
    echo "PR #$target_pr は OPEN 状態ではありません (state=$pr_state)。監視対象外です。" >&2
    exit 3
  fi
  # gh search prs と同じ形式 ({repository: {nameWithOwner}, number, title, url}) に合わせる
  # jq は null.foo を空文字として扱うため、owner/name を個別抽出して片方 null も検知する
  owner=$(echo "$single" | jq -r '.headRepositoryOwner.login // ""')
  name=$(echo "$single" | jq -r '.headRepository.name // ""')
  if [[ -z "$owner" || -z "$name" ]]; then
    echo "PR #$target_pr のリポジトリ情報を取得できませんでした (headRepositoryOwner.login=$owner, headRepository.name=$name)" >&2
    exit 1
  fi
  repo_full="${owner}/${name}"
  prs_json=$(jq -n --arg repo "$repo_full" --argjson pr "$single" \
    '[{repository: {nameWithOwner: $repo}, number: $pr.number, title: $pr.title, url: $pr.url}]')
else
  # アサインPR取得モード
  prs_json=$(gh search prs --assignee @me --state open --json repository,number,title,url 2>&1) || {
    echo "gh search prs の実行に失敗しました: $prs_json" >&2
    exit 1
  }
fi

pr_count=$(echo "$prs_json" | jq 'length')
if [[ "$pr_count" -eq 0 ]]; then
  echo "対象のオープンPRはありません。" >&2
  exit 3
fi

# --- 結果構築 ---

total_prs=0
total_comments=0
skipped_comments=0
actionable_comments=0

pr_results="[]"

for i in $(seq 0 $((pr_count - 1))); do
  repo=$(echo "$prs_json" | jq -r ".[$i].repository.nameWithOwner")
  number=$(echo "$prs_json" | jq -r ".[$i].number")
  title=$(echo "$prs_json" | jq -r ".[$i].title")
  url=$(echo "$prs_json" | jq -r ".[$i].url")

  pr_detail=$(gh pr view "$number" --repo "$repo" --json number,title,body,headRefName,url 2>&1) || {
    echo "警告: PR #$number ($repo) の詳細取得に失敗しました。スキップします。" >&2
    continue
  }

  head_ref=$(echo "$pr_detail" | jq -r '.headRefName')
  pr_body=$(echo "$pr_detail" | jq -r '.body // ""')

  # --- Step 3: botコメント取得 ---

  review_comments=$(gh api "repos/$repo/pulls/$number/comments" --paginate --jq \
    '[.[] | select(.user.type == "Bot") | {id: .id, user: .user.login, body: .body, path: .path, line: .line, original_line: .original_line, diff_hunk: .diff_hunk, created_at: .created_at, html_url: .html_url}]' 2>&1) || {
    echo "警告: PR #$number ($repo) のレビューコメント取得に失敗しました。スキップします。" >&2
    continue
  }

  reviews=$(gh api "repos/$repo/pulls/$number/reviews" --paginate --jq \
    '[.[] | select(.user.type == "Bot" and .state != "DISMISSED") | {id: .id, user: .user.login, body: .body, state: .state, created_at: .created_at, html_url: .html_url}]' 2>&1) || {
    echo "警告: PR #$number ($repo) のレビュー取得に失敗しました。スキップします。" >&2
    continue
  }

  filtered_comments=$(echo "$review_comments" | jq '
    [.[] |
      if (.body == null or .body == "" or (.body | test("^\\s*$"))) then
        . + {"skipped": true, "skip_reason": "empty_body"}
      elif (.body | test("^\\s*<!--.*-->\\s*$")) then
        . + {"skipped": true, "skip_reason": "html_comment_only"}
      else
        . + {"skipped": false, "skip_reason": null}
      end
    | . + {"type": "review_comment"}
    ]
  ')

  filtered_reviews=$(echo "$reviews" | jq '
    [.[] |
      if (.body == null or .body == "" or (.body | test("^\\s*$"))) then
        . + {"skipped": true, "skip_reason": "empty_body"}
      elif (.body | test("^\\s*<!--.*-->\\s*$")) then
        . + {"skipped": true, "skip_reason": "html_comment_only"}
      elif (.state == "APPROVED") then
        . + {"skipped": true, "skip_reason": "approved"}
      else
        . + {"skipped": false, "skip_reason": null}
      end
    | . + {"type": "review"}
    ]
  ')

  comment_count=$(echo "$filtered_comments" | jq 'length')
  review_count=$(echo "$filtered_reviews" | jq 'length')
  skipped_c=$(echo "$filtered_comments" | jq '[.[] | select(.skipped == true)] | length')
  skipped_r=$(echo "$filtered_reviews" | jq '[.[] | select(.skipped == true)] | length')
  actionable_c=$(echo "$filtered_comments" | jq '[.[] | select(.skipped == false)] | length')
  actionable_r=$(echo "$filtered_reviews" | jq '[.[] | select(.skipped == false)] | length')

  total_prs=$((total_prs + 1))
  total_comments=$((total_comments + comment_count + review_count))
  skipped_comments=$((skipped_comments + skipped_c + skipped_r))
  actionable_comments=$((actionable_comments + actionable_c + actionable_r))

  pr_obj=$(jq -n \
    --argjson number "$number" \
    --arg title "$title" \
    --arg url "$url" \
    --arg headRefName "$head_ref" \
    --arg repository "$repo" \
    --arg body "$pr_body" \
    --argjson comments "$filtered_comments" \
    --argjson reviews "$filtered_reviews" \
    '{
      number: $number,
      title: $title,
      url: $url,
      headRefName: $headRefName,
      repository: $repository,
      body: $body,
      comments: $comments,
      reviews: $reviews
    }')

  pr_results=$(echo "$pr_results" | jq --argjson pr "$pr_obj" '. + [$pr]')
done

if [[ "$actionable_comments" -eq 0 ]]; then
  echo "actionableなbotレビューコメントはありません。" >&2
  exit 3
fi

# --- 最終JSON出力 ---

jq -n \
  --arg original_branch "$original_branch" \
  --argjson prs "$pr_results" \
  --argjson total_prs "$total_prs" \
  --argjson total_comments "$total_comments" \
  --argjson skipped_comments "$skipped_comments" \
  --argjson actionable_comments "$actionable_comments" \
  '{
    original_branch: $original_branch,
    prs: $prs,
    summary: {
      total_prs: $total_prs,
      total_comments: $total_comments,
      skipped_comments: $skipped_comments,
      actionable_comments: $actionable_comments
    }
  }'
