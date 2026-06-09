#!/usr/bin/env zsh
# ============================================================================
# wt.zsh - git worktree manager (single public zsh function)
#
# Canonical : ~/dotfiles/dotfiles/wt.zsh
# Snapshot  : ${CLAUDE_PLUGIN_ROOT}/skills/wt-manager/scripts/wt.zsh
# Load      : ~/.zshrc 末尾で `source "${${(%):-%x}:A:h}/wt.zsh"` (相対)
#
# Subcommands: wt | wt new | wt ls | wt set | wt rm | wt claude | wt cd
# Specs     : plugins/wt-manager/REQUIREMENTS.md / skills/wt-manager/SKILL.md
#
# 設計メモ (内包方式):
#   トップレベルに公開する関数は `wt` ただ1つ。内部ヘルパ (_wt_*) は wt() の
#   実行時にこの関数内で定義し、終了時に `unfunction -m '_wt_*'` で破棄する。狙い:
#     1. 対話シェルの名前空間・タブ補完を internal ヘルパで汚さない (公開ゼロ)
#     2. Claude Code のシェルスナップショットは「先頭 `_` のトップレベル関数」を
#        除外するため、_wt_* をトップレベルに置くと Claude の Bash から wt new 等が
#        動かない。wt() 内包なら snapshot に載るのは wt だけで、wt 経由で全
#        サブコマンドが動作する
#   テスト用: 環境変数 WT_KEEP_INTERNAL=1 のときは破棄をスキップし、一度 wt を
#   呼べば _wt_* がグローバルに残る (ホワイトボックステストから直接呼べる)。
# ============================================================================

