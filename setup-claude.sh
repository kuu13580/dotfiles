#!/bin/bash
# Claude Code ユーザー設定のマージスクリプト
# Usage: ./setup-claude.sh

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_FILE="$DOTFILES_DIR/claude/settings.base.json"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "🔗 Claude Code 設定をマージ中..."

mkdir -p "$HOME/.claude"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo '{}' > "$SETTINGS_FILE"
fi

# settings.json は Claude Code 自身も書き換えるため、symlink ではなくマージする
# base のキーを優先し、permissions.allow だけは既存ルールと和集合にする
TEMP_FILE=$(mktemp)
jq -s '
  .[0] as $cur | .[1] as $base
  | ($cur * $base)
  | .permissions.allow = ((($cur.permissions.allow // []) + ($base.permissions.allow // [])) | unique)
' "$SETTINGS_FILE" "$BASE_FILE" > "$TEMP_FILE"

if cmp -s "$TEMP_FILE" "$SETTINGS_FILE"; then
    rm "$TEMP_FILE"
    echo "✅ settings.json は既に最新です"
    exit 0
fi

if [ "$(jq -c . "$SETTINGS_FILE")" != "{}" ]; then
    backup="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$backup"
    echo "📋 既存の settings.json をバックアップしました (${backup##*/})"
fi
mv "$TEMP_FILE" "$SETTINGS_FILE"
chmod 600 "$SETTINGS_FILE"
echo "✅ settings.json にマージしました"
