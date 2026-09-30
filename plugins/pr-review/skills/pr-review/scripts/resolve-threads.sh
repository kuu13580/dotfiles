#!/usr/bin/env bash
# resolve-threads.sh
# pr-review 用: レビュースレッドを Resolve する (ユーザーの承認後にのみ実行すること)
# Usage: bash resolve-threads.sh <threadId> [<threadId> ...]
set -euo pipefail

[[ $# -eq 0 ]] && { echo "Usage: bash resolve-threads.sh <threadId> [...]" >&2; exit 1; }

ok=0; ng=0
for id in "$@"; do
  if res=$(gh api graphql -f id="$id" -f query='
    mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { id isResolved } } }' 2>&1); then
    echo "resolved: $id"
    ok=$((ok + 1))
  else
    echo "failed:   $id — $res" >&2
    ng=$((ng + 1))
  fi
done
echo "resolved ${ok} / failed ${ng}"
[[ "$ng" -gt 0 ]] && exit 1
exit 0
