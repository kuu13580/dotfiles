#!/bin/bash

# dotfilesセットアップスクリプト
# Usage: ./install.sh

set -e

# apt install時の対話プロンプト(tzdata等)を抑制
export DEBIAN_FRONTEND=noninteractive
export TZ=Asia/Tokyo

echo "🚀 dotfilesセットアップを開始します..."

# 現在のディレクトリを取得
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# nanoのインストールとデフォルトエディタに設定
echo "📦 nanoをインストール中..."
if ! command -v nano &> /dev/null; then
    sudo -E apt update
    sudo -E apt install -y nano
    echo "✅ nanoをインストールしました"
else
    echo "✅ nanoは既にインストール済みです"
fi
echo "SELECTED_EDITOR=\"/bin/nano\"" > "$HOME/.selected_editor"
echo "✅ nanoをデフォルトエディタに設定しました"

# zshのインストール
echo "📦 zshをインストール中..."
if ! command -v zsh &> /dev/null; then
    sudo -E apt update
    sudo -E apt install -y zsh
    echo "✅ zshをインストールしました"
else
    echo "✅ zshは既にインストール済みです"
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
git clone https://github.com/MichaelAquilina/zsh-you-should-use.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
echo "✅ zshプラグインをインストールしました"

# GitHub CLIのインストール
echo "📦 GitHub CLIをインストール中..."
if ! command -v gh &> /dev/null; then
    (type -p wget >/dev/null || (sudo apt update && sudo apt install wget -y)) \
	&& sudo mkdir -p -m 755 /etc/apt/keyrings \
	&& out=$(mktemp) && wget -nv -O$out https://cli.github.com/packages/githubcli-archive-keyring.gpg \
	&& cat $out | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
	&& sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
	&& sudo mkdir -p -m 755 /etc/apt/sources.list.d \
	&& echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
	&& sudo apt update \
	&& sudo apt install gh -y
    echo "✅ GitHub CLIをインストールしました"
else
    echo "✅ GitHub CLIは既にインストール済みです"
fi

# 開発ツール・フォント等のインストール
echo "📦 開発ツール・フォントをインストール中..."
sudo -E apt install -y \
    jq \
    fzf \
    ffmpeg \
    gitk \
    stun-client \
    unzip zip
echo "✅ 開発ツール・フォントをインストールしました"

# fnmのインストール
echo "📦 fnm (Fast Node Manager) をインストール中..."
if ! command -v fnm &> /dev/null; then
    curl -fsSL https://fnm.vercel.app/install | bash
    echo "✅ fnmをインストールしました"
else
    echo "✅ fnmは既にインストール済みです"
fi

# fnmのPATHを通してNode.js LTSとpnpmをインストール
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env)"
echo "📦 Node.js LTS をインストール中..."
fnm install --lts
fnm default lts-latest
echo "✅ Node.js $(node --version) をインストールしました"

echo "📦 pnpm をインストール中..."
npm install -g pnpm
echo "✅ pnpm $(pnpm --version) をインストールしました"

# 設定ファイルのシンボリックリンク作成
echo "🔗 設定ファイルをリンク中..."

# .zshrcのバックアップ
if [ -f "$HOME/.zshrc" ] && [ ! -L "$HOME/.zshrc" ]; then
    cp "$HOME/.zshrc" "$HOME/.zshrc.backup.$(date +%Y%m%d_%H%M%S)"
    echo "📋 既存の.zshrcをバックアップしました"
fi

# .zshrcのシンボリックリンク作成
ln -sf "$DOTFILES_DIR/dotfiles/.zshrc" "$HOME/.zshrc"
echo "✅ .zshrcをリンクしました"

# .p10k.zshのバックアップとシンボリックリンク作成
if [ -f "$HOME/.p10k.zsh" ] && [ ! -L "$HOME/.p10k.zsh" ]; then
    cp "$HOME/.p10k.zsh" "$HOME/.p10k.zsh.backup.$(date +%Y%m%d_%H%M%S)"
    echo "📋 既存の.p10k.zshをバックアップしました"
fi
if [ -f "$DOTFILES_DIR/dotfiles/.p10k.zsh" ]; then
    ln -sf "$DOTFILES_DIR/dotfiles/.p10k.zsh" "$HOME/.p10k.zsh"
    echo "✅ .p10k.zshをリンクしました"
fi

# Git設定の適用
source "$DOTFILES_DIR/setup-git.sh"

# Dockerのインストール
if command -v docker &> /dev/null; then
    echo "✅ Dockerは既にインストール済みです"
else
    echo "🐳 Dockerをインストール中..."

    # Add Docker's official GPG key:
    sudo -E apt update
    sudo -E apt install -y ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo -E apt update

    # install Latest
    sudo -E apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo usermod -aG docker $(whoami)
    echo "✅ Dockerをインストールしました (dockerグループへの追加はログアウト後に反映)"
fi

echo ""
echo "🎉 dotfilesセットアップが完了しました！"
echo ""
echo "📝 次のステップ:"
echo "1. フォントのインストール:"
echo "   - PlemolJP (エディタ推奨): https://github.com/yuru7/PlemolJP"
echo "   - MesloLGS NF (ターミナル必須): https://github.com/romkatv/powerlevel10k?tab=readme-ov-file#fonts"
echo "2. VSCodeの設定に追加:"
echo '   "editor.fontFamily": "PlemolJP Console NF"'
echo '   "terminal.integrated.fontFamily": "MesloLGS NF"'
echo "3. ターミナルを再起動するか 'source ~/.zshrc' を実行"
echo ""
echo "🔄 変更を適用するには新しいシェルセッションを開始してください"
