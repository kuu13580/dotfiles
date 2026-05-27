# Powerlevel10k instant prompt (有効化する場合はコメントを外す)
# p10k configure を実行すると自動的に追加されます
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Prevent PATH duplication on re-sourcing
typeset -U path PATH

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="powerlevel10k/powerlevel10k"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(git zsh-autosuggestions you-should-use)

source $ZSH/oh-my-zsh.sh

# User configuration

# export MANPATH="/usr/local/man:$MANPATH"

# You may need to manually set your language environment
# export LANG=en_US.UTF-8

# Preferred editor for local and remote sessions
# if [[ -n $SSH_CONNECTION ]]; then
#   export EDITOR='vim'
# else
#   export EDITOR='nvim'
# fi

# Compilation flags
# export ARCHFLAGS="-arch $(uname -m)"

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

[[ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
[[ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# custom alias

alias python="python3"
alias pip="pip3"
alias gitlog="git log --oneline"
alias rebase='f(){ git fetch origin; git rebase origin/$1; git rebase -i origin/$1; unset -f f; }; f'

# custom functions

function vcw() {
    local dir="$HOME/.vscode-workspaces"

    if ! command -v fzf &> /dev/null; then
        echo "🤔 fzf が見つかりません。インストールしますか？ (y/n)"
        read -k 1 "opt"
        echo
        if [[ "$opt" == "y" || "$opt" == "Y" ]]; then
        echo "🚀 Installing fzf..."
        sudo apt update && sudo apt install -y fzf
        else
        echo "❌ 処理を中断しました。fzf が必要です。"
        return 1
        fi
    fi

    if [ ! -d "$dir" ]; then
        echo "📁 ディレクトリ $dir が見つかりません。"
        return 1
    fi

    local selected=$(ls "$dir"/*.code-workspace 2>/dev/null | xargs -n 1 basename | sed 's/\.code-workspace$//' | fzf --height 40% --reverse --border --prompt="Select Workspace > ")

    if [ -n "$selected" ]; then
        local editor=$(echo "code\nzed" | fzf --height 20% --reverse --border --prompt="Editor > ")
        [ -z "$editor" ] && return 0

        local ws="$dir/$selected.code-workspace"
        if [ "$editor" = "zed" ]; then
            local folder=$(jq -r '.folders[0].path' "$ws")
            zed "$folder"
        else
            code "$ws"
        fi
    fi
}

function delete-vcw() {
    local dir="$HOME/.vscode-workspaces"

    if ! command -v fzf &> /dev/null; then
        echo "🤔 fzf が見つかりません。インストールしますか？ (y/n)"
        read -k 1 "opt"
        echo
        if [[ "$opt" == "y" || "$opt" == "Y" ]]; then
        sudo apt update && sudo apt install -y fzf
        else
        return 1
        fi
    fi

    if [ ! -d "$dir" ]; then
        echo "📁 ディレクトリ $dir が見つかりません。"
        return 1
    fi

    local selected_names=($(ls "$dir"/*.code-workspace 2>/dev/null | xargs -n 1 basename | sed 's/\.code-workspace$//' | fzf --height 40% --reverse --multi --border --header "Tabで複数選択可 / Enterで確定" --prompt="Delete Workspace > "))

    if [ ${#selected_names[@]} -eq 0 ]; then
        return 0
    fi

    echo "⚠️  以下のワークスペースに関連するファイルを削除しますか？"
    for name in "${selected_names[@]}"; do
        echo "  - $name"
    done
    echo -n "本当に削除しますか？ (y/N): "
    read -k 1 "confirm"
    echo

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        for name in "${selected_names[@]}"; do
            local ws_file="$dir/$name.code-workspace"
            
            # JSONから folders[0].path を抽出
            local repo_dir=$(jq -r '.folders[0].path' "$ws_file" 2>/dev/null)

            # パスが取得できない、または空の場合はスキップ
            if [[ -z "$repo_dir" || "$repo_dir" == "null" ]]; then
                echo "⚠️  パスが見つからないため、ワークスペース設定のみ削除します: $name"
                rm -f "$ws_file" "$ws_file.backup" "$ws_file.lock"
                continue
            fi

            # Gitの未コミット変更チェック
            if [ -d "$repo_dir/.git" ]; then
                if ! git -C "$repo_dir" diff --quiet HEAD 2>/dev/null || \
                    [ -n "$(git -C "$repo_dir" ls-files --others --exclude-standard 2>/dev/null)" ]; then
                    echo "⛔ Skipped: $name (未コミットの変更があります)"
                    echo "   確認: git -C \"$repo_dir\" status"
                    continue
                fi
            fi

            # ファイルとディレクトリの削除
            rm -f "$ws_file" "$ws_file.backup" "$ws_file.lock"
            if [ -d "$repo_dir" ]; then
                rm -rf "$repo_dir"
                echo "✅ Deleted: $name (Path: $repo_dir)"
            else
                echo "✅ Deleted: $name (Workspace file only, path not found)"
            fi
        done
    else
        echo "🚫 キャンセルしました。"
    fi
}

function gh-needs-action() {
  GH_PAGER= gh pr list --assignee @me --state open --json number,title,url,reviews,reviewRequests,author --jq '
    .[] |
    . as $pr |
    $pr.author.login as $author |
    [$pr.reviewRequests[]?.login] as $rerequested |
    [
      $pr.reviews[] | select(
        .state == "COMMENTED" and
        .author.login != $author and
        .author.login != "copilot-pull-request-reviewer" and
        .author.login != "github-actions"
      ) | .author.login
    ] | unique as $commenters |
    [$commenters[] | select(. as $c | $rerequested | index($c) | not)] as $unaddressed |
    select(
      ([$pr.reviews[] | select(.state == "APPROVED")] | length) == 0 and
      ($unaddressed | length) > 0
    ) |
    "#\($pr.number) \($pr.title)\n  \($pr.url)"
  '
}

# wt-manager: load worktree helper functions from same directory as this .zshrc
# (works through symlinks; ${${(%):-%x}:A:h} = resolved absolute dir of this file)
[[ -f "${${(%):-%x}:A:h}/wt.zsh" ]] && source "${${(%):-%x}:A:h}/wt.zsh"

# Load machine-local overrides (not tracked in git)
[[ -f ~/.local.zshrc ]] && source ~/.local.zshrc

#path
path=(
  $HOME/.local/bin
  $HOME/.local/share/fnm(N-/)
  $path
)


#fnm
eval "$(fnm env --use-on-cd --shell zsh)"
