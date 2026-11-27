#!/usr/bin/env bash
# fetch-pr-bodies.sh
# review-kit 用: PR のレビュー本文と PR コメントを全件取り、作者が返信済みかを付けて JSON で出す (fetch-pr-feedback.sh と detect-state.sh が共有)
# Usage: bash fetch-pr-bodies.sh <owner/repo> <PR番号> <PR作成者> [<除外する login>]
# Exit codes: 0 = 成功 / 1 = エラー

set -euo pipefail

repo="${1:?owner/repo}"; number="${2:?PR番号}"; author="${3:?PR作成者}"; me="${4:-$author}"

# 返信 1 件ごとに本文が空のレビューが作られ件数がすぐ膨らむため、GraphQL の件数上限ではなく REST で全ページ取る
# 本文は長い PR で 128KiB を超え、--argjson で渡すと argument list too long になるのでファイル経由にする
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
gh api --paginate "repos/$repo/pulls/$number/reviews" \
  --jq '.[] | {login: .user.login, type: .user.type, state, body, at: .submitted_at, url: .html_url}' >"$tmp/reviews"
gh api --paginate "repos/$repo/issues/$number/comments" \
  --jq '.[] | {id, login: .user.login, type: .user.type, body, at: .created_at, url: .html_url}' >"$tmp/comments"

jq -n --slurpfile reviews "$tmp/reviews" --slurpfile comments "$tmp/comments" --arg author "$author" --arg me "$me" '
  def bot: .login == null or .type == "Bot" or (.login | test("\\[bot\\]$"));
  def others: select(.login != $me and .login != $author);
  # 作者の PR コメントに元の URL がそのまま含まれるものだけを返信とみなす (…-123 が …-1234 に一致しないよう直後の数字を弾く)
  ([$comments[] | select(.login == $author) | .body] | join("\n")) as $replies
  | def answered: .url as $u | any(($replies | split($u))[1:][]; test("^[0-9]") | not);
  {review_bodies: [$reviews[] | others | select((.body // "") != "")
     | {author: (.login // "ghost"), is_bot: bot, state, body, at, url, answered: answered}],
   pr_comments: [$comments[] | others
     | {id, author: (.login // "ghost"), is_bot: bot, body, at, url, answered: answered}]}'
