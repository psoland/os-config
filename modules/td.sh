#!/usr/bin/env bash
# td - tmux developer layout (no bottom terminal)
#
# Layout:
#   Left:       Neovim
#   Right col:  Optional AI assistant(s) (~25% width)
#
# Usage:
#   td              # nvim only
#   td c            # + OpenCode on the right
#   td cx           # + Claude Code (danger mode) on the right
#   td c p          # + OpenCode top-right, Pi bottom-right
#   td c cx         # + OpenCode top-right, Claude Code bottom-right
#   td "my cmd"     # + arbitrary command on the right
#
set -euo pipefail

arg1="${1:-}"
arg2="${2:-}"

# Layout percentages
pct_right=25
pct_right_split=50

map_cmd() {
  case "${1:-}" in
  c) printf '%s' "opencode --port" ;;
  cx) printf '%s' "claude --dangerously-skip-permissions" ;;
  p) printf '%s' "pi" ;;
  "") printf '%s' "" ;;
  *) printf '%s' "$1" ;;
  esac
}

right_top="$(map_cmd "$arg1")"
right_bottom="$(map_cmd "$arg2")"

if [ -z "${TMUX:-}" ] || [ -z "${TMUX_PANE:-}" ]; then
  echo "td must be run from inside tmux."
  echo "Start tmux first (e.g. 't' or 'tmux')."
  exit 1
fi

# Use current pane as editor pane
nvim_pane="$TMUX_PANE"

# Idempotency: if this window already has tagged nvim pane, just jump there
existing_nvim="$(tmux list-panes -F '#{pane_id} #{@td_nvim} #{pane_current_command}' | awk '$2 == "1" && $3 == "nvim" { print $1; exit }')"
if [ -n "$existing_nvim" ]; then
  tmux select-pane -t "$existing_nvim"
  exit 0
fi

# Optional right column
if [ -n "$arg1" ]; then
  right_pane="$(tmux split-window -h -p "$pct_right" -t "$nvim_pane" -P -F '#{pane_id}' -c "$PWD")"

  if [ -n "$arg2" ]; then
    right_bottom_pane="$(tmux split-window -v -p "$pct_right_split" -t "$right_pane" -P -F '#{pane_id}' -c "$PWD")"
  fi

  tmux resize-pane -t "$right_pane" -x "${pct_right}%" 2>/dev/null || true
fi

# Mark editor pane for idempotency
tmux set-option -p -t "$nvim_pane" @td_nvim 1

# Start assistants first, then nvim
if [ -n "$arg1" ]; then
  tmux send-keys -t "$right_pane" "$right_top" C-m
  if [ -n "$arg2" ]; then
    tmux send-keys -t "$right_bottom_pane" "$right_bottom" C-m
  fi
  # CRITICAL: Do not remove this sleep!
  # The OpenCode TUI sends asynchronous terminal queries (e.g., Kitty graphics support)
  # through Tmux passthrough to Ghostty. If we switch focus to Neovim immediately,
  # the terminal's response (like `_Gi=31337;OK`) will be injected directly into Neovim
  # as raw keystrokes, triggering random Vim commands and crashing the editor.
  sleep 1.5s
fi

tmux send-keys -t "$nvim_pane" 'nvim' C-m
tmux select-pane -t "$nvim_pane"
