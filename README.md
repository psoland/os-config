# OS Config

Declarative Ubuntu VM setup with:
- system bootstrap via shell scripts
- user environment via Home Manager + flakes

## Current Scope

- Primary target: Ubuntu (Oracle Cloud works fine)
- User created/configured by bootstrap: `psoland`
- Home Manager targets in this repo: `psoland-vm` and `psoland-vm-arm`

## Repository Layout

```
os-config/
├── bootstrap.sh                  # OS detector, dispatches Ubuntu bootstrap
├── flake.nix                     # Home Manager configs + template output
├── hosts/
│   └── ubuntu/
│       ├── bootstrap.sh          # Ubuntu system bootstrap (runs as root)
│       └── default.nix           # Host-specific HM module wiring
├── modules/
│   ├── common.nix                # Shared packages and programs
│   ├── zsh.nix
│   ├── tmux.nix
│   └── starship.nix
└── templates/
    └── devshell/
        └── flake.nix
```

## What Bootstrap Currently Does

`hosts/ubuntu/bootstrap.sh` performs these actions:

1. Updates apt packages (`apt-get update && apt-get upgrade -y`)
2. Installs `ufw`, `zsh`, and `git`
3. Installs Tailscale
4. Installs Docker (official convenience script)
5. Creates/configures `psoland` user with zsh + sudo + docker group
6. Copies `/home/ubuntu/.ssh/authorized_keys` to `/home/psoland/.ssh/` (if present)
7. Adds UFW allow rules for OpenSSH and mosh ports
8. Clones this repo to `/home/psoland/.dotfiles`
9. Installs Nix (Determinate Systems installer) if missing
10. Applies Home Manager automatically (`.#psoland-vm` on x86_64, `.#psoland-vm-arm` on ARM)

Notes:
- UFW rules are added, but UFW is not enabled automatically.
- Repo path after bootstrap is `~/.dotfiles` for `psoland`.
- `tailscale up` is intentionally left as a manual final step because it requires interactive auth.

## Quick Start

Prerequisite:
- You need at least one way to fetch the bootstrap: `curl` (for one-liner) or `git` (for clone workflow).
- Most Ubuntu cloud images already include both, but minimal images may not.

### Option A: One-liner from GitHub

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap.sh | bash
```

### Option B: Clone and run locally

```bash
git clone https://github.com/psoland/os-config.git
cd os-config
bash bootstrap.sh
```

## After Bootstrap

1. Authenticate Tailscale:

```bash
sudo tailscale up
```

2. Switch to the configured user:

```bash
sudo su - psoland
```

3. Log out/in (or reboot) to pick up shell/session changes.

Home Manager is already applied by bootstrap. Re-run manually only if needed:

```bash
cd ~/.dotfiles
nix build .#homeConfigurations.psoland-vm.activationPackage
./result/activate
```

On ARM instances:

```bash
nix build .#homeConfigurations.psoland-vm-arm.activationPackage
./result/activate
```

## Home Manager Configurations

| Name | User | System |
|------|------|--------|
| `psoland-vm` | `psoland` | `x86_64-linux` |
| `psoland-vm-arm` | `psoland` | `aarch64-linux` |

## Common Operations

### Update flake inputs

```bash
cd ~/.dotfiles
nix flake update
nix build .#homeConfigurations.psoland-vm.activationPackage
./result/activate
```

### Use the devshell template in another project

```bash
nix flake init -t github:psoland/os-config#devshell
```

### VM sync-and-apply alias

This repo defines a zsh alias named `syncapply` that:
1. goes to `~/.dotfiles`
2. pulls latest changes with rebase
3. auto-detects x86_64 vs ARM
4. builds the correct Home Manager activation package
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
nix build .#homeConfigurations.psoland-vm.activationPackage --show-trace
./result/activate
```

### SSH or firewall issues

```bash
sudo ufw status
tailscale status
```
