# Ubuntu VM Setup Guide

This guide walks you through setting up a fresh Ubuntu VM with a complete development environment using Nix and Home Manager.

## Overview

This configuration provides:

- **Tailscale** - Secure networking with SSH access
- **UFW** - Firewall configured for Tailscale-only access
- **Docker** - Container runtime
- **Mosh** - Mobile shell for resilient SSH
- **Syncthing** - File synchronization
- **Nix + Home Manager** - Declarative package and dotfile management
- **NixVim** - Neovim configured entirely in Nix
- **code-server** - VS Code in the browser
- **DevPod** - Development containers
- **zsh + Oh-My-Zsh** - Modern shell with plugins
- **tmux** - Terminal multiplexer
- **Development tools** - Go, Node.js, Python, lazygit, lazydocker, etc.

## Prerequisites

- Fresh Ubuntu 22.04+ or 24.04 (Noble) VM
- sudo access
- Internet connection
- A Tailscale account (free at https://tailscale.com)

## Quick Start

### Option 1: One-line install (from GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap/ubuntu-bootstrap.sh | bash
```

### Option 2: Clone and run

```bash
# Install git if not present
sudo apt update && sudo apt install -y git

# Clone the repository
git clone https://github.com/psoland/os-config.git ~/os-config
cd ~/os-config

# Run the bootstrap script
chmod +x bootstrap/ubuntu-bootstrap.sh
./bootstrap/ubuntu-bootstrap.sh
```

## Post-Bootstrap Steps

The bootstrap script will complete most of the setup automatically. Follow these steps to finish:

### 1. Authenticate Tailscale

```bash
sudo tailscale up --ssh
```

This will:
1. Open a URL for authentication
2. Enable Tailscale SSH (no need for traditional SSH keys)

### 2. Test Tailscale SSH

From **another machine** on your Tailscale network:

```bash
# Using Tailscale hostname
ssh psoland@your-vm-hostname

# Or using Tailscale IP (find it with `tailscale ip`)
ssh psoland@100.x.y.z
```

### 3. Enable the Firewall

**Only after confirming Tailscale SSH works:**

```bash
sudo ufw enable
```

This locks down SSH to only work through Tailscale.

### 4. Configure Syncthing for Tailscale

```bash
./bootstrap/configure-syncthing.sh
```

This configures Syncthing to only listen on the Tailscale interface.

### 5. Start Your New Shell

Log out and back in, or run:

```bash
exec zsh
```

### 6. Install Additional Tools

```bash
# Install lazysql
just install-lazysql

# Install opencode
just install-opencode

# Install VS Code extensions for code-server
just install-vscode-extensions
```

## Accessing Services

All services are only accessible via Tailscale:

| Service | URL | Notes |
|---------|-----|-------|
| SSH | `ssh user@tailscale-ip` | Uses Tailscale SSH |
| Mosh | `mosh user@tailscale-ip` | Mobile shell |
| Syncthing | `http://tailscale-ip:8384` | File sync web UI |
| code-server | `http://tailscale-ip:8080` | VS Code in browser |

## Daily Usage

### Home Manager Commands

```bash
# Apply configuration changes
just switch

# Update all Nix packages
just update && just switch

# Check configuration without applying
just check

# Format Nix files
just fmt

# Clean up old generations
just gc
```

### Service Management

```bash
# Check service status
just services

# code-server
just start-code-server
just stop-code-server
just logs-code-server

# Syncthing
systemctl --user status syncthing
```

### Useful Aliases

The shell configuration includes many useful aliases:

```bash
# File listing (uses eza)
ll    # Long listing with icons
lt    # Tree view

# Git
gs    # git status
lg    # lazygit
glog  # Pretty git log

# Docker
ld    # lazydocker
d     # docker
dc    # docker compose

# Editors
v     # nvim

# Home Manager
hms   # home-manager switch
hmu   # update and switch
```

## Directory Structure

```
~/os-config/
├── bootstrap/
│   ├── ubuntu-bootstrap.sh      # Main bootstrap script
│   └── configure-syncthing.sh   # Syncthing configuration
├── home-manager/
│   ├── flake.nix                # Nix flake definition
│   ├── home.nix                 # Main home configuration
│   └── modules/
│       ├── shell.nix            # zsh + oh-my-zsh + starship
│       ├── tmux.nix             # tmux configuration
│       ├── nixvim/              # Neovim configuration
│       │   └── default.nix
│       ├── dev-tools.nix        # Development tools
│       └── services.nix         # code-server, devpod
├── docs/
│   └── SETUP.md                 # This file
└── justfile                     # Task runner commands
```

## Customization

### Adding Packages

Edit `home-manager/modules/dev-tools.nix` or `home-manager/home.nix`:

```nix
home.packages = with pkgs; [
  # Add your packages here
  your-package
];
```

Then apply:

```bash
just switch
```

### Configuring Neovim

Edit `home-manager/modules/nixvim/default.nix`. NixVim provides a declarative way to configure Neovim:

```nix
programs.nixvim = {
  plugins = {
    # Enable a plugin
    your-plugin.enable = true;
  };
  
  # Add keymaps
  keymaps = [
    {
      mode = "n";
      key = "<leader>x";
      action = ":YourCommand<CR>";
      options.desc = "Description";
    }
  ];
};
```

### Changing Shell Theme

The starship prompt is configured in `home-manager/modules/shell.nix`. Modify the `programs.starship.settings` section.

### Adding tmux Plugins

Edit `home-manager/modules/tmux.nix` and add plugins to the `plugins` list.

## Troubleshooting

### "Permission denied" after enabling UFW

If you get locked out:
1. Access the VM via console (hypervisor console, not SSH)
2. Run: `sudo ufw disable`
3. Verify Tailscale is working: `tailscale status`
4. Re-enable: `sudo ufw enable`

### Home Manager fails to build

```bash
# Check for syntax errors
just check

# Update flake lock file
just update

# Try with verbose output
home-manager switch --flake ./home-manager#psoland@ubuntu --show-trace
```

### code-server not accessible

```bash
# Check if running
systemctl --user status code-server

# Check logs
just logs-code-server

# Verify UFW allows port 8080 on tailscale0
sudo ufw status | grep 8080
```

### Syncthing not syncing

```bash
# Check service status
systemctl --user status syncthing

# View logs
journalctl --user -u syncthing -f

# Verify listening address
curl http://$(tailscale ip -4):8384
```

## Security Notes

1. **SSH is Tailscale-only** - The UFW firewall blocks port 22 on all interfaces except `tailscale0`
2. **No passwords** - Tailscale SSH uses your Tailscale identity, no password prompts
3. **Services bound to Tailscale** - code-server and Syncthing only listen on Tailscale IPs
4. **Automatic updates** - Consider enabling unattended-upgrades for security patches

## Maintenance

### Regular Updates

```bash
# Update system packages
sudo apt update && sudo apt upgrade

# Update Nix packages
just update && just switch

# Clean up old generations (weekly)
just gc-week
```

### Backup

The configuration is in git. Your actual data should be synced via Syncthing or backed up separately.

```bash
# Commit any local changes
cd ~/os-config
git add -A
git commit -m "Update configuration"
git push
```

## Expanding to macOS

This configuration is designed to be extended to macOS using nix-darwin. The `flake.nix` includes placeholders for Darwin configurations.

To add macOS support:
1. Install Nix on macOS (Determinate Systems installer)
2. Install nix-darwin
3. Add a Darwin configuration to the flake
4. Create Darwin-specific modules as needed

## Resources

- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [NixVim Documentation](https://nix-community.github.io/nixvim/)
- [Tailscale Documentation](https://tailscale.com/kb/)
- [Syncthing Documentation](https://docs.syncthing.net/)
