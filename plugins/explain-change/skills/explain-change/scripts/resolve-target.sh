#!/usr/bin/env bash
# 引数から解説対象 (worktree / pr / commit / range / branch) を判別し、
# 調査に必要なメタデータを JSON で stdout に出力する。
#
# exit code: 0=解決 / 1=エラー / 2=対象を特定できない (ユーザーに確認が必要)
set -uo pipefail

die()  { echo "$1" >&2; exit 1; }
undecided() { echo "$1" >&2; exit 2; }

command -v git >/dev/null 2>&1 || die "git が見つかりません。"
command -v jq  >/dev/null 2>&1 || die "jq が見つかりません (apt install jq / brew install jq)。"
git rev-parse --git-dir >/dev/null 2>&1 || die "git リポジトリの中で実行してください。"

ARG="${1:-}"

default_branch() {
  local d c
  if d=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null); then
    echo "$d"; return
  fi
  for c in origin/main origin/master main master; do
    if git rev-parse --verify --quiet "$c" >/dev/null 2>&1; then echo "$c"; return; fi
  done
  echo ""
}

# git 側の差分メタデータ (stat / ファイル一覧 / コミット一覧) を JSON 片で返す
git_meta() {
  local range="$1" log_range="$2"
  local stat files commits
  stat=$(git diff --stat "$range" 2>/dev/null | tail -n 1)
  files=$(git diff --name-status "$range" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')
  if [ -n "$log_range" ]; then
    commits=$(git log --format='%h %s' "$log_range" 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')
  else
    commits='[]'
  fi
  jq -n --arg stat "$stat" --argjson files "$files" --argjson commits "$commits" \
    '{stat: $stat, files: $files, commits: $commits}'
}

# 対象のコードが手元で読める状態かを 3 値で返す
#   exact    = HEAD がまさにその commit
#   contains = HEAD の祖先 (マージ済み等)。読めるが後続の変更が乗っている可能性がある
#   absent   = 手元に無い
local_code_state() {
  local target="${1:-}"
  [ -z "$target" ] && { echo "absent"; return; }
  git rev-parse --verify --quiet "${target}^{commit}" >/dev/null 2>&1 || { echo "absent"; return; }
  if [ "$(git rev-parse "${target}^{commit}")" = "$(git rev-parse HEAD)" ]; then echo "exact"; return; fi
  if git merge-base --is-ancestor "$target" HEAD 2>/dev/null; then echo "contains"; return; fi
  echo "absent"
}

# commit / range / branch 共通の JSON 出力 (worktree と pr は形が違うので各自で組む)
emit() {
  local kind="$1" label="$2" base="$3" head="$4" diff_command="$5" local_code="$6" meta="$7"
  local extra="${8:-}"
  [ -z "$extra" ] && extra='{}'
  jq -n \
    --arg kind "$kind" --arg label "$label" --arg base "$base" --arg head "$head" \
    --arg diff_command "$diff_command" --arg local_code "$local_code" \
    --argjson meta "$meta" --argjson extra "$extra" \
    '{kind: $kind, label: $label, base: $base, head: $head, diff_command: $diff_command,
      untracked: [], local_code: $local_code, pr: null} + $meta + $extra'
}

# 引数をブランチの完全 ref に解決する (ローカル優先 → リモート)。見つからなければ 1。
# git は bare name を refs/remotes/origin/* に DWIM しないので、
# 存在判定で当たった ref をそのまま git に渡す必要がある。
resolve_branch_ref() {
  local a="$1" c
  for c in "refs/heads/${a}" "refs/remotes/${a}" "refs/remotes/origin/${a}"; do
    if git rev-parse --verify --quiet "$c" >/dev/null 2>&1; then echo "$c"; return 0; fi
  done
  return 1
}

DIRTY=false
[ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=true

# ---------------------------------------------------------------- worktree
resolve_worktree() {
  local untracked meta
  untracked=$(git ls-files --others --exclude-standard | jq -R -s 'split("\n") | map(select(length > 0))')
  meta=$(git_meta "HEAD" "")
  jq -n \
    --arg kind "worktree" \
    --arg label "未コミットの変更 (HEAD からの差分)" \
    --arg base "HEAD" \
    --arg head "(working tree)" \
    --arg diff_command "git diff HEAD" \
    --argjson untracked "$untracked" \
    --argjson meta "$meta" \
    '{kind: $kind, label: $label, base: $base, head: $head,
      diff_command: $diff_command, untracked: $untracked,
      local_code: "exact", pr: null} + $meta'
}

# ---------------------------------------------------------------- pr
resolve_pr() {
  local num="$1" repo_flag="$2"
  command -v gh >/dev/null 2>&1 || die "gh CLI が見つかりません。PR を対象にするには gh が必要です。"
  local view
  # shellcheck disable=SC2086
  view=$(gh pr view "$num" $repo_flag --json number,title,body,url,state,author,baseRefName,headRefName,headRefOid,additions,deletions,changedFiles,commits,mergeCommit 2>/dev/null) \
    || die "PR #${num} を取得できませんでした (gh auth status / PR 番号を確認してください)。"

  local head_oid files state
  head_oid=$(jq -r '.headRefOid' <<<"$view")
  state=$(local_code_state "$head_oid")
  # squash / rebase merge では headRefOid が HEAD の祖先にならない (ブランチ削除済みなら
  # ローカルに存在すらしない)。マージコミット経由で「手元に入っている」を拾い直す。
  if [ "$state" = "absent" ]; then
    local merge_oid; merge_oid=$(jq -r '.mergeCommit.oid // ""' <<<"$view")
    if [ -n "$merge_oid" ] && [ "$(local_code_state "$merge_oid")" != "absent" ]; then
      # マージコミットは相手側の変更も含むため exact ではなく contains 扱いにする
      state="contains"
    fi
  fi

  # shellcheck disable=SC2086
  files=$(gh pr diff "$num" $repo_flag --name-only 2>/dev/null | jq -R -s 'split("\n") | map(select(length > 0))')

  local diff_cmd="gh pr diff ${num}"
  [ -n "$repo_flag" ] && diff_cmd="${diff_cmd} ${repo_flag}"

  jq -n \
    --arg kind "pr" \
    --arg diff_command "$diff_cmd" \
    --argjson view "$view" \
    --argjson files "$files" \
    --arg local_code "$state" \
    '{kind: $kind,
      label: "PR #\($view.number) \($view.title)",
      base: $view.baseRefName,
      head: $view.headRefName,
      diff_command: $diff_command,
      stat: "\($view.changedFiles) files, +\($view.additions) -\($view.deletions)",
      files: $files,
      commits: ($view.commits | map("\(.oid[0:7]) \(.messageHeadline)")),
      untracked: [],
      local_code: $local_code,
      pr: {number: $view.number, title: $view.title, body: $view.body, url: $view.url,
           state: $view.state, author: $view.author.login}}'
}

