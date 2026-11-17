# Herdr Core and the mobile app

`modules/home/programs/herdr-core.nix` installs the pinned official **herdr-core
0.1.21** release (`herdr-core` and `hc`) alongside Herdr TUI on all configured
Linux and Apple Silicon macOS hosts. The package retains the signed macOS
application bundle. Update its version and hashes in `packages/herdr-core.nix`,
then apply Home Manager; do not use the upstream installer or `hc update`.

## Connect the mobile app

After applying dotfiles on Spark, use the existing Tailscale connection:

- Host: Spark's Tailscale hostname, MagicDNS FQDN, or Tailscale IP
- User: `psoland`
- Port: `22`

The app runs `herdr-core connect` over SSH, not `herdr`. No public core port,
web server, or desktop GUI is required. The core starts on demand. SSH access
grants control with your account's permissions; don't run core as root.

Home Manager also installs launchers at `~/.local/bin/herdr-core` and
`~/.local/bin/hc`, locations the mobile client can discover without an
interactive shell. They prepend the user's Home Manager profile to PATH so
new core-owned agents can find `opencode`, `codex`, `claude`, and `pi` too.
Existing manual launchers are not silently overwritten.

Tailscale networking alone does not replace SSH authentication. Either authorize
the app's public key for normal SSH or configure Tailscale SSH separately.

Verify discovery without starting the server:

```sh
ssh psoland@spark '$HOME/.local/bin/herdr-core --version'
```

To check the runtime after connecting, run `hc server status`. Linux logout
protection depends on systemd/logind settings. **At startup upstream core itself
tries to enable lingering** for your account so programs survive the last SSH
logout. If that is refused, it reports a warning and a suggested administrator
command. Home Manager activation does not start core or change login policy.
Neither lingering nor detaching preserves processes through a reboot.

## Share the same agents with a terminal

Herdr TUI **cannot natively connect to herdr-core** as its backend. The native
desktop app and mobile app use core; TUI has a different server and protocol.
Installing core does not import or stop existing TUI panes.

Use core as the owner of agents you want on both your terminal and your phone:

```sh
# In an ordinary SSH shell, outside Herdr TUI, from the project directory:
hc run --bg --name coding opencode

# In an ordinary terminal OR inside a Herdr TUI pane:
hc attach coding
```

This attaches to the same process the phone sees; it does not start a second
OpenCode instance. **Ctrl+\\** detaches the core viewer without ending the agent.
`hc` on its own opens a terminal picker; `hc ls` lists core's terminals.

If starting core for the first time, do it outside TUI so the core does not
inherit TUI-specific pane identifiers. Once running, core uses its own saved
environment. A core that was started with the wrong PATH can take a fresh
environment using `hc server restart --fresh` from an ordinary SSH shell.

This is a terminal-viewing workflow, not native TUI integration: TUI's agent
sidebar, pane status, layouts, and lifecycle do not become core's. Don't rely on
the TUI integrations for agents owned by core. Core reads program status via
OSC 7501; a program that does not emit status can still be a usable terminal
without an agent-status entry. Start new mobile-visible agents with `hc run`,
not by directly typing `opencode` into a TUI-owned shell.

For a fully shared sidebar and spaces/layouts, use the new Herdr desktop app
with the mobile app. This change installs the headless core only, not that GUI.

## Validate without changing live sessions

```sh
nix build --impure --no-link --file tests/herdr/core.nix
```

The test uses isolated HOME, XDG directories and socket paths, verifies the
mobile SSH probe, checks the wrapper's PATH, and exercises shared terminal
attach/detach without touching real sessions. macOS is evaluated and its
downloaded bundle is inspected on Linux; native macOS execution still needs a
Mac.
