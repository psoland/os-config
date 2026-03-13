# tdl - tmux developer layout
#
# Layout:
#   Top-left:   Neovim
#   Bottom:     Terminal shell (full width)
#   Right col:  Optional AI assistant(s) (~30% width)
#
# Usage:
#   tdl              # nvim + bottom shell
#   tdl c            # + OpenCode on the right
#   tdl cx           # + Claude Code (danger mode) on the right
#   tdl c cx         # + OpenCode top-right, Claude Code bottom-right
#   tdl "my cmd"     # + arbitrary command on the right
#
# Override session name with TDL_SESSION env var.

set -euo pipefail

base="$(basename "$PWD" | tr -cd '[:alnum:]_-')"
session="${TDL_SESSION:-tdl-${base}}"

map_cmd() {
  case "${1:-}" in
    c)  printf '%s' "opencode" ;;
    cx) printf '%s' "claude --dangerously-skip-permissions" ;;
    "") printf '%s' "" ;;
    *)  printf '%s' "$1" ;;
  esac
}

right_top="$(map_cmd "${1:-}")"
right_bottom="$(map_cmd "${2:-}")"

# Reattach if session already exists
if tmux has-session -t "$session" 2>/dev/null; then
  exec tmux attach -t "$session"
fi

tmux new-session -d -s "$session" -c "$PWD" -n dev

# Capture the initial pane ID (this is the nvim pane)
nvim_pane="$(tmux display-message -t "$session":dev -p '#{pane_id}')"

# Split bottom terminal (25% height), capture its pane ID
bottom_pane="$(tmux split-window -v -p 25 -t "$nvim_pane" -P -F '#{pane_id}')"

# Start nvim in the top pane
tmux send-keys -t "$nvim_pane" 'nvim' C-m

# Optional right column (~30% width)
if [ -n "${1:-}" ]; then
  right_pane="$(tmux split-window -h -p 30 -t "$nvim_pane" -P -F '#{pane_id}')"
  tmux send-keys -t "$right_pane" "$right_top" C-m

  # Optional split of right column (top/bottom)
  if [ -n "${2:-}" ]; then
    right_bottom_pane="$(tmux split-window -v -p 50 -t "$right_pane" -P -F '#{pane_id}')"
    tmux send-keys -t "$right_bottom_pane" "$right_bottom" C-m
  fi
fi

tmux select-pane -t "$nvim_pane"
exec tmux attach -t "$session"
