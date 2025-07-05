#!/bin/bash

# dotfilesセットアップスクリプト
# Usage: ./install.sh

set -e

echo "🚀 dotfilesセットアップを開始します..."

# 現在のディレクトリを取得
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# zshのインストール
echo "📦 zshをインストール中..."
if ! command -v zsh &> /dev/null; then
    sudo apt update
    sudo apt install -y zsh
    echo "✅ zshをインストールしました"
else
    echo "✅ zshは既にインストール済みです"
fi

# デフォルトシェルをzshに変更
echo "🔧 デフォルトシェルをzshに変更中..."
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s $(which zsh)
    echo "✅ デフォルトシェルをzshに変更しました"
else
    echo "✅ 既にzshがデフォルトシェルです"
fi

# Oh My Zshのインストール
echo "🎨 Oh My Zshをインストール中..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    	sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    echo "✅ Oh My Zshをインストールしました"
else
    echo "✅ Oh My Zshは既にインストール済みです"
fi

# Powerlevel10kテーマのインストール
echo "⚡ Powerlevel10kテーマをインストール中..."
if [ ! -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k" ]; then
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    echo "✅ Powerlevel10kテーマをインストールしました"
else
    echo "✅ Powerlevel10kテーマは既にインストール済みです"
fi

# zshプラグインのインストール
echo "🔌 zshプラグインをインストール中..."
sudo apt update
sudo apt install -y zsh-autosuggestions zsh-syntax-highlighting
echo "✅ zshプラグインをインストールしました"

# 設定ファイルのシンボリックリンク作成
echo "🔗 設定ファイルをリンク中..."

# .zshrcのバックアップ
if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    echo "📋 既存の.zshrcをバックアップしました"
fi

# .zshのコピー
cp "$DOTFILES_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
echo "✅ .zshrcをリンクしました"

# .p10k.zshのコピー
if [ -f "$DOTFILES_DIR/dotfiles/.p10k.zsh" ]; then
    cp "$DOTFILES_DIR/dotfiles/.p10k.zsh" "$HOME/.p10k.zsh"
    echo "✅ .p10k.zshをリンクしました"
fi

echo ""
echo "🎉 dotfilesセットアップが完了しました！"
echo ""
echo "📝 次のステップ:"
echo "1. ターミナルを再起動するか 'source ~/.zshrc' を実行"
echo "2. Powerlevel10k設定ウィザードが表示される場合は指示に従って設定"
echo "3. フォントが正しく表示されない場合は、Nerd Fontをインストール"
echo "   https://github.com/romkatv/powerlevel10k?tab=readme-ov-file#fonts"
echo ""
echo "🔄 変更を適用するには新しいシェルセッションを開始してください"
