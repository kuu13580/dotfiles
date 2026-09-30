#!/usr/bin/env bash
# 明示キーを現在の worktree に設定し、解決後の "<repo>/<key>" を stdout に出す。
#
# キーは設定した worktree の ID と対で保存する。git worktree add は実行元の config.worktree を
# 新 worktree へ複製するため、ID が一致しないキーを resolve-key.sh が複製として無視できるようにする。
set -euo pipefail

if [ $# -ne 1 ] || [ -z "$1" ]; then
  echo "usage: set-key.sh <key>" >&2
  exit 1
fi

git rev-parse --git-dir >/dev/null

# 無効のまま --worktree に書くと全 worktree 共有の .git/config に入る
[ "$(git config --get extensions.worktreeConfig)" = "true" ] || git config extensions.worktreeConfig true

# main worktree は "."、linked worktree は "worktrees/<id>"
owner=$(git rev-parse --absolute-git-dir)
owner=${owner#"$(git rev-parse --path-format=absolute --git-common-dir)"}; owner=${owner#/}; owner=${owner:-.}
git config --worktree prepare-context.key "$1"
git config --worktree prepare-context.keyOwner "$owner"

"$(dirname "$0")/resolve-key.sh"