function wt() {
  emulate -L zsh

# ======================= internal helpers (per-invocation) ==================
# 以降のヘルパは wt 実行時に定義され、関数末尾で破棄される (WT_KEEP_INTERNAL で保持)。
# ヒアドキュメント終端マーカーを行頭に保つため、ヘルパ本体はインデントしない。

function _wt_check_deps() {
  local missing=()
  local c
  for c in git fzf; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  if (( ${#missing[@]} > 0 )); then
    echo "wt: missing required commands: ${missing[*]}" >&2
    return 1
  fi
}

# Ensure extensions.worktreeConfig is enabled on the repo containing <path>.
# Required to use `git config --worktree` on non-main worktrees.
# Safe to call repeatedly; no-op if already enabled.
function _wt_ensure_worktree_config() {
  local at="$1"
  local cur
  cur="$(git -C "$at" config --get extensions.worktreeConfig 2>/dev/null)"
  if [[ "$cur" != "true" ]]; then
    git -C "$at" config extensions.worktreeConfig true
  fi
}

# Resolve placement parent dir for a new worktree given a repo_root.
# Pure function: depends only on $1 and $HOME (overridable for tests).
#   direct pattern: parent == $HOME && basename != "main" → $HOME/<repo>-worktrees
#   parent pattern: else                                  → <parent>
function _wt_resolve_target_parent() {
  local repo_root="$1"
  local parent_dir="${repo_root:h}"
  local repo_base="${repo_root:t}"
  if [[ "$parent_dir" == "$HOME" && "$repo_base" != "main" ]]; then
    echo "$HOME/${repo_base}-worktrees"
  else
    echo "$parent_dir"
  fi
}

# Emit TSV per worktree: <path>\t<branch>\t<head>
function _wt_list_raw() {
  git worktree list --porcelain 2>/dev/null | awk '
    function flush() { if (p != "") { print p"\t"b"\t"h; p=""; b=""; h="" } }
    /^worktree / { flush(); p=substr($0,10) }
    /^HEAD /     { h=substr($0,6) }
    /^branch /   { b=substr($0,8); sub(/^refs\/heads\//,"",b) }
    /^detached/  { if (h != "") b="detached@"substr(h,1,11) }
    END          { flush() }
  '
}

# Resolve a worktree by name: basename match first, then exact/suffix path match.
# Prints the absolute path; returns 1 if no worktree matched.
function _wt_resolve_name() {
  local name="$1"
  local found=""

  while IFS=$'\t' read -r wt_path wt_branch wt_head; do
    if [[ "$(basename "$wt_path")" == "$name" ]]; then
      found="$wt_path"; break
    fi
  done < <(_wt_list_raw)

  if [[ -z "$found" ]]; then
    while IFS=$'\t' read -r wt_path wt_branch wt_head; do
      if [[ "$wt_path" == "$name" || "$wt_path" == *"/$name" ]]; then
        found="$wt_path"; break
      fi
    done < <(_wt_list_raw)
  fi

  [[ -z "$found" ]] && return 1
  print -r -- "$found"
}

# POSIX-sh preview script used by fzf. fzf substitutes {1} with the (quoted) path.
function _wt_fzf_preview_cmd() {
  cat <<'PREVIEW_SH'
p={1}
if [ -d "$p" ]; then
  b=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ "$b" = HEAD ] && b="detached@$(git -C "$p" rev-parse --short=11 HEAD 2>/dev/null)"
  age=$(git -C "$p" log -1 --format="%cr" 2>/dev/null)
  d=$(git -C "$p" config --worktree wt.description 2>/dev/null)
  printf "BRANCH:      %s\nPATH:        %s\nAGE:         %s\nDESCRIPTION:\n" "${b:-?}" "$p" "${age:-?}"
  if [ -n "$d" ]; then printf "%s\n" "$d" | sed "s/^/  /"; else echo "  (no description)"; fi
fi
PREVIEW_SH
}

# Select worktree(s) via fzf. Outputs selected absolute path(s), one per line.
# args: $1 prompt, $2 = "multi" for multi-select
function _wt_fzf_select() {
  local prompt="${1:-Select Worktree > }"
  local multi="${2:-}"

  local -a fzf_opts
  fzf_opts=(--height 60% --reverse --border --prompt="$prompt" --ansi
            --delimiter=$'\t' --with-nth=2,3,5
            --preview "$(_wt_fzf_preview_cmd)"
            --preview-window=right:55%)
  [[ "$multi" == multi ]] && fzf_opts+=(--multi --header "Tabで複数選択 / Enterで確定")

  local input name age desc1
  input="$(
    _wt_list_raw | while IFS=$'\t' read -r wt_path wt_branch wt_head; do
      name="$(basename "$wt_path")"
      age="$(git -C "$wt_path" log -1 --format='%cr' 2>/dev/null | head -1)"
      desc1="$(git -C "$wt_path" config --worktree wt.description 2>/dev/null | head -1)"
      printf '%s\t%s\t%s\t%s\t%s\n' "$wt_path" "$name" "${wt_branch:-?}" "${age:-?}" "${desc1:-(no description)}"
    done
  )"
  [[ -z "$input" ]] && { echo "wt: no worktrees found" >&2; return 1; }

  print -r -- "$input" | fzf "${fzf_opts[@]}" | awk -F'\t' '{print $1}'
}

# ---------- wt (no args) -----------------------------------------------------
function _wt_default() {
  _wt_check_deps || return 1
  local sel
  sel="$(_wt_fzf_select 'Open Worktree > ')" || return 1
  [[ -z "$sel" ]] && return 0

  local editor
  editor="$(printf 'code\nzed\n' | fzf --height 20% --reverse --border --prompt='Editor > ')"
  [[ -z "$editor" ]] && return 0

  case "$editor" in
    code) command code "$sel" ;;
    zed)  command zed  "$sel" ;;
    *)    echo "wt: unknown editor: $editor" >&2; return 1 ;;
  esac
}

# ---------- wt new -b <branch> <dir> [base] [-d desc] ------------------------
function _wt_new() {
  _wt_check_deps || return 1

  local branch="" dir="" base="" desc=""
  while (( $# > 0 )); do
    case "$1" in
      -b) [[ -z "${2:-}" ]] && { echo "wt new: -b requires an argument" >&2; return 1; }
          branch="$2"; shift 2 ;;
      -d) [[ -z "${2:-}" ]] && { echo "wt new: -d requires an argument" >&2; return 1; }
          desc="$2"; shift 2 ;;
      --) shift; break ;;
      -*) echo "wt new: unknown option: $1" >&2; return 1 ;;
      *)
        if   [[ -z "$dir"  ]]; then dir="$1"
        elif [[ -z "$base" ]]; then base="$1"
        else echo "wt new: too many positional args (got '$1')" >&2; return 1
        fi
        shift ;;
    esac
  done

  if [[ -z "$branch" || -z "$dir" ]]; then
    echo "Usage: wt new -b <branch> <dir> [base] [-d desc]" >&2
    return 1
  fi
  if [[ "$dir" == *"/"* ]]; then
    echo "wt new: <dir> must be a directory NAME only (no '/'); got '$dir'" >&2
    return 1
  fi

  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "wt new: not inside a git repository" >&2
    return 1
  }

  local target_parent
  target_parent="$(_wt_resolve_target_parent "$repo_root")"
  local target_path="$target_parent/$dir"

  if [[ -e "$target_path" ]]; then
    echo "wt new: target already exists: $target_path" >&2
    return 1
  fi
  if [[ -z "$base" ]]; then
    base="$(git config wt.baseRef 2>/dev/null)"
  fi

  mkdir -p "$target_parent" || return 1

  local -a gwt_args=(worktree add -b "$branch" "$target_path")
  [[ -n "$base" ]] && gwt_args+=("$base")

  echo "wt new: git ${gwt_args[*]}"
  git "${gwt_args[@]}" || return 1

  if [[ -n "$desc" ]]; then
    _wt_ensure_worktree_config "$target_path"
    git -C "$target_path" config --worktree wt.description "$desc"
    echo "wt new: description recorded"
  else
    echo "wt new: warning - description (-d) not provided. Run 'wt set' to add one." >&2
  fi
  echo "wt new: created $target_path"

  _wt_run_postnew "$target_path" "$branch" "$repo_root"
}

