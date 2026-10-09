#!/usr/bin/env bash
# ts - start a named tmux development session
#
# Usage: ts <session-name> [path]
#
set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [ -z "$1" ]; then
  echo "Usage: ts <session-name> [path]" >&2
  exit 1
fi

session_name="$1"
requested_dir="${2:-$PWD}"

case "$requested_dir" in
  "~") requested_dir="$HOME" ;;
  "~/"*) requested_dir="$HOME/${requested_dir#\~/}" ;;
esac

if [ ! -d "$requested_dir" ]; then
  echo "Directory does not exist: $requested_dir" >&2
  exit 1
fi

working_dir="$(cd -- "$requested_dir" && pwd -P)"
printf -v opencode_cmd 'opencode2 %q' "$working_dir"

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

nvim_pane="$(tmux new-session -d -P -F '#{pane_id}' -s "$session_name" -n nvim -c "$working_dir")"
opencode_pane="$(tmux new-window -d -P -F '#{pane_id}' -t "=$session_name" -n oc -c "$working_dir")"
hunk_pane="$(tmux new-window -d -P -F '#{pane_id}' -t "=$session_name" -n diff -c "$working_dir")"
tmux new-window -d -t "=$session_name" -n term -c "$working_dir"

# Run commands in shells so their named windows remain open after they exit.
tmux send-keys -t "$opencode_pane" "$opencode_cmd" C-m
tmux send-keys -t "$hunk_pane" 'hd' C-m
tmux send-keys -t "$nvim_pane" 'nvim' C-m
tmux select-pane -t "$nvim_pane"

if [ -n "${TMUX:-}" ]; then
  tmux switch-client -t "=$session_name"
  exit 0
else
  exec tmux attach-session -t "=$session_name"
fi
