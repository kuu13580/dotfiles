#!/usr/bin/env bash
# rebase の進行を1ステップ進め、停止状態を JSON で stdout に出す。
#
# usage:
#   rebase-step.sh start <base>   backup ref と状態ファイルを作って rebase 開始
#   rebase-step.sh adopt          ユーザーが手で始めた rebase を引き継ぐ (状態ファイルが無ければ作る)
#   rebase-step.sh continue       マーカー残存を検査してから --continue
#   rebase-step.sh skip           現在のコミットを捨てて --skip
#   rebase-step.sh status         現在の停止状態のみ
#   rebase-step.sh abort          --abort。backup ref は残す
#   rebase-step.sh finish         完了後: 判断記録・消えたコミットを出力し、backup ref と状態ファイルを削除
#
# status: done / conflict / stopped (コンフリクト以外の停止) / blocked (continue の検査で止めた)
# exit: 0=正常 (status を見て分岐) / 1=エラー
set -uo pipefail
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"
require_tools

CMD="${1:-}"
STATE_DIR=$(state_dir)
STATE=$(state_file)
LOG="$STATE_DIR/last-output.txt"

state_get() { jq -r ".$1" "$STATE"; }

emit_status() {
  local blocked="${1:-}"
  if [ -n "$blocked" ]; then
    jq -n --arg reason "$blocked" --argjson unmerged "$(git diff --name-only --diff-filter=U | to_json_array)" \
      '{status: "blocked", reason: $reason, unmerged: $unmerged}'
    return
  fi
  if ! in_rebase; then
    jq -n --arg head "$(git rev-parse HEAD)" '{status: "done", head: $head}'
    return
  fi
  local rd cur unmerged status
  rd=$(rebase_dir)
  cur=$(git rev-parse --quiet --verify REBASE_HEAD 2>/dev/null || true)
  unmerged=$(git diff --name-only --diff-filter=U | to_json_array)
  status=conflict
  [ "$unmerged" = "[]" ] && status=stopped
  jq -n --arg status "$status" --arg cur "$cur" \
    --arg subject "$([ -n "$cur" ] && git log -1 --format=%s "$cur")" \
    --arg progress "$(cat "$rd/msgnum" 2>/dev/null)/$(cat "$rd/end" 2>/dev/null)" \
    --argjson unmerged "$unmerged" \
    --arg output "$(tail -n 20 "$LOG" 2>/dev/null)" \
    '{status: $status, commit: $cur, subject: $subject, progress: $progress,
      unmerged: $unmerged, git_output: $output}'
}

write_state() {
  local branch="$1" base="$2" orig="$3" backup="refs/rebase-with-context/backup/$1"
  mkdir -p "$STATE_DIR"
  git update-ref "$backup" "$orig"
  jq -n --arg branch "$branch" --arg base "$base" --arg orig "$orig" --arg backup "$backup" \
    --arg onto "$(git rev-parse "$base^{commit}" 2>/dev/null)" \
    '{branch: $branch, base: $base, orig_head: $orig, backup_ref: $backup, onto: $onto}' > "$STATE"
  : > "$STATE_DIR/decisions.jsonl"
}

case "$CMD" in
  start)
    BASE="${2:-}"; [ -n "$BASE" ] || die "usage: rebase-step.sh start <base>"
    in_rebase && die "既に rebase 中です。adopt で引き継いでください。"
    [ -f "$STATE" ] && die "前回の状態ファイルが残っています。abort で片付けてください。"
    BRANCH=$(git symbolic-ref --quiet --short HEAD) || die "detached HEAD では実行できません。"
    write_state "$BRANCH" "$BASE" "$(git rev-parse HEAD)"
    if ! git_rebase --empty=drop "$BASE" > "$LOG" 2>&1 && ! in_rebase; then
      cat "$LOG" >&2
      git update-ref -d "$(state_get backup_ref)"; rm -rf "$STATE_DIR"
      die "rebase を開始できませんでした。"
    fi
    emit_status
    ;;
  adopt)
    in_rebase || die "rebase 中ではありません。"
    if [ ! -f "$STATE" ]; then
      rd=$(rebase_dir)
      write_state "$(rebase_branch)" "$(cat "$rd/onto")" "$(cat "$rd/orig-head")"
    fi
    emit_status
    ;;
  continue)
    in_rebase || die "rebase 中ではありません。"
    if [ -n "$(git diff --name-only --diff-filter=U)" ]; then
      emit_status "未解消 (git add されていない) のファイルがあります"; exit 0
    fi
    markers=$(git diff --cached --check 2>&1 | grep -B1 'leftover conflict marker' || true)
    if [ -n "$markers" ]; then
      emit_status "コンフリクトマーカーが残っています: $markers"; exit 0
    fi
    git_rebase --continue > "$LOG" 2>&1
    emit_status
    ;;
  skip)
    in_rebase || die "rebase 中ではありません。"
    git_rebase --skip > "$LOG" 2>&1
    emit_status
    ;;
  status)
    emit_status
    ;;
  abort)
    in_rebase && git_rebase --abort
    backup=""
    [ -f "$STATE" ] && backup=$(state_get backup_ref)
    rm -rf "$STATE_DIR"
    jq -n --arg backup "$backup" --arg head "$(git rev-parse HEAD)" \
      '{status: "aborted", head: $head, backup_ref: (if $backup == "" then null else $backup end),
        restore: (if $backup == "" then null else "git reset --hard \($backup)" end)}'
    ;;
  finish)
    in_rebase && die "rebase がまだ完了していません。"
    [ -f "$STATE" ] || die "状態ファイルがありません ($STATE)。"
    orig=$(state_get orig_head); base=$(state_get base); backup=$(state_get backup_ref)
    mb=$(git merge-base "$orig" "$base")
    # rebase は author 日時と件名を保つので、それで対応先の無い (取り込み済み/空で落ちた) コミットを探す。
    # range-diff は解消で diff が変わったコミットを別物と判定するため使わない
    dropped=$(awk -F'\t' 'NR == FNR { kept[$1 FS $2] = 1; next } !kept[$1 FS $2] { print $3 " " $2 }' \
      <(git log --format='%at%x09%s' "$base..HEAD") \
      <(git log --reverse --format='%at%x09%s%x09%h' "$mb..$orig") | to_json_array)
    jq -n --arg branch "$(state_get branch)" --arg base "$base" --arg orig "$orig" \
      --arg head "$(git rev-parse HEAD)" \
      --argjson decisions "$(jq -s . "$STATE_DIR/decisions.jsonl" 2>/dev/null || echo '[]')" \
      --argjson dropped "$dropped" \
      '{status: "finished", branch: $branch, base: $base, orig_head: $orig, head: $head,
        decisions: $decisions, dropped_commits: $dropped,
        restore: "git reset --hard \($orig)"}'
    git update-ref -d "$backup"
    rm -rf "$STATE_DIR"
    ;;
  *)
    die "usage: rebase-step.sh <start <base> | adopt | continue | skip | status | abort | finish>"
    ;;
esac