# ---------------------------------------------------------------- commit
resolve_commit() {
  local sha subject parent meta state
  sha=$(git rev-parse "$1")
  subject=$(git log -1 --format='%s' "$sha")
  if git rev-parse --verify --quiet "${sha}^" >/dev/null 2>&1; then parent="${sha}^"; else parent="$(git hash-object -t tree /dev/null)"; fi
  meta=$(git_meta "${parent}..${sha}" "${parent}..${sha}")
  state=$(local_code_state "$sha")
  emit "commit" "commit ${sha:0:7} ${subject}" "$parent" "$sha" "git show ${sha}" "$state" "$meta"
}

# ---------------------------------------------------------------- range
resolve_range() {
  local spec="$1" sep base head meta state log_range mb
  case "$spec" in *...*) sep="..." ;; *) sep=".." ;; esac
  base="${spec%%${sep}*}"
  head="${spec##*${sep}}"
  [ -z "$head" ] && head="HEAD"
  git rev-parse --verify --quiet "${base}^{commit}" >/dev/null 2>&1 || undecided "範囲の始点 '${base}' を解決できません。"
  git rev-parse --verify --quiet "${head}^{commit}" >/dev/null 2>&1 || undecided "範囲の終点 '${head}' を解決できません。"
  # git diff A...B は merge-base..B を見るが、git log A...B は対称差を返す。
  # 揃えないと「ファイル 0 件・コミット 4 件」のような食い違った JSON になる。
  if [ "$sep" = "..." ]; then
    mb=$(git merge-base "$base" "$head") || undecided "'${base}' と '${head}' の merge-base を取得できません。"
    log_range="${mb}..${head}"
  else
    log_range="$spec"
  fi
  meta=$(git_meta "$spec" "$log_range")
  state=$(local_code_state "$head")
  emit "range" "範囲 ${spec}" "$base" "$head" "git diff ${spec}" "$state" "$meta"
}

