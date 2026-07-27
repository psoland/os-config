#!/usr/bin/env bash
# ts - start a named tmux development session
#
# Usage: ts <session-name>
#
set -euo pipefail

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo "Usage: ts <session-name>" >&2
  exit 1
fi

session_name="$1"
working_dir="$PWD"

case "$session_name" in
  *[.:]*)
    echo "Session name cannot contain '.' or ':'." >&2
    exit 1
    ;;
esac

if tmux has-session -t "=$session_name" 2>/dev/null; then
  echo "Tmux session '$session_name' already exists." >&2
  exit 1
fi

tmux new-session -d -s "$session_name" -n nvim -c "$working_dir"
tmux new-window -d -t "=$session_name" -n hunk -c "$working_dir"
tmux new-window -d -t "=$session_name" -n oc -c "$working_dir"
tmux new-window -d -t "=$session_name" -n term -c "$working_dir"

# Run commands in shells so their named windows remain open after they exit.
tmux send-keys -t "=$session_name:hunk" 'hd' C-m
tmux send-keys -t "=$session_name:oc" 'opencode' C-m

# Let OpenCode finish its asynchronous terminal queries before Neovim starts.
sleep 1.5s
tmux send-keys -t "=$session_name:nvim" 'nvim' C-m
tmux select-window -t "=$session_name:nvim"

if [ -n "${TMUX:-}" ]; then
  exec tmux switch-client -t "=$session_name"
else
  exec tmux attach-session -t "=$session_name"
fi