# ---------- postNew hook (opt-in per repo) -----------------------------------
# 新しい worktree 作成直後に `git config wt.postNew` のコマンドを実行する。
# repo 単位の opt-in (共有 .git/config に保存されるため全 worktree で有効)。
# 未設定の repo では何もしない。フックは cwd=新 worktree で実行され、以下の env を受け取る:
#   WT_NEW_PATH      新しい worktree の絶対パス
#   WT_NEW_BRANCH    新 worktree の branch 名
#   WT_MAIN_WORKTREE main worktree のパス (gitignore されたファイルのコピー元等に)
#   WT_REPO_ROOT     `wt new` を呼んだ repo root
# フックが非ゼロ終了しても警告のみで `wt new` は失敗扱いにしない (worktree は既に存在する)。
function _wt_run_postnew() {
  local new_path="$1" branch="$2" repo_root="$3"
  local hook
  hook="$(git -C "$new_path" config wt.postNew 2>/dev/null)"
  [[ -z "$hook" ]] && return 0

  local main_wt
  main_wt="$(git -C "$new_path" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"

  echo "wt new: running postNew hook (git config wt.postNew)"
  if ( cd "$new_path" \
       && WT_NEW_PATH="$new_path" WT_NEW_BRANCH="$branch" \
          WT_MAIN_WORKTREE="$main_wt" WT_REPO_ROOT="$repo_root" \
          zsh -c "$hook" ); then
    echo "wt new: postNew hook completed"
  else
    echo "wt new: warning - postNew hook exited non-zero (worktree kept)" >&2
  fi
}

