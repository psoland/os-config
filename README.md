# OS Config

Declarative machine setup with:
- Linux/macOS bootstrap via shell scripts
- user environment via Home Manager + flakes

## Current Scope

- Primary targets: Oracle Ubuntu VMs, Spark DGX Ubuntu, and a personal MacBook (Apple Silicon)
- User configured by bootstrap: `psoland`
- Home Manager targets in this repo: `psoland-vm`, `psoland-vm-arm`, `psoland-vm-openclaw`, `spark`, and `psoland-mac`

## Repository Layout

```
os-config/
├── flake.nix                     # Home Manager configs + template output
├── hosts/
│   ├── oracle/
│   │   ├── bootstrap.sh          # Oracle Ubuntu bootstrap (runs as root)
│   │   ├── default.nix           # Host-specific HM module wiring
│   │   └── openclaw.nix          # Oracle host variant with OpenClaw enabled
│   ├── spark/
│   │   ├── bootstrap.sh          # Spark DGX bootstrap (runs as root)
│   │   └── default.nix           # Host-specific HM module wiring
│   └── macbook/
│       ├── bootstrap.sh          # macOS bootstrap (runs as your user, not root)
│       └── default.nix           # Host-specific HM module wiring
├── modules/
│   ├── common.nix                # Shared packages and programs
│   ├── darwin.nix                # macOS-only HM bits (brew shellenv, etc.)
│   ├── openclaw.nix              # OpenClaw Home Manager module config
│   ├── zsh.nix
│   ├── tmux.nix
│   ├── starship.nix
│   └── nvim.nix
├── openclaw-documents/           # Managed OpenClaw document directory
│   ├── AGENTS.md
│   ├── SOUL.md
│   └── TOOLS.md
└── templates/
    └── devshell/
        └── flake.nix
```

## Bootstrap Scripts

### Linux bootstrap scripts (Oracle + Spark)

The Linux scripts run as root and follow this core flow:

1. Updates apt packages (`apt-get update && apt-get upgrade -y`)
2. Installs core tools (`ufw`, `zsh`, `git`)
3. Installs Tailscale
4. Installs Docker (official convenience script)
5. Configures `psoland` user for zsh + docker (Oracle bootstrap creates user; Spark expects it to already exist)
6. Oracle bootstrap copies `/home/ubuntu/.ssh/authorized_keys` to `/home/psoland/.ssh/` when present
7. Adds UFW allow rules for OpenSSH and mosh ports
8. Clones this repo to `/home/psoland/.dotfiles`
9. Installs Nix (Determinate Systems installer) if missing
10. Writes selected flake target to `~/.dotfiles/.hm-flake`
11. Applies Home Manager automatically for that target

Notes:
- UFW rules are added, but UFW is not enabled automatically.
- Repo path after bootstrap is `~/.dotfiles` for `psoland`.
- `tailscale up` is intentionally left as a manual final step because it requires interactive auth.

### macOS bootstrap script (Apple Silicon)

The macOS script runs as the normal user (`psoland`, not root) and:

1. Verifies macOS + Apple Silicon (`arm64`) + expected user/home
2. Ensures Xcode Command Line Tools are installed (opens installer prompt if missing)
3. Installs Homebrew (if missing)
4. Installs Nix (if missing)
5. Clones this repo to `~/.dotfiles` and writes `~/.dotfiles/.hm-flake`
6. Backs up conflicting dotfiles/configs to `~/.dotfiles-backup/<timestamp>/`
7. Builds and activates `homeConfigurations.psoland-mac`

Notes:
- If Xcode CLT is not installed, the script triggers installation and exits; rerun it after CLT completes.
- `nix-darwin` is intentionally not used yet. System-level macOS settings remain manual or Homebrew-managed.

## Quick Start

Linux scripts: run as root (`sudo`).
MacBook script: run as `psoland` (non-root) on Apple Silicon.

### Oracle Ubuntu VM

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/hosts/oracle/bootstrap.sh | sudo bash
```

If you want OpenClaw on Oracle, run normal bootstrap first, then switch target:

```bash
printf '%s\n' psoland-vm-openclaw > ~/.dotfiles/.hm-flake
cd ~/.dotfiles
apply
```

### Spark DGX Ubuntu

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/hosts/spark/bootstrap.sh | sudo bash
```

### MacBook (Apple Silicon)

