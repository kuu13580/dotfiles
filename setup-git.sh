#!/bin/bash
# Git共通設定スクリプト
# user.name / user.email は手動で設定してください:
#   git config --global user.name "your-name"
#   git config --global user.email "your-email"

set -e

echo "🔧 Git設定を適用中..."

# 基本設定
git config --global core.editor "code --wait"
git config --global init.defaultBranch main
git config --global rerere.enabled true
git config --global submodule.recurse true

# エイリアス
git config --global alias.bclean '!f() { \
  my_name="$(git config user.name)"; \
  current_branch="$(git symbolic-ref --short HEAD)"; \
  branches_with_authors=$(git branch --format="%(refname:short) %(authorname)" | grep -v -E "^(${current_branch}|main|master|develop) "); \
  echo "$branches_with_authors" | grep " ${my_name}$" | awk "{print \$1}" | xargs -r git branch -d 2>/dev/null; \
  echo "$branches_with_authors" | grep -v " ${my_name}$" | awk "{print \$1}" | xargs -r git branch -D; \
}; f'

git config --global alias.squash '!f() { git fetch origin && git rebase -i $1 --autosquash; }; f'

echo "✅ Git設定を適用しました"
