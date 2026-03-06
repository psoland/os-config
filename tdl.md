# tdl (tmux developer layout)

This sets up a tmux layout like:

- Top-left: Neovim
- Bottom (full width): terminal shell
- Optional right column (about 30% width): OpenCode (`c`) or Claude Code danger mode (`cx`)

## Install

Save this script as `tdl` somewhere on your `PATH` (for example `~/.local/bin/tdl`) and make it executable:

```bash
chmod +x ~/.local/bin/tdl
```

## Usage

```bash
# tmux developer layout only (nvim + bottom shell)
tdl

# add OpenCode on the right
tdl c

# add Claude Code (danger mode) on the right
tdl cx
```

## Script

```bash
#!/usr/bin/env bash
set -euo pipefail

# session name per folder; override with TDL_SESSION if you want
base="$(basename "$PWD" | tr -cd '[:alnum:]_-')"
session="${TDL_SESSION:-tdl-${base}}"

map_cmd() {
  case "${1:-}" in
    c)  printf '%s' "opencode" ;;
    cx) printf '%s' "claude --dangerously-skip-permissions" ;;
    "") printf '%s' "" ;;
    *)  printf '%s' "$1" ;; # allow custom command strings too
  esac
}

right_top="$(map_cmd "${1:-}")"
right_bottom="$(map_cmd "${2:-}")"

# attach if already running
if tmux has-session -t "$session" 2>/dev/null; then
  exec tmux attach -t "$session"
fi

tmux new-session -d -s "$session" -c "$PWD" -n dev

# Base layout: top + bottom (bottom is 25% height)
tmux split-window -v -p 25 -t "$session":dev
tmux send-keys -t "$session":dev.0 'nvim' C-m

# Optional right column (about 30% width)
if [ -n "${1:-}" ]; then
  tmux select-pane -t "$session":dev.0
  tmux split-window -h -p 30 -t "$session":dev
  tmux send-keys -t "$session":dev.2 "$right_top" C-m

  # Optional split of right column
  if [ -n "${2:-}" ]; then
    tmux select-pane -t "$session":dev.2
    tmux split-window -v -p 50 -t "$session":dev
    tmux send-keys -t "$session":dev.3 "$right_bottom" C-m
  fi
fi

tmux select-pane -t "$session":dev.0
exec tmux attach -t "$session"
```
