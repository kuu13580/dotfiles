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

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
            echo "✅ $(basename "$dst") は既にリンク済みです"
            return 0
        fi
        local backup="${dst}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -P "$dst" "$backup" 2>/dev/null || cp "$dst" "$backup"
        echo "📋 既存の $(basename "$dst") をバックアップしました (${backup##*/})"
    fi
    ln -sf "$src" "$dst"
    echo "✅ $(basename "$dst") をリンクしました"
}

# 配置先が ~/dotfiles 以外（devcontainer等）の場合はパスを適応
if [ "$DOTFILES_DIR" != "$HOME/dotfiles" ]; then
    sed "s|~/dotfiles|$DOTFILES_DIR|g" "$DOTFILES_DIR/antigravity/skills.json" > "$GEMINI_CONFIG_DIR/skills.json"
    sed "s|~/dotfiles|$DOTFILES_DIR|g" "$DOTFILES_DIR/antigravity/hooks.json" > "$GEMINI_CONFIG_DIR/hooks.json"
    echo "✅ skills.json を配置先に合わせて生成しました"
    echo "✅ hooks.json を配置先に合わせて生成しました"
    link_config "$DOTFILES_DIR/antigravity/AGENTS.md" "$GEMINI_CONFIG_DIR/AGENTS.md"
else
    link_config "$DOTFILES_DIR/antigravity/AGENTS.md" "$GEMINI_CONFIG_DIR/AGENTS.md"
    link_config "$DOTFILES_DIR/antigravity/skills.json" "$GEMINI_CONFIG_DIR/skills.json"
    link_config "$DOTFILES_DIR/antigravity/hooks.json" "$GEMINI_CONFIG_DIR/hooks.json"
fi

# 各スキルを ~/.gemini/config/skills/ へ直接リンク (UI・エージェント検出を確実にする)
mkdir -p "$GEMINI_CONFIG_DIR/skills"
for skill_dir in "$DOTFILES_DIR"/plugins/*/skills/*; do
    if [ -d "$skill_dir" ] && [ -f "$skill_dir/SKILL.md" ]; then
        skill_name="$(basename "$skill_dir")"
        link_config "$skill_dir" "$GEMINI_CONFIG_DIR/skills/$skill_name"
    fi
done

echo "🎉 Antigravity 設定のリンクが完了しました"
