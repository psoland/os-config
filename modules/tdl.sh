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

# Layout percentages (single source of truth)
pct_bottom=20      # bottom shell height
pct_right=25       # right column width
pct_right_split=50 # right column top/bottom split

map_cmd() {
  case "${1:-}" in
  c) printf '%s' "opencode --port" ;;
  cx) printf '%s' "claude --dangerously-skip-permissions" ;;
  "") printf '%s' "" ;;
  *) printf '%s' "$1" ;;
  esac
}

right_top="$(map_cmd "${1:-}")"
right_bottom="$(map_cmd "${2:-}")"

# 1. Determine target pane or create new session
if [ -n "${TMUX:-}" ]; then
  # We are already inside tmux — check if a TDL layout already exists in this window.
  existing_nvim="$(tmux list-panes -F '#{pane_id} #{@tdl_nvim} #{pane_current_command}' \
    | awk '$2 == "1" && $3 == "nvim" { print $1; exit }')"
  if [ -n "$existing_nvim" ]; then
    tmux select-pane -t "$existing_nvim"
    exit 0
  fi

  # Open TDL using the CURRENT pane.
  nvim_pane="$TMUX_PANE"
else
  # Reattach if session already exists
  if tmux has-session -t "$session" 2>/dev/null; then
    exec tmux attach -t "$session"
  fi

  # Extract current terminal dimensions to fix the scaling bug.
  # (Defaults to 120x40 if tput is unavailable).
  cols=$(tput cols 2>/dev/null || echo 120)
  lines=$(tput lines 2>/dev/null || echo 40)

  # Create new session with explicit dimensions to prevent 80x24 fallback scaling.
  tmux new-session -d -x "$cols" -y "$lines" -s "$session" -c "$PWD" -n dev
  nvim_pane="$(tmux display-message -t "$session:dev" -p '#{pane_id}')"
fi

# 2. Split panes using the base pane
# Using -c "$PWD" ensures that if we run this in an existing pane,
# the new splits spawn in the current directory.
bottom_pane="$(tmux split-window -v -p "$pct_bottom" -t "$nvim_pane" -P -F '#{pane_id}' -c "$PWD")"

if [ -n "${1:-}" ]; then
  right_pane="$(tmux split-window -h -p "$pct_right" -t "$nvim_pane" -P -F '#{pane_id}' -c "$PWD")"

  if [ -n "${2:-}" ]; then
    right_bottom_pane="$(tmux split-window -v -p "$pct_right_split" -t "$right_pane" -P -F '#{pane_id}' -c "$PWD")"
  fi
fi

# Explicitly resize panes as a bullet-proof fallback against tmux hooks/presets.
# The '%' ensures they are resized relative to the window.
tmux resize-pane -t "$bottom_pane" -y "${pct_bottom}%" 2>/dev/null || true
if [ -n "${1:-}" ]; then
  tmux resize-pane -t "$right_pane" -x "${pct_right}%" 2>/dev/null || true
fi

# 3. Mark the nvim pane so repeated calls are idempotent
tmux set-option -p -t "$nvim_pane" @tdl_nvim 1

# 4. Focus the nvim pane and start Nvim
tmux select-pane -t "$nvim_pane"
if [ -n "${TMUX:-}" ]; then
  # Start assistant commands AFTER nvim so they don't interfere with startup.
  # send-keys queues input; the commands run once each pane's shell is ready.
  if [ -n "${1:-}" ]; then
    tmux send-keys -t "$right_pane" "$right_top" C-m
    if [ -n "${2:-}" ]; then
      tmux send-keys -t "$right_bottom_pane" "$right_bottom" C-m
    fi
  fi
  exec nvim .
else
  if [ -n "${1:-}" ]; then
    tmux send-keys -t "$right_pane" "$right_top" C-m
    if [ -n "${2:-}" ]; then
      tmux send-keys -t "$right_bottom_pane" "$right_bottom" C-m
    fi
  fi
  tmux send-keys -t "$nvim_pane" 'nvim .' C-m
  exec tmux attach -t "$session"
fi
