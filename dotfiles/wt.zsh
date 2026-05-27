#!/usr/bin/env zsh
# ============================================================================
# wt.zsh - git worktree manager (zsh functions)
#
# Canonical : ~/dotfiles/dotfiles/wt.zsh
# Snapshot  : ${CLAUDE_PLUGIN_ROOT}/skills/wt-manager/scripts/wt.zsh
# Load      : ~/.zshrc 末尾で `source "${${(%):-%x}:A:h}/wt.zsh"` (相対)
#
# Subcommands: wt | wt new | wt ls | wt set | wt rm | wt claude | wt cd
# Specs     : plugins/wt-manager/REQUIREMENTS.md / skills/wt-manager/SKILL.md
# ============================================================================

# ---------- main dispatcher --------------------------------------------------
function wt() {
  emulate -L zsh
  local cmd="${1:-}"
  [[ -n "$cmd" ]] && shift
  case "$cmd" in
    "")              _wt_default      "$@" ;;
    new)             _wt_new          "$@" ;;
    ls|list)         _wt_ls           "$@" ;;
    set)             _wt_set          "$@" ;;
    rm|remove)       _wt_rm           "$@" ;;
    claude)          _wt_claude       "$@" ;;
    cd)              _wt_cd           "$@" ;;
    -h|--help|help)  _wt_help              ;;
    *) echo "wt: unknown subcommand '$cmd'" >&2; _wt_help >&2; return 1 ;;
  esac
}

# ---------- internal helpers -------------------------------------------------
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
}

# ---------- wt ls ------------------------------------------------------------
function _wt_ls() {
  _wt_check_deps || return 1
  local name age desc
  {
    printf 'DIR\tBRANCH\tAGE\tDESC\n'
    _wt_list_raw | while IFS=$'\t' read -r wt_path wt_branch wt_head; do
      name="$(basename "$wt_path")"
      age="$(git -C "$wt_path" log -1 --format='%cr' 2>/dev/null \
             | sed -E 's/ ago$//; s/ year(s)?/y/; s/ month(s)?/mo/; s/ week(s)?/w/; s/ day(s)?/d/; s/ hour(s)?/h/; s/ minute(s)?/m/; s/ second(s)?/s/' \
             | tr -d ' ')"
      desc="$(git -C "$wt_path" config --worktree wt.description 2>/dev/null | head -1)"
      printf '%s\t%s\t%s\t%s\n' "$name" "${wt_branch:-?}" "${age:-?}" "${desc:-(no description)}"
    done
  } | column -t -s $'\t'
}

# ---------- wt set -----------------------------------------------------------
function _wt_set() {
  _wt_check_deps || return 1
  local sel
  sel="$(_wt_fzf_select 'Set Description > ')" || return 1
  [[ -z "$sel" ]] && return 0

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

# ---------- wt rm ------------------------------------------------------------
function _wt_rm() {
  _wt_check_deps || return 1
  local selected
  selected="$(_wt_fzf_select 'Remove Worktree > ' multi)" || return 1
  [[ -z "$selected" ]] && return 0

  local -a paths
  paths=("${(@f)selected}")

  echo "wt rm: about to remove:"
  local p
  for p in "${paths[@]}"; do
    echo "  - $p"
  done
  printf 'Proceed? (y/N): '
  local confirm; read -r confirm
  if [[ "$confirm" != [yY]* ]]; then
    echo "wt rm: aborted"
    return 0
  fi

  printf 'Also delete branches? (y/N): '
  local del_branch; read -r del_branch

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

# ---------- wt claude --------------------------------------------------------
function _wt_claude() {
  _wt_check_deps || return 1
  if ! command -v claude >/dev/null 2>&1; then
    echo "wt claude: 'claude' command not found in PATH" >&2
    return 1
  fi
  local sel
  sel="$(_wt_fzf_select 'Claude Worktree > ')" || return 1
  [[ -z "$sel" ]] && return 0

  local desc
  desc="$(git -C "$sel" config --worktree wt.description 2>/dev/null)"
  if [[ -z "$desc" ]]; then
    printf 'Description is empty. Task (one line): '
    read -r desc
    if [[ -z "$desc" ]]; then
      echo "wt claude: aborted (empty task)"
      return 0
    fi
  fi

  echo "wt claude: cd '$sel' && claude --bg \"$desc\""
  ( cd "$sel" && claude --bg "$desc" )
}

# ---------- wt cd (must remain a function for cwd propagation) ---------------
function _wt_cd() {
  if (( $# == 0 )); then
    _wt_check_deps || return 1
    local sel
    sel="$(_wt_fzf_select 'cd to Worktree > ')" || return 1
    [[ -z "$sel" ]] && return 0
    cd -- "$sel"
    return $?
  fi

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

  if [[ -z "$found" ]]; then
    echo "wt cd: no worktree matched '$name'" >&2
    return 1
  fi
  cd -- "$found"
}

# ---------- wt help ----------------------------------------------------------
function _wt_help() {
  cat <<'EOF'
wt - git worktree manager (zsh functions)

USAGE
  wt                                 fzf select → pick editor (code/zed) → open
  wt new -b <br> <dir> [base] [-d desc]
                                     create new worktree (records description)
                                       <dir> must be a directory NAME only
                                       [base] omitted → git config wt.baseRef → HEAD
  wt ls                              list worktrees with metadata
  wt set                             fzf select → edit wt.description
                                       ($EDITOR if set, else inline prompt)
  wt rm                              fzf multi-select → remove worktree(s)
                                       branch deletion is confirmed separately
  wt claude                          fzf select → claude --bg "<wt.description>"
  wt cd [<name>]                     cd to worktree (zsh function only)
                                       no arg → fzf select
  wt help                            show this help

METADATA
  wt.description    per-worktree (git config --worktree)  "what is this for"
  wt.baseRef        per-repo     (git config)             default base ref for `wt new`

EXAMPLES
  wt new -b feature/foo task-foo origin/develop -d "PR#1234 verify"
  git config wt.baseRef origin/develop      # set default base for `wt new`
  wt cd task-foo                            # cd to worktree by directory name
EOF
}
