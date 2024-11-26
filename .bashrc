alias python="python3"
alias pip="pip3"
alias gitlog="git log --oneline"

alias rebase='f(){ git fetch origin; git rebase origin/$1; git rebase -i origin/$1; unset -f f; }; f'