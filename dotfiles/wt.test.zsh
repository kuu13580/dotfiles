#!/usr/bin/env zsh
# ============================================================================
# wt.test.zsh - minimal test suite for wt.zsh
#
# Run: zsh ~/dotfiles/dotfiles/wt.test.zsh
# Scope: pure-logic / git-side flows (fzf / claude / EDITOR は対象外)
# ============================================================================

emulate -L zsh

# -------------------- harness ----------------------------------------------
typeset -i PASS=0 FAIL=0
typeset -a FAILED=()

_pass() { (( PASS++ )); printf '  \033[32m✓\033[0m %s\n' "$1"; }
_fail() {
  (( FAIL++ )); FAILED+=("$1")
  printf '  \033[31m✗\033[0m %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '      %s\n' "$2"
  [[ -n "${3:-}" ]] && printf '      %s\n' "$3"
}

_assert_eq() {
  local got="$1" expected="$2" name="$3"
  if [[ "$got" == "$expected" ]]; then _pass "$name"
  else _fail "$name" "expected: $expected" "got:      $got"
  fi
}
_assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  if [[ "$haystack" == *"$needle"* ]]; then _pass "$name"
  else _fail "$name" "expected to contain: $needle" "got: $haystack"
  fi
}
_assert_neq() {
  local got="$1" forbidden="$2" name="$3"
  if [[ "$got" != "$forbidden" ]]; then _pass "$name"
  else _fail "$name" "should not be: $forbidden"
  fi
}

# -------------------- setup ------------------------------------------------
typeset -g THIS_DIR="${${(%):-%x}:A:h}"
if [[ ! -f "$THIS_DIR/wt.zsh" ]]; then
  echo "wt.zsh not found next to test file ($THIS_DIR)"; exit 2
fi
source "$THIS_DIR/wt.zsh"

typeset -g TMP="$(mktemp -d -t wt-test.XXXXXX)"
trap "rm -rf '$TMP'" EXIT

# Avoid leakage from user's global git config that could affect test outcomes
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test

_mkrepo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main 2>/dev/null || git -C "$dir" init -q
  git -C "$dir" commit --allow-empty -m init -q
}
_addwt() {
  local repo="$1" branch="$2" wt_path="$3"
  git -C "$repo" worktree add -b "$branch" "$wt_path" 2>/dev/null
}

# -------------------- tests ------------------------------------------------

test_help() {
  echo "[help]"
  local out; out="$(wt help 2>&1)"
  _assert_contains "$out" "USAGE" "help has USAGE"
  _assert_contains "$out" "wt new" "help has wt new"
  _assert_contains "$out" "wt cd"  "help has wt cd"
}

test_unknown_subcmd() {
  echo "[unknown subcommand]"
  local out; out="$(wt nonexistent 2>&1)"
  _assert_contains "$out" "unknown subcommand" "error message"
  ( wt nonexistent ) >/dev/null 2>&1; local rc=$?
  _assert_neq "$rc" "0" "nonzero exit"
}

test_new_validation() {
  echo "[wt new arg validation]"
  local out
  out="$(wt new task-foo 2>&1)";        _assert_contains "$out" "Usage:" "no -b → usage"
  out="$(wt new -b foo /abs/path 2>&1)"; _assert_contains "$out" "directory NAME only" "absolute path rejected"
  out="$(wt new -b foo sub/dir 2>&1)";   _assert_contains "$out" "directory NAME only" "relative path rejected"
  out="$(wt new -b foo 2>&1)";           _assert_contains "$out" "Usage:" "no <dir> → usage"
  out="$(wt new -b 2>&1)";               _assert_contains "$out" "requires an argument" "-b without value"
}

test_list_raw_parsing() {
  echo "[_wt_list_raw parsing]"
  local repo="$TMP/repo-list"
  _mkrepo "$repo"
  _addwt "$repo" "feature/foo" "$TMP/wt-foo"
  _addwt "$repo" "feature/bar" "$TMP/wt-bar"
  local main_sha; main_sha="$(git -C "$repo" rev-parse HEAD)"
  git -C "$repo" worktree add --detach "$TMP/wt-det" "$main_sha" 2>/dev/null

  local out; out="$(cd "$repo" && _wt_list_raw)"
  _assert_contains "$out" "$repo"        "main worktree path"
  _assert_contains "$out" "feature/foo"  "feature/foo branch"
  _assert_contains "$out" "feature/bar"  "feature/bar branch"
  _assert_contains "$out" "detached@"    "detached marker"
}

