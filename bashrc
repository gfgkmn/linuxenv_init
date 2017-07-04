# export LC_ALL=en_US.UTF-8
# export LANG=en_US.UTF-8
export PATH=$PATH:$HOME/Application/bin
source $(which virtualenvwrapper.sh)
source ~/Application/bin/z.sh
alias j=z
export HISTFILESIZE=
export HISTSIZE=
export HISTTIMEFORMAT="[%F %T] "

# fs [FUZZY PATTERN] - Select selected tmux session
#   - Bypass fuzzy finder if there's only one match (--select-1)
#   - Exit if there's no match (--exit-0)
fs() {
	  local session
	    session=$(tmux list-sessions -F "#{session_name}" | \
		        fzf --query="$1" --select-1 --exit-0) &&
			  tmux a -t "$session"

}
