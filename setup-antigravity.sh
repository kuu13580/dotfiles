#!/bin/bash
# Antigravity 設定のシンボリックリンク作成スクリプト
# Usage: ./setup-antigravity.sh

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_CONFIG_DIR="$HOME/.gemini/config"

echo "🔗 Antigravity 設定をリンク中..."

mkdir -p "$GEMINI_CONFIG_DIR"
chmod +x "$DOTFILES_DIR/antigravity/scripts/"*.sh 2>/dev/null || true

link_config() {
    local src="$1"
    local dst="$2"

    if [ -f "$dst" ] && [ ! -L "$dst" ]; then
        cp "$dst" "${dst}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "📋 既存の $(basename "$dst") をバックアップしました"
    fi
    ln -sf "$src" "$dst"
    echo "✅ $(basename "$dst") をリンクしました"
}

link_config "$DOTFILES_DIR/antigravity/AGENTS.md" "$GEMINI_CONFIG_DIR/AGENTS.md"
link_config "$DOTFILES_DIR/antigravity/skills.json" "$GEMINI_CONFIG_DIR/skills.json"
link_config "$DOTFILES_DIR/antigravity/hooks.json" "$GEMINI_CONFIG_DIR/hooks.json"

echo "🎉 Antigravity 設定のリンクが完了しました"
