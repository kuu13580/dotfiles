#!/usr/bin/env bash
# post-pending-review.sh
# pr-review 用: 行コメントを未 submit の pending review として投稿する (submit はしない)
# Usage:
#   bash post-pending-review.sh <PR番号|PR URL> <comments.json> [--dry-run] [--append <review_id>]
#
# --append: 既存の pending review の ID が <review_id> と一致するときだけ、そこへ追記する。
#           この実行系で作った review (前回出力の review_id) にだけ使い、手書きのドラフトは保護する。
#
# comments.json は以下の配列:
#   [{"path": "src/a.ts", "line": 42, "body": "..."},
#    {"path": "src/b.ts", "line": 20, "start_line": 18, "body": "..."}]
#
# 行が PR の diff に含まれていないと GitHub は 422 を返し、1 件でも不正だと全件が落ちる。
# そのため投稿前に diff と突き合わせ、コメントできない行は除外して結果に載せる。
#
# Exit codes: 0 = 投稿成功 / 1 = エラー / 5 = 投稿可能なコメントが 0 件 / 6 = 既存 pending review あり (--append 不一致含む)

set -euo pipefail

target="${1:-}"
comments_file="${2:-}"
dry_run=false
append_id=""
shift 2 2>/dev/null || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=true; shift ;;
    --append) append_id="${2:-}"; shift 2 ;;
    *) echo "不明なオプション: $1" >&2; exit 1 ;;
  esac
done

[[ -z "$target" || -z "$comments_file" ]] && {
  echo "Usage: bash post-pending-review.sh <PR番号|PR URL> <comments.json> [--dry-run] [--append <review_id>]" >&2; exit 1;
}
[[ -f "$comments_file" ]] || { echo "コメントファイルが見つかりません: $comments_file" >&2; exit 1; }

for cmd in gh jq python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "$cmd が見つかりません。" >&2; exit 1; }
done

