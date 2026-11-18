#!/usr/bin/env bash
# Stop フック: 作業や調べもののあったターンで記録が古いまま終わろうとしたら、1回だけ追記を促す。
#
# 判定はコマンドだけで行う (LLM 判定は毎ターンのコストが読めないため使わない)。
# 材料は transcript の「最後のユーザー発言以降のツール使用」と CONTEXT.md の mtime。
set -uo pipefail

# これ以上のツール使用は、編集や調べものが無くても記録に値する作業とみなす
MIN_TOOL_USES=5

INPUT=$(cat)
ACTIVE=$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null) || ACTIVE=false
[ "$ACTIVE" = "true" ] && exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || TRANSCRIPT=""
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || CWD=""
[ -f "$TRANSCRIPT" ] || exit 0

[ -n "$CWD" ] && cd "$CWD" 2>/dev/null

KEY=$("${CLAUDE_PLUGIN_ROOT}/scripts/resolve-key.sh") || exit 0
RECORD="$HOME/.claude/contexts/$KEY/CONTEXT.md"

if command -v tac >/dev/null 2>&1; then reverse() { tac "$1"; }; else reverse() { tail -r "$1"; }; fi

# transcript は数百MBになるため末尾から読み、最後のユーザー発言で打ち切る。
# 出力は「該当した理由 (「、」区切り)<TAB>該当したツール使用のうち最新の epoch 秒」。何も該当しなければ無出力
RESULT=$(reverse "$TRANSCRIPT" | jq -nRr --arg ctx "$HOME/.claude/contexts/" --argjson min "$MIN_TOOL_USES" '
  def is_prompt:
    .type == "user" and (.isMeta | not) and (.isSidechain | not)
    and ((.message.content | type) == "string"
      or ((.message.content | type) == "array" and all(.message.content[]; .type != "tool_result")));
  def epoch: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
  [ label $done
    | inputs | fromjson? // empty
    | if is_prompt then break $done
      elif .type == "assistant" and (.isSidechain | not) then
        .timestamp as $ts | .message.content[]? | select(.type == "tool_use") | {id, name, input, ts: (($ts // "1970-01-01T00:00:00Z") | epoch)}
      else empty end ]
  | unique_by(.id)
  # 記録そのものの読み書きと、成果の残らない管理用ツールは数えない
  | map(select(((.input.file_path // .input.notebook_path // "") | startswith($ctx)) | not))
  | map(select(.name | test("^(ToolSearch|TodoWrite|Task(Create|Update|List|Get))$") | not))
  | (map(select((.name | test("^(Edit|MultiEdit|Write|NotebookEdit)$"))
        or (.name == "Bash" and ((.input.command // "") | test("\\bgit\\b[^;&|]*\\bcommit\\b")))))) as $edits
  | (map(select(.name | test("^(WebSearch|WebFetch|Agent|Task|mcp__.*)$")))) as $research
  | [ (if ($edits | length) > 0 then {r: "ファイル編集・コミット", t: ($edits | map(.ts) | max)} else empty end),
      (if ($research | length) > 0 then {r: "調べもの (\($research | map(.name | sub("^mcp__.*"; "MCP")) | unique | join("・")))", t: ($research | map(.ts) | max)} else empty end),
      (if length >= $min then {r: "ツール使用 \(length) 回", t: (map(.ts) | max)} else empty end) ]
  | select(length > 0)
  | "\(map(.r) | join("、"))\t\(map(.t) | max)"
')
[ -n "$RESULT" ] || exit 0

REASONS=${RESULT%%$'\t'*}
LAST_TS=${RESULT##*$'\t'}
MTIME=0
[ -f "$RECORD" ] && MTIME=$(date -r "$RECORD" +%s)
[ "$MTIME" -ge "$LAST_TS" ] && exit 0

NEW=""
[ -f "$RECORD" ] || NEW=" (未作成。冒頭にタスクの一行説明を置く)"

# 発火のたびに文脈へ入るため短く保つ。スキルを呼ばせると SKILL.md 全文 (約 9KB) が毎回読み込まれるので、基準を直接渡す
REASON="prepare-context: このターンの作業 (${REASONS}) が ${RECORD}${NEW} に未反映。セッションが消えても続きから入れるよう、スキルは呼ばず直接追記してから終える。
- 残す: 確認した事実と出典 (パス:行番号・URL)、決定と理由、再利用できる検証手順、未決着なら現在地
- 残さない: コマンドの順番、生ログ
- 古くなった記述は書き換え、置き換えた決定は旧版を理由ごと CONTEXT.archive.md へ
残す事実が無ければ「記録の更新なし」とだけ述べて終える。"

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
