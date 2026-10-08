# Agent indicators

`Ctrl+s`, then `s`, opens the normal tmux session tree. Dots appear after the
session names, padded to the same column using the longest current name. Sorting,
expansion, previews, and session names are unchanged. Width is recalculated each
time the picker opens; exceptionally long names can push details off a narrow
terminal. Tagging a row with `t` adds tmux's own `*`, shifting that row one cell.

| Dot | Meaning |
| --- | --- |
| Amber | At least one agent is running |
| Green | An agent finished a turn and you have not visited the session yet |
| Blue | An agent needs input/approval, or failed, and you have not visited yet |
| Blank | No running agents or unread notifications |

Unread input takes priority over unread completion, which takes priority over
running. Each agent/conversation/input request has independent state. Entering
the session acknowledges **all** of its existing notifications, even those in
other windows. Highlighting a row or opening the picker does not acknowledge it.
Running remains visible until the agent stops. An acknowledged input request
stays hidden until a new attention event arrives; it does not repeatedly reappear.

## Installation and colors

Close OpenCode V2 clients before activating the appropriate Home Manager
configuration (activation replaces `cli.json`). Reload tmux using `Ctrl+s`, `r`,
then reopen the clients so they pick up the CLI plugin and the new `tmux-agent`
executable on their PATH. No changes to `ts.sh` are needed. If invoking a
Git-backed flake directly, include the new files in its Git index first; no files
have been staged or committed automatically here.

Defaults are in `modules/home/programs/tmux.nix`. Colors can also be changed live:

```sh
tmux set -g @agent_running_color yellow
tmux set -g @agent_finished_color '#a6e3a1'
tmux set -g @agent_input_color '#89b4fa'
```

Reloading tmux preserves live overrides. Edit the module's defaults to make a
choice declarative for new tmux servers.

## OpenCode V2

`config/opencode/plugins/tmux-agent` is enabled in `cli.json`. It observes the
conversations displayed by each CLI, including those left running after switching
to another conversation. It filters out other conversations on the shared server.
Subagent input requests contribute to their parent's attention; subagent completion
alone does not count as parent completion. An idle conversation at startup does
not create a green notification.

The plugin uses V2 execution, permission, and form events. It captures the **CLI's**
tmux socket/pane, not the background server's environment or a worktree pathname.
Failures need attention; interrupted turns do not create a completion notification.

State is kept in tmux pane options. Session names may change and agent windows may
move between sessions. Closing the CLI unregisters its sources; abruptly killed
CLI processes are pruned on the next event/picker refresh. A running process that
hangs cannot be distinguished from a running agent without additional monitoring.
There is no background polling service, sidebar, desktop notification, or sound.

## Other agents

Only **OpenCode V2** is wired automatically in this first version. Claude Code,
Codex, Pi, and V1 OpenCode can use the same helper through their own adapters:

```sh
tmux-agent state running --source claude
tmux-agent state needs-input --source claude --event approval-123
tmux-agent state finished --source claude --event turn-456
tmux-agent remove --source claude
```

The socket and pane default to `TMUX` and `TMUX_PANE`. Supply `--socket` (before
the subcommand) and `--pane` explicitly when the adapter runs elsewhere. Use a
stable source per agent/conversation. For simultaneous input requests, use a
separate source per request and remove it when answered. `--event` deduplicates
repeated reports of that event; do not use a constant event ID for every turn.
`idle` clears a source's state without reporting completion. `--pid` can identify
the local agent process for dead-client cleanup. `--at` accepts local Unix
milliseconds so delayed events do not re-notify after acknowledgement.

## Tests

```sh
python3 -B -m unittest discover -s tests/tmux -p '*_test.py' -v
node --test tests/opencode/tmux-agent.test.mjs
```

The Python integration tests run isolated tmux servers, never the active server.