# ---------- wt ls [-p] --------------------------------------------------------
#   -p / --path: add absolute PATH column (e.g. to feed EnterWorktree({path}))
function _wt_ls() {
  _wt_check_deps || return 1

  local show_path=0
  case "${1:-}" in
    "") ;;
    -p|--path) show_path=1 ;;
    *) echo "wt ls: unknown option: $1" >&2
       echo "Usage: wt ls [-p]" >&2
       return 1 ;;
  esac

  local name age desc
  {
    if (( show_path )); then
      printf 'DIR\tBRANCH\tAGE\tPATH\tDESC\n'
    else
      printf 'DIR\tBRANCH\tAGE\tDESC\n'
    fi
    _wt_list_raw | while IFS=$'\t' read -r wt_path wt_branch wt_head; do
      name="$(basename "$wt_path")"
      age="$(git -C "$wt_path" log -1 --format='%cr' 2>/dev/null \
             | sed -E 's/ ago$//; s/ year(s)?/y/; s/ month(s)?/mo/; s/ week(s)?/w/; s/ day(s)?/d/; s/ hour(s)?/h/; s/ minute(s)?/m/; s/ second(s)?/s/' \
             | tr -d ' ')"
      desc="$(git -C "$wt_path" config --worktree wt.description 2>/dev/null | head -1)"
      if (( show_path )); then
        printf '%s\t%s\t%s\t%s\t%s\n' "$name" "${wt_branch:-?}" "${age:-?}" "$wt_path" "${desc:-(no description)}"
      else
        printf '%s\t%s\t%s\t%s\n' "$name" "${wt_branch:-?}" "${age:-?}" "${desc:-(no description)}"
      fi
    done
  } | column -t -s $'\t'
}

