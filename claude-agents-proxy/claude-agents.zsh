# Windows Terminal (WT_SESSION あり) の `claude agents` だけ proxy.py 経由で起動する
_claude_agents_proxy="${${(%):-%x}:A:h}/proxy.py"

claude() {
  if [[ $1 == agents && -n $WT_SESSION && -x $_claude_agents_proxy ]] && (( $+commands[python3] )); then
    "$_claude_agents_proxy" claude "$@"
  else
    command claude "$@"
  fi
}
