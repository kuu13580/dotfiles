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

# wt.zsh は internal ヘルパ (_wt_*) を wt() 内で定義し終了時に破棄する。
# ホワイトボックステストはヘルパを直接呼ぶため、WT_KEEP_INTERNAL=1 で破棄を抑止し、
# 一度 wt を呼んでヘルパをグローバルへ展開しておく。
export WT_KEEP_INTERNAL=1
wt help >/dev/null 2>&1

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

  # 引数なし + 非tty(stdin=/dev/null): 対話フォームに入らず usage エラーで即終了する
  # こと(read でハングしない)。Claude の非tty 呼び出し経路の不変条件。
  local rc
  out="$(wt new </dev/null 2>&1)"; rc=$?
  _assert_contains "$out" "Usage:" "no args + non-tty → usage (no interactive hang)"
  _assert_neq "$rc" "0" "no args + non-tty → nonzero exit"

  # 対話フォーム用の base 選択ヘルパが定義されていること。
  typeset -f _wt_pick_base >/dev/null; _assert_eq "$?" "0" "_wt_pick_base defined"
}

test_claude_arg_validation() {
  echo "[wt claude arg validation]"
  # Unknown options are rejected before fzf/claude — no session is launched.
  local out rc
  out="$(wt claude --bogus 2>&1)";       _assert_contains "$out" "unknown argument" "unknown option rejected"
  ( wt claude --bogus ) >/dev/null 2>&1; rc=$?
  _assert_neq "$rc" "0" "unknown option → nonzero exit"
  # -n requires a value (rejected before fzf/claude)
  out="$(wt claude -n 2>&1)";            _assert_contains "$out" "requires a name" "-n without value rejected"
  ( wt claude -n ) >/dev/null 2>&1; rc=$?
  _assert_neq "$rc" "0" "-n without value → nonzero exit"
  # positional <name> resolves against worktrees (before the claude-command check)
  local repo="$TMP/repo-claude"
  _mkrepo "$repo"
  out="$(cd "$repo" && wt claude nonexistent-wt 2>&1)"
  _assert_contains "$out" "no worktree matched" "unmatched name rejected"
  # help documents the -n flag and the idle default
  out="$(wt help 2>&1)"
  _assert_contains "$out" "wt claude"  "help has wt claude"
  _assert_contains "$out" "idle"       "help mentions idle default"
  _assert_contains "$out" "-n <label>" "help documents -n"
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

  # -p adds absolute PATH column
  out="$(cd "$repo" && wt ls -p)"
  _assert_contains "$out" "PATH"             "header has PATH with -p"
  _assert_contains "$out" "$TMP/ls-target"   "absolute path shown with -p"
  out="$(cd "$repo" && wt ls -x 2>&1)"
  _assert_contains "$out" "unknown option"   "unknown option rejected"
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

test_resolve_name() {
  echo "[_wt_resolve_name]"
  local repo="$TMP/repo-resolve"
  _mkrepo "$repo"
  _addwt "$repo" "branch-res" "$TMP/res-target"

  local got
  got="$(cd "$repo" && _wt_resolve_name res-target)"
  _assert_eq "$got" "$TMP/res-target" "basename match"
  got="$(cd "$repo" && _wt_resolve_name "$TMP/res-target")"
  _assert_eq "$got" "$TMP/res-target" "exact path match"
  ( cd "$repo" && _wt_resolve_name nonexistent-wt ) >/dev/null 2>&1
  _assert_neq "$?" "0" "no match → nonzero"
}

test_set_noninteractive() {
  echo "[wt set non-interactive]"
  local repo="$TMP/repo-set"
  _mkrepo "$repo"
  _addwt "$repo" "branch-set" "$TMP/set-target"

  local out got
  out="$(cd "$repo" && wt set set-target "PR#42 review")"
  _assert_contains "$out" "updated" "set <name> <desc> prints updated"
  got="$(git -C "$TMP/set-target" config --worktree wt.description)"
  _assert_eq "$got" "PR#42 review" "description written"

  out="$(cd "$repo" && wt set set-target "")"
  _assert_contains "$out" "cleared" "empty desc clears"
  got="$(git -C "$TMP/set-target" config --worktree wt.description 2>/dev/null)"
  _assert_eq "$got" "" "description cleared"

  out="$(cd "$repo" && wt set nonexistent-wt "x" 2>&1)"
  _assert_contains "$out" "no worktree matched" "unmatched name rejected"
  out="$(cd "$repo" && wt set a b c 2>&1)"
  _assert_contains "$out" "Usage:" "too many args → usage"
}

test_rm_noninteractive() {
  echo "[wt rm non-interactive]"
  local repo="$TMP/repo-rm"
  _mkrepo "$repo"
  _addwt "$repo" "branch-rm-keep" "$TMP/rm-keep"
  _addwt "$repo" "branch-rm-del"  "$TMP/rm-del"

  local out
  # -y: remove worktree, keep branch
  out="$(cd "$repo" && wt rm rm-keep -y 2>&1)"
  _assert_contains "$out" "removed" "rm <name> -y removes"
  if [[ -d "$TMP/rm-keep" ]]; then _fail "worktree dir gone"; else _pass "worktree dir gone"; fi
  if git -C "$repo" show-ref --verify -q refs/heads/branch-rm-keep; then
    _pass "branch kept without -b"
  else
    _fail "branch kept without -b"
  fi

  # -y -b: remove worktree and its branch
  out="$(cd "$repo" && wt rm rm-del -y -b 2>&1)"
  _assert_contains "$out" "branch deleted" "rm -y -b reports branch deletion"
  if git -C "$repo" show-ref --verify -q refs/heads/branch-rm-del; then
    _fail "branch deleted with -b"
  else
    _pass "branch deleted with -b"
  fi

  out="$(cd "$repo" && wt rm nonexistent-wt -y 2>&1)"
  _assert_contains "$out" "no worktree matched" "unmatched name rejected"
  out="$(cd "$repo" && wt rm -x 2>&1)"
  _assert_contains "$out" "unknown option" "unknown option rejected"
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

test_postnew_hook() {
  echo "[wt new postNew hook (git config wt.postNew)]"
  local repo="$TMP/repo-postnew"
  _mkrepo "$repo"

  # hook: env を marker に書き出し、main worktree からファイルをコピーする
  echo "secret-key" > "$repo/key.src"
  git -C "$repo" config wt.postNew \
    'printf "%s|%s|%s\n" "$WT_NEW_BRANCH" "$WT_MAIN_WORKTREE" "$WT_NEW_PATH" > marker.txt; cp "$WT_MAIN_WORKTREE/key.src" key.copied'

  local out; out="$(cd "$repo" && wt new -b feature/hook hook-target -d "hook test" 2>&1)"
  _assert_contains "$out" "running postNew hook" "postNew hook announced"
  _assert_contains "$out" "postNew hook completed" "postNew hook completed"

  # cwd=新 worktree で実行されたか (marker が新 worktree に出来ている)
  _assert_eq "$(cat "$TMP/hook-target/marker.txt" 2>/dev/null | cut -d'|' -f1)" "feature/hook" "WT_NEW_BRANCH passed"
  _assert_eq "$(cat "$TMP/hook-target/marker.txt" 2>/dev/null | cut -d'|' -f2)" "$repo" "WT_MAIN_WORKTREE = main worktree"
  _assert_eq "$(cat "$TMP/hook-target/marker.txt" 2>/dev/null | cut -d'|' -f3)" "$TMP/hook-target" "WT_NEW_PATH = new worktree"
  _assert_eq "$(cat "$TMP/hook-target/key.copied" 2>/dev/null)" "secret-key" "file copied from main worktree"

  # 未設定 repo ではフックは走らない
  local repo2="$TMP/repo-nohook"
  _mkrepo "$repo2"
  out="$(cd "$repo2" && wt new -b feature/nohook nohook-target 2>&1)"
  if [[ "$out" != *"running postNew hook"* ]]; then _pass "no postNew run when unset"
  else _fail "no postNew run when unset" "hook ran unexpectedly"; fi

  # フック非ゼロ終了 → 警告のみで worktree は作成される
  local repo3="$TMP/repo-hookfail"
  _mkrepo "$repo3"
  git -C "$repo3" config wt.postNew 'exit 3'
  out="$(cd "$repo3" && wt new -b feature/hookfail hookfail-target 2>&1)"
  _assert_contains "$out" "created" "worktree created despite hook failure"
  _assert_contains "$out" "exited non-zero" "hook failure warned"
}

test_dir_candidates() {
  echo "[_wt_dir_candidates]"
  local got
  # '_' 区切りで前半から1段ずつ削る (先頭の feature/ は :t で除去済み)
  got="$(_wt_dir_candidates feature/077_TICKET-5_update-translate | paste -sd, -)"
  _assert_eq "$got" "077_TICKET-5_update-translate,TICKET-5_update-translate,update-translate" \
    "multi-segment splits from the front"

  got="$(_wt_dir_candidates feature/hotfix | paste -sd, -)"
  _assert_eq "$got" "hotfix" "no '_' → single candidate"

  got="$(_wt_dir_candidates plain-branch | paste -sd, -)"
  _assert_eq "$got" "plain-branch" "no '/' nor '_' → branch itself"
}

# -------------------- run --------------------------------------------------
echo "wt.zsh test suite"
echo "  source: $THIS_DIR/wt.zsh"
echo "  tmpdir: $TMP"
echo

test_help
test_unknown_subcmd
test_new_validation
test_claude_arg_validation
test_list_raw_parsing
test_description_roundtrip
test_cd_resolution
test_ls_format
test_resolve_target_parent
test_resolve_name
test_set_noninteractive
test_rm_noninteractive
test_new_happy_path
test_postnew_hook
test_dir_candidates

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
