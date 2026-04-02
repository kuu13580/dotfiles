# dotfiles

個人用のシェル設定・開発環境の設定ファイル管理リポジトリ

## セットアップ

```bash
git clone <repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
```

## 管理方針

### 1. Symlink Only

`install.sh`は`cp`ではなく`ln -sf`でシンボリックリンクを作成する。
`$HOME`側の変更が即座にリポジトリに反映され、Single Source of Truthを維持する。

### 2. 環境固有設定の分離 (Local Files)

OS固有の設定や秘密情報は`.zshrc`本体に記述せず、`~/.local.zshrc`に分離する。
`.zshrc`末尾で自動的にsourceされる。`.local.*`は`.gitignore`に含まれる。

```zsh
# 例: ~/.local.zshrc
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
```

### 3. 設定の肥大化防止

- `typeset -U path PATH` でPATHの重複を防止
- `[[ -f ... ]] && source ...` でオプショナルなプラグインの存在チェック
- `(( $+commands[cmd] ))` で未インストールコマンドの設定をガード

## 検証環境 (Docker)

`install.sh`の動作をクリーンなUbuntu 24.04環境で検証できる。

### VSCode Dev Containers (推奨)

1. VSCodeで「Dev Containers」拡張機能をインストール
2. このリポジトリを開き、`Ctrl+Shift+P` → `Dev Containers: Reopen in Container`
3. コンテナ起動時に`install.sh`が自動実行される

### CLIで検証

```bash
# ビルド
docker build -t dotfiles-test .

# install.sh実行 + symlink確認
docker run --rm -v "$(pwd):/home/testuser/dotfiles" dotfiles-test \
  bash -c "cd ~/dotfiles && bash install.sh && ls -la ~/.zshrc ~/.p10k.zsh"

# zshを対話的に試す
docker run --rm -it -v "$(pwd):/home/testuser/dotfiles" dotfiles-test \
  bash -c "cd ~/dotfiles && bash install.sh && zsh"
```

## フォント設定

### エディタフォント (推奨): PlemolJP

プログラミング向け日英対応フォント。[PlemolJP](https://github.com/yuru7/PlemolJP)のReleasesからインストールし、VSCodeの設定に追加:

```json
"editor.fontFamily": "PlemolJP Console NF"
```

### ターミナルフォント: MesloLGS NF

Powerlevel10kの表示に必要。[こちら](https://github.com/romkatv/powerlevel10k?tab=readme-ov-file#fonts)から4つのttfファイルをダウンロードしてインストールし、VSCodeの設定に追加:

```json
"terminal.integrated.fontFamily": "MesloLGS NF"
```

## ファイル一覧

| ファイル             | 説明                                                 |
| -------------------- | ---------------------------------------------------- |
| `dotfiles/.zshrc`    | Zsh設定 (oh-my-zsh + powerlevel10k)                  |
| `dotfiles/.p10k.zsh` | Powerlevel10kプロンプト設定                          |
| `.wslconfig`         | WSL2設定 (`C:\Users\<user>\.wslconfig` に手動コピー) |
| `config`             | SSH configテンプレート (手動コピー)                  |
| `custom_keymap.txt`  | Google日本語入力カスタムキーマップ                   |
| `extensions.json`    | VSCode推奨拡張機能                                   |
| `setup-git.sh`       | Git共通設定スクリプト (user設定除く)                 |
| `install.sh`         | セットアップスクリプト                               |