Run as your normal user `psoland` (NOT root) on Apple Silicon. The script
fails fast if the machine is not `arm64` or if the user/home does not match
`psoland` / `/Users/psoland`.

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/hosts/macbook/bootstrap.sh | bash
```

Notes:
- `nix-darwin` is intentionally not used yet. System-level macOS settings
  (Dock, Finder, key repeat, casks, etc.) are still managed manually or via
  Homebrew. Home Manager covers shell, nvim, tmux, starship, git, and CLI
  tooling — same as on the Linux hosts.
- After bootstrap, open a new terminal so the new `~/.zshrc` and `~/.zprofile`
  are loaded.
- Homebrew stays on `PATH` via `~/.zprofile` (set from `modules/darwin.nix`),
  so brew-installed CLIs and casks still work.

### Clone and run locally

```bash
git clone https://github.com/psoland/os-config.git
cd os-config
sudo bash hosts/oracle/bootstrap.sh
```

## After Bootstrap

### Linux hosts (Oracle/Spark)

1. Authenticate Tailscale:

```bash
sudo tailscale up
```

2. Switch to the configured user:

```bash
sudo su - psoland
```

3. Log out/in (or reboot) to pick up shell/session changes.

### MacBook

1. Open a new terminal window so the new `~/.zshrc`/`~/.zprofile` load.
2. Verify key tools resolve as expected:

```bash
which nvim tmux starship git
```

3. If dotfiles were moved, review backups in `~/.dotfiles-backup/<timestamp>/`.

Home Manager is already applied by bootstrap. Re-run manually only if needed:

```bash
cd ~/.dotfiles
nix build .#homeConfigurations.$(tr -d '\n' < ~/.dotfiles/.hm-flake).activationPackage
./result/activate
```

If `~/.dotfiles/.hm-flake` does not exist, use one of these explicitly:

```bash
nix build .#homeConfigurations.psoland-vm.activationPackage
nix build .#homeConfigurations.psoland-vm-arm.activationPackage
nix build .#homeConfigurations.psoland-vm-openclaw.activationPackage
nix build .#homeConfigurations.spark.activationPackage
nix build .#homeConfigurations.psoland-mac.activationPackage
./result/activate
```

## Home Manager Configurations

| Name | User | System |
|------|------|--------|
| `psoland-vm` | `psoland` | `x86_64-linux` |
| `psoland-vm-arm` | `psoland` | `aarch64-linux` |
| `psoland-vm-openclaw` | `psoland` | `x86_64-linux` |
| `spark` | `psoland` | `aarch64-linux` |
| `psoland-mac` | `psoland` | `aarch64-darwin` |

### Oracle OpenClaw target

- OpenClaw is currently supported only on `x86_64-linux` in this repo.
- To enable OpenClaw on an Oracle machine, set `~/.dotfiles/.hm-flake` to `psoland-vm-openclaw` and apply:

```bash
printf '%s\n' psoland-vm-openclaw > ~/.dotfiles/.hm-flake
cd ~/.dotfiles
apply
```

## Common Operations

### Update flake inputs

```bash
cd ~/.dotfiles
nix flake update
nix build .#homeConfigurations.$(tr -d '\n' < ~/.dotfiles/.hm-flake).activationPackage
./result/activate
```

### Use the devshell template in another project

```bash
nix flake init -t github:psoland/os-config#devshell
```

### sync-and-apply alias

This repo provides a `syncapply` command that:
1. goes to `~/.dotfiles`
2. pulls latest changes with rebase
3. selects target in this order: `HOME_MANAGER_FLAKE` env var -> `~/.dotfiles/.hm-flake` -> fail if still unset
4. builds the selected Home Manager activation package
5. activates it

Usage:

```bash
syncapply
```

## Troubleshooting

### Nix not available in current shell

Open a new shell session, then check:

```bash
nix --version
```

### Home Manager switch fails

```bash
cd ~/.dotfiles
nix build .#homeConfigurations.$(tr -d '\n' < ~/.dotfiles/.hm-flake).activationPackage --show-trace
./result/activate
```

### SSH or firewall issues

```bash
sudo ufw status
tailscale status
```

## code-server over Tailscale

This repo enables `code-server` for the Spark host only.

Spark config uses:
- `bindAddr = 127.0.0.1:8080`
- `auth = none`

This is designed for Blink + SSH tunnel usage over Tailscale.

Apply config:

```bash
cd ~/.dotfiles
apply
```

Connect from iPad/Blink (or any Tailnet device):

1. Start tunnel from Blink:

```bash
ssh -N -L 8080:127.0.0.1:8080 spark
```

2. In another Blink tab, open Code against localhost:

```bash
code http://localhost:8080
```

Notes:
- This avoids exposing `code-server` on LAN/public interfaces.
- `code-server` is not enabled for Oracle unless you add it there.
