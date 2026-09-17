#!/usr/bin/env bash
# reply-thread.sh
# pr-review 用: レビュースレッドに返信する (文面をユーザーが承認した後にのみ実行すること)
# Usage: bash reply-thread.sh <PR番号|PR URL> <返信先コメントのdatabaseId> <本文ファイル>
set -euo pipefail

target="${1:-}"; comment_id="${2:-}"; body_file="${3:-}"
[[ -z "$target" || -z "$comment_id" || -z "$body_file" ]] && {
  echo "Usage: bash reply-thread.sh <PR番号|PR URL> <comment databaseId> <本文ファイル>" >&2; exit 1; }
[[ -f "$body_file" ]] || { echo "本文ファイルが見つかりません: $body_file" >&2; exit 1; }

if [[ "$target" =~ ^[0-9]+$ ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner); number="$target"
elif [[ "$target" =~ ^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"; number="${BASH_REMATCH[3]}"
else
  echo "引数の形式が不正です: '$target'" >&2; exit 1
fi

jq -n --rawfile body "$body_file" '{body: $body}' \
  | gh api --method POST "/repos/$repo/pulls/$number/comments/$comment_id/replies" --input - \
  | jq '{id, html_url, created_at}'
