#!/usr/bin/env bash
# rebase のコンフリクト停止中に、各 hunk の両側の出どころ (コミット・PR) を JSON で stdout に出す。
#
# HEAD 側 = merge-base 以降に hunk の行範囲を触ったコミット (log -L)。
#   side=upstream は base に入っているコミット、side=own はこの rebase で先に適用した自分のコミット
# replay 側 = 適用中のコミット (REBASE_HEAD) と自分のブランチの PR
#
# exit: 0=出力 / 1=エラー
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
require_tools
in_rebase || die "rebase 中ではありません。"

MAX_COMMITS_PER_HUNK=10
RD=$(rebase_dir)
ONTO=$(cat "$RD/onto")
ORIG=$(cat "$RD/orig-head")
MB=$(git merge-base "$ORIG" "$ONTO")
BRANCH=$(rebase_branch)
REPLAY=$(git rev-parse --quiet --verify REBASE_HEAD 2>/dev/null || true)
REPO=$(github_repo) || REPO=""

CACHE="$(state_dir)/cache"
mkdir -p "$CACHE" 2>/dev/null || CACHE=$(mktemp -d)

# 作業ツリーのマーカーから各 hunk の位置と、HEAD 側の内容が HEAD のファイルの何行目にあたるかを出す
#   出力: marker_start marker_end head_start head_end (head_end < head_start は HEAD 側が空)
hunks_of() {
  awk '
    st == 0 && /^<{7}( |$)/ { st = 1; ms = NR; hs = h + 1; next }
    st == 1 && /^\|{7}( |$)/ { st = 2; next }
    (st == 1 || st == 2) && /^={7}$/ { st = 3; he = h; next }
    st == 3 && /^>{7}( |$)/ { print ms, NR, hs, he; st = 0; next }
    st == 0 || st == 1 { h++ }
  ' "$1"
}

commits_touching() {
  local path="$1" s="$2" e="$3"
  if [ "$e" -lt "$s" ]; then s=$(( s > 1 ? s - 1 : 1 )); e=$s; fi
  git log -L "$s,$e:$path" --format=%H -s "$MB..HEAD" 2>/dev/null | head -n "$MAX_COMMITS_PER_HUNK"
}

prs_of_commit() {
  local sha="$1" f="$CACHE/commit-$1.json"
  [ -n "$REPO" ] || { echo '[]'; return; }
  [ -f "$f" ] || gh api "repos/$REPO/commits/$sha/pulls" --jq '[.[].number][0:3]' > "$f" 2>/dev/null || echo '[]' > "$f"
  cat "$f"
}

PR_QUERY='query($owner:String!,$name:String!,$num:Int!){repository(owner:$owner,name:$name){pullRequest(number:$num){
  number title url state mergedAt baseRefName headRefName body
  closingIssuesReferences(first:5){nodes{number title}}
  reviewThreads(first:100){nodes{path line isResolved comments(first:20){nodes{author{login} body}}}}}}}'

pr_detail() {
  local num="$1" paths="$2" f="$CACHE/pr-$1.json"
  if [ ! -f "$f" ]; then
    gh api graphql -F owner="${REPO%/*}" -F name="${REPO#*/}" -F num="$num" -f query="$PR_QUERY" \
      --jq '.data.repository.pullRequest' > "$f" 2>/dev/null || { rm -f "$f"; echo null; return; }
  fi
  # レビュースレッドはコンフリクトしたファイルに付いたものだけ
  jq --argjson paths "$paths" '{
      number, title, url, state, merged_at: .mergedAt, base: .baseRefName, head: .headRefName,
      body: (.body // "" | .[0:6000]),
      closing_issues: .closingIssuesReferences.nodes,
      review_threads: [.reviewThreads.nodes[] | select(.path as $p | $paths | index($p))
        | {path, line, resolved: .isResolved,
           comments: [.comments.nodes[] | {author: .author.login, body: (.body | .[0:1500])}]}]
    }' "$f"
}