if [[ "$target" =~ ^[0-9]+$ ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  number="$target"
elif [[ "$target" =~ ^https?://[^/]+/([^/]+)/([^/]+)/pull/([0-9]+) ]]; then
  repo="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  number="${BASH_REMATCH[3]}"
else
  echo "引数の形式が不正です: '$target'" >&2; exit 1
fi
owner="${repo%%/*}"; name="${repo##*/}"

# --- 既存 pending review の確認 (GitHub 仕様上 1 ユーザー 1 PR につき 1 つだけ) ---
pending=$(gh api graphql -f owner="$owner" -f name="$name" -F number="$number" -f query='
query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){
  pullRequest(number:$number){ headRefOid reviews(states: PENDING, first:1){ nodes{ id databaseId url comments(first:1){ totalCount } } } } } }')
head_oid=$(echo "$pending" | jq -r '.data.repository.pullRequest.headRefOid')
pending_node=$(echo "$pending" | jq -r '.data.repository.pullRequest.reviews.nodes[0].id // empty')
pending_db_id=$(echo "$pending" | jq -r '.data.repository.pullRequest.reviews.nodes[0].databaseId // empty')
append=false
if [[ -n "$pending_node" && -n "$append_id" && "$pending_db_id" == "$append_id" ]]; then
  append=true
elif [[ -n "$pending_node" ]]; then
  if [[ -n "$append_id" ]]; then
    echo "既存の pending review ($pending_db_id) が --append の指定 ($append_id) と一致しません。手書きのドラフトの可能性があるため追記しません。" >&2
  else
    echo "PR #$number には既に未 submit の pending review があります。GitHub 上で破棄 (Discard review) してから再実行してください。" >&2
  fi
  echo "$pending" | jq -r '.data.repository.pullRequest.reviews.nodes[0].url' >&2
  exit 6
fi

# --- diff と突き合わせて投稿可能な行を判定 ---
diff_file=$(mktemp)
trap 'rm -f "$diff_file"' EXIT
gh pr diff "$number" --repo "$repo" > "$diff_file"

split=$(python3 - "$diff_file" "$comments_file" <<'PY'
import codecs, json, re, sys

diff_path, comments_path = sys.argv[1], sys.argv[2]

# 新ファイル側でコメント可能な行 = hunk 内の追加行と文脈行
commentable = {}
path = None
new_line = 0
with open(diff_path, encoding="utf-8", errors="replace") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if line.startswith("+++ "):
            p = line[4:]
            # 非 ASCII のパスは git が "b/\346\227..." のように引用符と 8 進エスケープで出す
            if p.startswith('"') and p.endswith('"'):
                p = codecs.escape_decode(p[1:-1].encode())[0].decode("utf-8", errors="replace")
            path = None if p == "/dev/null" else re.sub(r"^b/", "", p)
            continue
        if line.startswith("@@"):
            m = re.search(r"\+(\d+)", line)
            new_line = int(m.group(1)) if m else 0
            continue
        if path is None:
            continue
        if line.startswith("+"):
            commentable.setdefault(path, set()).add(new_line); new_line += 1
        elif line.startswith("-") or line.startswith("\\"):
            pass
        elif line.startswith(" "):
            commentable.setdefault(path, set()).add(new_line); new_line += 1

comments = json.load(open(comments_path, encoding="utf-8"))
valid, invalid = [], []
for c in comments:
    p, ln = c.get("path"), c.get("line")
    body = (c.get("body") or "").strip()
    if not p or not isinstance(ln, int) or not body:
        invalid.append({**c, "reason": "path / line / body のいずれかが欠けています"}); continue
    lines = commentable.get(p)
    if lines is None:
        invalid.append({"path": p, "line": ln, "body": body, "reason": "この PR の diff に含まれないファイルです"}); continue
    if ln not in lines:
        near = sorted(lines, key=lambda x: abs(x - ln))[:3]
        invalid.append({"path": p, "line": ln, "body": body,
                        "reason": f"diff に含まれない行です (近い行: {near})"}); continue
    item = {"path": p, "line": ln, "side": "RIGHT", "body": body}
    sl = c.get("start_line")
    if isinstance(sl, int) and sl < ln and sl in lines:
        item["start_line"] = sl
        item["start_side"] = "RIGHT"
    valid.append(item)

print(json.dumps({"valid": valid, "invalid": invalid}, ensure_ascii=False))
PY
)

valid=$(echo "$split" | jq '.valid')
invalid=$(echo "$split" | jq '.invalid')
valid_count=$(echo "$valid" | jq 'length')

if [[ "$dry_run" == "true" ]]; then
  jq -n --argjson valid "$valid" --argjson invalid "$invalid" --arg oid "$head_oid" \
    '{dry_run: true, commit_id: $oid, would_post: ($valid | length), valid: $valid, invalid: $invalid}'
  exit 0
fi

if [[ "$valid_count" == "0" ]]; then
  echo "投稿可能なコメントがありません。" >&2
  echo "$invalid" | jq -r '.[] | "  - \(.path):\(.line) — \(.reason)"' >&2
  exit 5
fi

if [[ "$append" == "true" ]]; then
  posted=0
  while IFS= read -r c; do
    if err=$(gh api graphql -f rid="$pending_node" \
        -f path="$(echo "$c" | jq -r .path)" -F line="$(echo "$c" | jq .line)" \
        -f body="$(echo "$c" | jq -r .body)" \
        $(echo "$c" | jq -r 'if .start_line then "-F startLine=\(.start_line) -f startSide=RIGHT" else "" end') \
        -f query='
      mutation($rid: ID!, $path: String!, $line: Int!, $body: String!, $startLine: Int, $startSide: DiffSide) {
        addPullRequestReviewThread(input: {pullRequestReviewId: $rid, path: $path, line: $line, side: RIGHT,
          startLine: $startLine, startSide: $startSide, body: $body}) { thread { id } }
      }' 2>&1); then
      posted=$((posted + 1))
    else
      invalid=$(echo "$invalid" | jq --argjson c "$c" --arg e "$err" '. + [$c + {reason: "追記に失敗: \($e)"}]')
    fi
  done < <(echo "$valid" | jq -c '.[]')
  jq -n --argjson invalid "$invalid" --arg repo "$repo" --argjson number "$number" \
    --argjson posted "$posted" --argjson rid "$pending_db_id" \
    '{posted: $posted, review_id: $rid, state: "PENDING", appended: true,
      url: "https://github.com/\($repo)/pull/\($number)/files", invalid: $invalid}'
  exit 0
fi

payload=$(jq -n --arg oid "$head_oid" --argjson comments "$valid" '{commit_id: $oid, comments: $comments}')
res=$(echo "$payload" | gh api --method POST "/repos/$owner/$name/pulls/$number/reviews" --input - 2>&1) || {
  echo "pending review の作成に失敗しました: $res" >&2
  exit 1
}

jq -n --argjson res "$res" --argjson invalid "$invalid" --argjson valid "$valid" \
  --arg repo "$repo" --argjson number "$number" \
  '{posted: ($valid | length), review_id: $res.id, state: $res.state,
    url: "https://github.com/\($repo)/pull/\($number)/files",
    invalid: $invalid}'