# ---------- wt set [<name>] ["<desc>"] ---------------------------------------
#   no args          → fzf select → $EDITOR / inline prompt (interactive)
#   <name>           → skip fzf → $EDITOR / inline prompt
#   <name> "<desc>"  → fully non-interactive (empty "" clears the description)
function _wt_set() {
  _wt_check_deps || return 1

  if (( $# > 2 )); then
    echo "Usage: wt set [<name>] [\"<desc>\"]" >&2
    return 1
  fi

  local sel
  if (( $# >= 1 )); then
    sel="$(_wt_resolve_name "$1")" || {
      echo "wt set: no worktree matched '$1'" >&2
      return 1
    }
  else
    sel="$(_wt_fzf_select 'Set Description > ')" || return 1
    [[ -z "$sel" ]] && return 0
  fi

  if (( $# == 2 )); then
    _wt_ensure_worktree_config "$sel"
    if [[ -z "$2" ]]; then
      git -C "$sel" config --worktree --unset wt.description 2>/dev/null
      echo "wt set: cleared description for $(basename "$sel")"
    else
      git -C "$sel" config --worktree wt.description "$2"
      echo "wt set: updated $(basename "$sel")"
    fi
    return 0
  fi

  local current
  current="$(git -C "$sel" config --worktree wt.description 2>/dev/null)"
  local new=""

  if [[ -n "${EDITOR:-}" ]]; then
    local tmpfile
    tmpfile="$(mktemp -t wt-desc.XXXXXX)" || return 1
    [[ -n "$current" ]] && printf '%s\n' "$current" >"$tmpfile"
    eval "$EDITOR \"\$tmpfile\""
    new="$(<"$tmpfile")"
    new="${new%$'\n'}"   # strip single trailing newline
    rm -f "$tmpfile"
  else
    echo "Current description for $(basename "$sel"):"
    if [[ -n "$current" ]]; then
      printf '%s\n' "$current" | sed 's/^/  /'
    else
      echo "  (none)"
    fi
    printf 'New description (single line, empty to unset): '
    read -r new
  fi

  _wt_ensure_worktree_config "$sel"
  if [[ -z "$new" ]]; then
    git -C "$sel" config --worktree --unset wt.description 2>/dev/null
    echo "wt set: cleared description for $(basename "$sel")"
  else
    git -C "$sel" config --worktree wt.description "$new"
    echo "wt set: updated $(basename "$sel")"
  fi
}

# ---------- wt rm [<name>...] [-y] [-b] --------------------------------------
#   no names → fzf multi-select (interactive)
#   <name>...→ skip fzf
#   -y       → skip "Proceed?" confirmation (required for non-interactive use)
#   -b       → also delete branches (without -b in -y mode, branches are kept)
function _wt_rm() {
  _wt_check_deps || return 1

  local auto=0 branch_flag=0
  local -a names=()
  while (( $# > 0 )); do
    case "$1" in
      -y|--yes)    auto=1; shift ;;
      -b|--branch) branch_flag=1; shift ;;
      -*) echo "wt rm: unknown option: $1" >&2
          echo "Usage: wt rm [<name>...] [-y] [-b]" >&2
          return 1 ;;
      *) names+=("$1"); shift ;;
    esac
  done

  local -a paths=()
  local p
  if (( ${#names[@]} > 0 )); then
    local n
    for n in "${names[@]}"; do
      p="$(_wt_resolve_name "$n")" || {
        echo "wt rm: no worktree matched '$n'" >&2
        return 1
      }
      paths+=("$p")
    done
  else
    local selected
    selected="$(_wt_fzf_select 'Remove Worktree > ' multi)" || return 1
    [[ -z "$selected" ]] && return 0
    paths=("${(@f)selected}")
  fi

  echo "wt rm: about to remove:"
  for p in "${paths[@]}"; do
    echo "  - $p"
  done

  local del_branch=""
  if (( auto )); then
    (( branch_flag )) && del_branch="y"
  else
    printf 'Proceed? (y/N): '
    local confirm; read -r confirm
    if [[ "$confirm" != [yY]* ]]; then
      echo "wt rm: aborted"
      return 0
    fi
    if (( branch_flag )); then
      del_branch="y"
    else
      printf 'Also delete branches? (y/N): '
      read -r del_branch
    fi
  fi

  for p in "${paths[@]}"; do
    local branch=""
    branch="$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)"
    [[ "$branch" == HEAD ]] && branch=""

    if git worktree remove "$p"; then
      echo "  removed: $p"
      if [[ "$del_branch" == [yY]* && -n "$branch" ]]; then
        if git branch -d "$branch" 2>/dev/null; then
          echo "  branch deleted: $branch"
        else
          echo "  branch '$branch' not safely deletable; force with: git branch -D $branch" >&2
        fi
      fi
    else
      echo "  failed to remove: $p (try: git worktree remove --force '$p')" >&2
    fi
  done
}

# ---------- wt claude [<name>] [-t [task]] -----------------------------------
# Default: launch an *idle* background session in the worktree (no prompt) —
#   just spin up a session; you send the first prompt yourself via Agent View.
# `<name>`: skip fzf and target the worktree by name (non-interactive).
# `-t` (or `--task`): seed the session with an initial task.
#   `wt claude -t`            → use the worktree's wt.description as the task
#   `wt claude -t "<task...>"` → use the given text as the task
function _wt_claude() {
  _wt_check_deps || return 1

  local name="" label="" label_set=0
  while (( $# )); do
    case "$1" in
      -n|--name)
        shift
        if [[ -z "${1:-}" ]]; then
          echo "wt claude: -n requires a name" >&2
          return 1
        fi
        label="$1"; label_set=1; shift
        ;;
      -*)
        echo "wt claude: unknown argument: $1" >&2
        echo "Usage: wt claude [<name>] [-n <label>]" >&2
        return 1
        ;;
      *)
        if [[ -z "$name" ]]; then
          name="$1"; shift
        else
          echo "wt claude: unexpected argument: $1" >&2
          echo "Usage: wt claude [<name>] [-n <label>]" >&2
          return 1
        fi
        ;;
    esac
  done

  local sel
  if [[ -n "$name" ]]; then
    sel="$(_wt_resolve_name "$name")" || {
      echo "wt claude: no worktree matched '$name'" >&2
      return 1
    }
  fi

  if ! command -v claude >/dev/null 2>&1; then
    echo "wt claude: 'claude' command not found in PATH" >&2
    return 1
  fi

  if [[ -z "$sel" ]]; then
    sel="$(_wt_fzf_select 'Claude Worktree > ')" || return 1
    [[ -z "$sel" ]] && return 0
  fi

  # 表示名: -n 明示 > wt.description > ディレクトリ名
  if (( ! label_set )); then
    label="$(git -C "$sel" config --worktree wt.description 2>/dev/null)"
    label="${label:-${sel:t}}"
  fi

  echo "wt claude: cd '$sel' && claude --bg -n \"$label\"   (idle — send a prompt to start)"
  ( cd "$sel" && claude --bg -n "$label" )
}

# ---------- wt cd (cwd propagates because wt itself is a function) -----------
function _wt_cd() {
  if (( $# == 0 )); then
    _wt_check_deps || return 1
    local sel
    sel="$(_wt_fzf_select 'cd to Worktree > ')" || return 1
    [[ -z "$sel" ]] && return 0
    cd -- "$sel"
    return $?
  fi

  local found
  found="$(_wt_resolve_name "$1")" || {
    echo "wt cd: no worktree matched '$1'" >&2
    return 1
  }
  cd -- "$found"
}

# ---------- wt help ----------------------------------------------------------
function _wt_help() {
  cat <<'EOF'
wt - git worktree manager (zsh function)

USAGE
  wt                                 fzf select → pick editor (code/zed) → open
  wt new -b <br> <dir> [base] [-d desc]
                                     create new worktree (records description)
                                       <dir> must be a directory NAME only
                                       [base] omitted → git config wt.baseRef → HEAD
  wt ls [-p]                         list worktrees with metadata
                                       -p  add absolute PATH column
  wt set [<name>] ["<desc>"]         edit/set wt.description
                                       no args → fzf select + $EDITOR/prompt
                                       <name>  → skip fzf (then $EDITOR/prompt)
                                       <name> "<desc>" → non-interactive ("" clears)
  wt rm [<name>...] [-y] [-b]        remove worktree(s)
                                       no names → fzf multi-select
                                       -y  skip confirmation (non-interactive)
                                       -b  also delete branches
  wt claude [<name>] [-n <label>]    claude --bg in the worktree (idle session)
                                       <name>      → skip fzf (non-interactive)
                                       -n <label>  → session display name
                                                     (default: wt.description, else dir name)
  wt cd [<name>]                     cd to worktree (zsh function only)
                                       no arg → fzf select
  wt help                            show this help

METADATA
  wt.description    per-worktree (git config --worktree)  "what is this for"
  wt.baseRef        per-repo     (git config)             default base ref for `wt new`
  wt.postNew        per-repo     (git config)             command run after `wt new`
                      cwd = new worktree; env: WT_NEW_PATH WT_NEW_BRANCH
                      WT_MAIN_WORKTREE WT_REPO_ROOT  (non-zero exit = warning only)

EXAMPLES
  wt new -b feature/foo task-foo origin/develop -d "PR#1234 verify"
  git config wt.baseRef origin/develop      # set default base for `wt new`
  wt cd task-foo                            # cd to worktree by directory name
  git config wt.postNew 'cp "$WT_MAIN_WORKTREE/.env.keys" .env.keys'   # opt-in postNew
EOF
}

# ================================ dispatch ==================================
  local cmd="${1:-}"
  [[ -n "$cmd" ]] && shift
  local rc=0
  case "$cmd" in
    "")              _wt_default      "$@"; rc=$? ;;
    new)             _wt_new          "$@"; rc=$? ;;
    ls|list)         _wt_ls           "$@"; rc=$? ;;
    set)             _wt_set          "$@"; rc=$? ;;
    rm|remove)       _wt_rm           "$@"; rc=$? ;;
    claude)          _wt_claude       "$@"; rc=$? ;;
    cd)              _wt_cd           "$@"; rc=$? ;;
    -h|--help|help)  _wt_help; rc=$? ;;
    *) echo "wt: unknown subcommand '$cmd'" >&2; _wt_help >&2; rc=1 ;;
  esac

  # cleanup: 対話シェルに internal ヘルパを残さない (テスト時は WT_KEEP_INTERNAL で保持)
  [[ -n "${WT_KEEP_INTERNAL:-}" ]] || unfunction -m '_wt_*' 2>/dev/null
  return $rc
}