# ---------------------------------------------------------------- branch
#   $1 完全 ref (refs/heads/... や refs/remotes/origin/...)、$2 表示名
resolve_branch() {
  local ref="$1" display="$2" db mb meta state extra
  db=$(default_branch)
  [ -z "$db" ] && undecided "デフォルトブランチを特定できません。'<base>..${display}' の形式で範囲を指定してください。"
  mb=$(git merge-base "$db" "$ref" 2>/dev/null) || undecided "'${db}' と '${display}' の merge-base を取得できません。"
  meta=$(git_meta "${mb}..${ref}" "${mb}..${ref}")
  state=$(local_code_state "$ref")
  extra=$(jq -n --arg db "$db" --arg ref "$ref" '{default_branch: $db, resolved_ref: $ref}')
  emit "branch" "ブランチ ${display} (${db} からの差分)" "$mb" "$display" \
       "git diff ${mb}..${ref}" "$state" "$meta" "$extra"
}

# ---------------------------------------------------------------- dispatch
OUT=""
if [ -z "$ARG" ]; then
  if [ "$DIRTY" = true ]; then
    OUT=$(resolve_worktree) || exit $?
  else
    command -v gh >/dev/null 2>&1 || undecided "未コミットの変更がなく、gh CLI もないため対象を特定できません。PR 番号 / commit / ブランチ名を指定してください。"
    num=$(gh pr view --json number -q .number 2>/dev/null) \
      || undecided "未コミットの変更がなく、カレントブランチに対応する PR も見つかりません。PR 番号 / commit / ブランチ名を指定してください。"
    OUT=$(resolve_pr "$num" "") || exit $?
  fi
elif [[ "$ARG" =~ ^[0-9]+$ ]]; then
  OUT=$(resolve_pr "$ARG" "") || exit $?
elif [[ "$ARG" =~ ^https?://[^/]*github\.com/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  OUT=$(resolve_pr "${BASH_REMATCH[3]}" "--repo ${BASH_REMATCH[1]}/${BASH_REMATCH[2]}") || exit $?
elif [[ "$ARG" == *".."* ]]; then
  OUT=$(resolve_range "$ARG") || exit $?
elif [ "$ARG" != "HEAD" ] && [ "$ARG" != "@" ] && BRANCH_REF=$(resolve_branch_ref "$ARG"); then
  OUT=$(resolve_branch "$BRANCH_REF" "$ARG") || exit $?
elif [[ "$ARG" =~ ^[0-9a-fA-F]{7,40}$ ]] && git rev-parse --verify --quiet "${ARG}^{commit}" >/dev/null 2>&1; then
  OUT=$(resolve_commit "$ARG") || exit $?
elif git rev-parse --verify --quiet "${ARG}^{commit}" >/dev/null 2>&1; then
  OUT=$(resolve_commit "$ARG") || exit $?
else
  undecided "'${ARG}' を PR 番号 / PR URL / commit / 範囲 / ブランチ名 のいずれとしても解決できません。"
fi

[ -z "$OUT" ] && die "対象の解決に失敗しました (内部エラー)。"

jq --argjson dirty "$DIRTY" '. + {dirty_worktree: $dirty}' <<<"$OUT"
