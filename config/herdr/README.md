# Herdr: Balanced profile

`modules/home/programs/herdr.nix` installs Herdr and its integrations through Home
Manager. Edit dotfiles and apply them instead of running `herdr integration
install`, `herdr integration uninstall`, or using the integration installer in
Herdr's settings UI. Herdr's config and integration scripts are immutable store
symlinks; in-app attempts to save settings may fail. Logs, sockets, snapshots,
and other runtime state remain outside this repo.

## Keys

The prefix is **Ctrl+S**. After pressing it:

| Key | Action |
| --- | --- |
| `c` | New tab immediately, without a naming prompt |
| `p` or `Ctrl+P` | Previous tab |
| `n` or `Ctrl+N` | Next tab |
| `h/j/k/l` | Focus pane |
| `v` / `-` | Split |
| `[` | Copy mode (`v` selects, `y` or Enter copies) |
| `r`, then arrows or `h/j/k/l` | Resize mode |
| `g` | Searchable navigator |
| `s` | Settings |
| `T` | Rename tab |
| `R` | Reload config |

Everything else retains upstream defaults: follow the source directory for new
panes/tabs, Catppuccin, the native agent sidebar, persistence, and restoration.
Existing tmux settings are unchanged. SSH auto-attach to tmux remains disabled
in `zsh.nix`; its commented example checks `HERDR_ENV` to avoid nesting tmux
inside Herdr if it is re-enabled later. `stty -ixon` allows Ctrl+S in both tools.

## Integrations

- **Pi:** `.pi/agent/extensions/herdr-agent-state.ts` from the pinned Herdr input.
- **Claude Code:** `.claude/hooks/herdr-agent-state.sh` from that same input;
  `agent-hooks.json` declares its `SessionStart` registration.
- **Codex:** `.codex/herdr-agent-state.sh` from that same input;
  `agent-hooks.json` declares its `SessionStart` registration and activation
  ensures `[features] hooks = true`.
- **OpenCode V2:** `../opencode/plugins/herdr-agent/`, loaded by `cli.json`.
  This is deliberately a terminal-client plugin, not a shared-server plugin.
  It captures the client's pane/socket, reports root-session identity and
  lifecycle state, and includes pending requests from child sessions without
  allowing their completions to mark the root idle. It is inert outside Herdr.

The OpenCode bridge uses Herdr's official `herdr:opencode` protocol source. It
replaces the incompatible upstream V1 file; `herdr integration status` may still
say OpenCode is **not installed** because that command only checks the old file.
Do not reinstall it to clear that message.

Herdr 0.8.0 launches `opencode --session <id>` when restoring an OpenCode pane.
The dotfiles install V2 as `opencode` on Linux and Apple Silicon macOS, with
`opencode2` pointing to that same binary. This removes the previous V1/V2
executable mismatch. End-to-end restoration should still be checked in Herdr.

### Adoption and updates

On activation, `manage-integrations.py` backs up existing regular Herdr config
and recognized integration scripts before replacing them with Home Manager
links. Unknown scripts abort adoption. The old OpenCode V1 integration is backed
up and removed if present. Already-managed symlinks are left alone.

Agent configs stay writable. Activation replaces only Herdr hook registrations,
preserving other hooks, preferences, model selections, trust settings, and TOML
comments. Changed files are backed up before an atomic write. Credentials and
machine-specific agent settings are never copied into this repo. Default agent
config directories are used; custom `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, or
`PI_CODING_AGENT_DIR` overrides need corresponding module changes.

Backups are private files under
`$XDG_STATE_HOME/herdr/dotfiles-backups/<timestamp>/` (normally
`~/.local/state/herdr/dotfiles-backups/`).

Update the `herdr` flake input to update the binary and upstream Pi/Claude/Codex
assets together. The custom OpenCode bridge is maintained here separately.

Build and check without activating:

```sh
nix build --impure --no-link --file tests/herdr/default.nix
node --test tests/opencode/herdr-agent.test.mjs
```

Apply Home Manager after closing V2 terminal clients, as the existing activation
replaces `cli.json`. For Spark, without staging files:

```sh
nix build 'path:.#homeConfigurations.spark.activationPackage'
./result/activate
herdr server reload-config
```

New agent processes load the managed Pi/Claude/Codex integrations. OpenCode V2
watches `cli.json` and reloads terminal plugins after its next launch or save.