test_description_roundtrip() {
  echo "[description set/get/unset]"
  local repo="$TMP/repo-desc"
  _mkrepo "$repo"

  git -C "$repo" config --worktree wt.description "PR#1234 test"
  local got; got="$(git -C "$repo" config --worktree wt.description)"
  _assert_eq "$got" "PR#1234 test" "set/get roundtrip"

  git -C "$repo" config --worktree --unset wt.description
  got="$(git -C "$repo" config --worktree wt.description 2>/dev/null)"
  _assert_eq "$got" "" "unset clears value"
}

test_cd_resolution() {
  echo "[wt cd name resolution]"
  local repo="$TMP/repo-cd"
  _mkrepo "$repo"
  _addwt "$repo" "branch-cd" "$TMP/cd-target"

  local final_pwd
  final_pwd="$(cd "$repo" && wt cd cd-target && pwd)"
  _assert_eq "$final_pwd" "$TMP/cd-target" "basename match"

  # suffix match (full path tail)
  final_pwd="$(cd "$repo" && wt cd "$TMP/cd-target" && pwd)"
  _assert_eq "$final_pwd" "$TMP/cd-target" "exact path match"

  local out; out="$(cd "$repo" && wt cd nonexistent-name 2>&1)"
  _assert_contains "$out" "no worktree matched" "nonexistent → error"
}

test_ls_format() {
  echo "[wt ls output]"
  local repo="$TMP/repo-ls"
  _mkrepo "$repo"
  _addwt "$repo" "feature/ls-test" "$TMP/ls-target"
  _wt_ensure_worktree_config "$TMP/ls-target"
  git -C "$TMP/ls-target" config --worktree wt.description "test desc"

  local out; out="$(cd "$repo" && wt ls)"
  _assert_contains "$out" "DIR"              "header has DIR"
  _assert_contains "$out" "BRANCH"           "header has BRANCH"
  _assert_contains "$out" "DESC"             "header has DESC"
  _assert_contains "$out" "feature/ls-test"  "branch shown"
  _assert_contains "$out" "test desc"        "description shown"
}

test_resolve_target_parent() {
  echo "[_wt_resolve_target_parent]"
  local fake_home="$TMP/fake-home"
  mkdir -p "$fake_home"

  local got
  got="$(HOME="$fake_home" _wt_resolve_target_parent "$fake_home/myrepo")"
  _assert_eq "$got" "$fake_home/myrepo-worktrees" "direct: HOME/<repo> (basename != main)"

  got="$(HOME="$fake_home" _wt_resolve_target_parent "$fake_home/main")"
  _assert_eq "$got" "$fake_home" "parent fallback: HOME/main (basename == main)"

  got="$(HOME="$fake_home" _wt_resolve_target_parent "$fake_home/sub/myrepo")"
  _assert_eq "$got" "$fake_home/sub" "parent: nested under HOME"

  got="$(HOME="$fake_home" _wt_resolve_target_parent "/other/somewhere/repo")"
  _assert_eq "$got" "/other/somewhere" "parent: outside HOME"
}

test_new_happy_path() {
  echo "[wt new end-to-end (parent pattern)]"
  local repo="$TMP/repo-new"
  _mkrepo "$repo"

  # $TMP is not under $HOME (or even if it is, basename != main / not direct under $HOME)
  # → parent pattern, target = $TMP/new-target
  local out; out="$(cd "$repo" && wt new -b feature/new-test new-target -d "PR#XX test" 2>&1)"
  _assert_contains "$out" "created" "wt new prints created"

  local branch; branch="$(git -C "$TMP/new-target" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  _assert_eq "$branch" "feature/new-test" "branch created"

  local desc; desc="$(git -C "$TMP/new-target" config --worktree wt.description 2>/dev/null)"
  _assert_eq "$desc" "PR#XX test" "description recorded"

  # duplicate target → error
  out="$(cd "$repo" && wt new -b feature/dup new-target 2>&1)"
  _assert_contains "$out" "already exists" "duplicate target rejected"
}

# -------------------- run --------------------------------------------------
echo "wt.zsh test suite"
echo "  source: $THIS_DIR/wt.zsh"
echo "  tmpdir: $TMP"
echo

test_help
test_unknown_subcmd
test_new_validation
test_list_raw_parsing
test_description_roundtrip
test_cd_resolution
test_ls_format
test_resolve_target_parent
test_new_happy_path

echo
echo "=========================================="
printf 'PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  echo "Failed:"
  for t in "${FAILED[@]}"; do printf '  - %s\n' "$t"; done
  exit 1
fi
echo "All tests passed."
exit 0