UNMERGED=$(git diff --name-only --diff-filter=U)
PATHS_JSON=$(printf '%s\n' "$UNMERGED" | to_json_array)

files='[]'
all_commits=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  code=$(git status --porcelain=v1 -- "$path" | head -n 1 | cut -c1-2)
  hunks='[]'; path_commits='[]'; markers=false
  if [ -f "$path" ] && grep -qE '^<{7}( |$)' "$path"; then
    markers=true
    while read -r ms me hs he; do
      cs=$(commits_touching "$path" "$hs" "$he")
      all_commits+="$cs"$'\n'
      hunks=$(jq --argjson ms "$ms" --argjson me "$me" --argjson hs "$hs" --argjson he "$he" \
        --argjson cs "$(printf '%s\n' "$cs" | to_json_array)" \
        '. + [{marker_lines: [$ms, $me], head_lines: (if $he < $hs then null else [$hs, $he] end), head_commits: $cs}]' <<< "$hunks")
    done < <(hunks_of "$path")
  else
    # modify/delete 等。ファイル単位で HEAD 側の変更コミットを取る
    cs=$(git log --format=%H "$MB..HEAD" -- "$path" | head -n "$MAX_COMMITS_PER_HUNK")
    all_commits+="$cs"$'\n'
    path_commits=$(printf '%s\n' "$cs" | to_json_array)
  fi
  files=$(jq --arg path "$path" --arg code "$code" --argjson markers "$markers" \
    --argjson hunks "$hunks" --argjson pc "$path_commits" \
    '. + [{path: $path, status: $code, markers: $markers, hunks: $hunks, head_commits: $pc}]' <<< "$files")
done <<< "$UNMERGED"

OWN_PR=""
[ -n "$REPO" ] && OWN_PR=$(gh pr view "$BRANCH" --json number -q .number 2>/dev/null) || true

commits='{}'; pr_nums=""
[ -n "$OWN_PR" ] && pr_nums+="$OWN_PR"$'\n'
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  if git merge-base --is-ancestor "$sha" "$ONTO"; then side=upstream; prs=$(prs_of_commit "$sha")
  else side=own; prs=$(jq -n --arg n "$OWN_PR" 'if $n == "" then [] else [$n | tonumber] end'); fi
  pr_nums+=$(jq -r '.[]' <<< "$prs")$'\n'
  commits=$(jq --arg sha "$sha" --arg side "$side" --argjson prs "$prs" \
    --arg subject "$(git log -1 --format=%s "$sha")" --arg body "$(git log -1 --format=%b "$sha" | head -c 2000)" \
    '. + {($sha): {side: $side, subject: $subject, body: $body, prs: $prs}}' <<< "$commits")
done < <(printf '%s' "$all_commits" | awk 'NF && !seen[$0]++')

prs='{}'
if [ -n "$REPO" ]; then
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    prs=$(jq --arg n "$n" --argjson d "$(pr_detail "$n" "$PATHS_JSON")" '. + {($n): $d}' <<< "$prs")
  done < <(printf '%s' "$pr_nums" | awk 'NF && !seen[$0]++')
fi

jq -n \
  --arg repo "$REPO" --arg onto "$ONTO" --arg mb "$MB" --arg head "$(git rev-parse HEAD)" --arg branch "$BRANCH" \
  --arg replay "$REPLAY" \
  --arg replay_subject "$([ -n "$REPLAY" ] && git log -1 --format=%s "$REPLAY")" \
  --arg replay_body "$([ -n "$REPLAY" ] && git log -1 --format=%b "$REPLAY" | head -c 4000)" \
  --arg own_pr "$OWN_PR" \
  --argjson files "$files" --argjson commits "$commits" --argjson prs "$prs" \
  '{github_repo: (if $repo == "" then null else $repo end), branch: $branch,
    onto: $onto, merge_base: $mb, head: $head,
    replay: {commit: $replay, subject: $replay_subject, body: $replay_body},
    own_pr: (if $own_pr == "" then null else ($own_pr | tonumber) end),
    files: $files, commits: $commits, prs: $prs}'
