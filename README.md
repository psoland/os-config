# OS Config - Nix-Based Multi-Platform Configuration

A declarative, reproducible system configuration for Ubuntu VMs with future macOS support via Nix and Home Manager.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Ubuntu VM                                 │
├─────────────────────────────────────────────────────────────────┤
│  System Layer (apt)          │  User Layer (Nix + Home Manager) │
│  ─────────────────────       │  ────────────────────────────────│
│  • git                       │  • zsh (with plugins, config)    │
│  • curl, wget                │  • tmux                          │
│  • ufw                       │  • neovim                        │
│  • tailscale                 │  • lazygit, lazydocker, lazysql  │
│  • docker                    │  • opencode                      │
│  • mosh                      │  • devpod                        │
│  • code-server (optional)    │  • syncthing (user service)      │
│                              │  • go, node, python (optional)   │
└─────────────────────────────────────────────────────────────────┘
```

## Design Principles

1. **Declarative**: All configuration in version control
2. **Reproducible**: Same config produces same environment
3. **Portable**: Ubuntu today, macOS tomorrow
4. **Secure**: Tailscale-only SSH access, UFW firewall
5. **Developer-focused**: Per-project environments via Nix devShells

## Directory Structure

```
os-config/
├── flake.nix                    # Main flake with home-manager
├── flake.lock                   # Locked dependency versions
├── README.md                    # This file
├── bootstrap/
│   └── ubuntu-vm.sh             # Initial system setup script
├── hosts/
│   └── ubuntu-vm/
│       └── default.nix          # Host-specific configuration
├── modules/
│   └── home/
│       ├── default.nix          # Common home configuration
│       ├── shell.nix            # zsh configuration
│       ├── git.nix              # git configuration
│       ├── editors.nix          # neovim, etc.
│       ├── terminal.nix         # tmux, terminal tools
│       ├── dev-tools.nix        # lazygit, lazydocker, etc.
│       └── services.nix         # syncthing, etc.
└── templates/
    └── devshell/
        └── flake.nix            # Template for project devshells
```

## Quick Start

### Prerequisites

- Fresh Ubuntu 22.04 or 24.04 VM
- SSH access to the VM
- Internet connection

### Initial Setup

1. **Download and run the bootstrap script:**

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap/ubuntu-vm.sh | bash
```

Or manually:

```bash
wget https://raw.githubusercontent.com/psoland/os-config/main/bootstrap/ubuntu-vm.sh
chmod +x ubuntu-vm.sh
./ubuntu-vm.sh
```

2. **Configure Tailscale:**

```bash
sudo tailscale up
```

Follow the authentication link and verify connectivity:

```bash
tailscale ip -4
```

3. **Apply Home Manager configuration:**

```bash
cd ~/os-config
nix run home-manager/master -- switch --flake .#ubuntu-vm
```

4. **Set ZSH as default shell:**

```bash
chsh -s $(which zsh)
```

5. **Reboot or log out/in** to apply all changes

### Post-Install

- Syncthing web UI: `http://localhost:8384`
- SSH is now restricted to Tailscale network only
- Access via: `ssh psoland@<tailscale-hostname>`

## Implementation Plan

### Phase 1: Bootstrap & Foundation

#### 1. Ubuntu VM Bootstrap Script ✓
- Install essential apt packages (git, curl, build-essential)
- Install system services (ufw, tailscale, docker, mosh)
- Configure UFW with temporary SSH access
- Install Nix using Determinate Systems installer
- Clone os-config repository

#### 2. Base Flake Structure ✓
- Create flake.nix with nixpkgs and home-manager
- Support x86_64-linux and aarch64-linux
- Placeholder for future macOS support
- Host-specific configuration

### Phase 2: Home Manager Core Modules

#### 3. ZSH Configuration
- Fully declarative shell configuration
- Plugins: syntax-highlighting, autosuggestions, fzf
- Starship or pure prompt
- Aliases, functions, history settings

#### 4. Git Configuration
- User settings, aliases
- Delta for diffs
- Credential helper
- Global gitignore

#### 5. Neovim Configuration
- Declarative neovim setup
- Essential plugins and LSP support
- Choice between nixvim or manual config

#### 6. Terminal Tools (tmux)
- Sensible defaults and keybindings
- Theme configuration
- Plugin management

#### 7. Development Tools
- lazygit, lazydocker, lazysql
- opencode
- devpod

#### 8. Syncthing User Service
- Declarative service configuration
- Auto-start on login
- Web UI access

### Phase 3: Security & Network

#### 9. Tailscale Integration
- Authentication workflow
- MagicDNS configuration
- Hostname documentation

#### 10. UFW for Tailscale-Only SSH
- Default deny incoming
- SSH only from Tailscale subnet (100.64.0.0/10)
- Mosh port configuration
- Service-specific rules

### Phase 4: Developer Experience

#### 11. Project DevShell Template
- Reusable flake template
- Node, Python, Go patterns
- direnv integration
- Usage documentation

#### 12. Code-Server (Optional)
- Browser-based VS Code
- Tailscale access
- Authentication setup

### Phase 5: Documentation & Polish

#### 13. Setup Documentation
- Complete setup guide
- Customization instructions
- Adding new packages
- macOS migration path

#### 14. GitHub Actions
- Flake validation on PRs
- Build checks

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Nix installer | Determinate Systems | Better flake support, official installer |
| nixpkgs channel | unstable | Access to latest tools (opencode, devpod) |
| System packages | apt | Docker, Tailscale, UFW integrate at system level |
| User packages | home-manager | Declarative, reproducible, portable to macOS |
| Node/Python | Per-project devShells | Best isolation, prevents version conflicts |
| Shell config | Fully Nix-managed | Single source of truth, no configuration drift |
| Syncthing | User service | Simpler permissions, consistent across platforms |
| SSH access | Tailscale-only | Zero-trust security, no exposed ports |

## Usage

### Adding a New Package

**System-level (apt):**
Add to `bootstrap/ubuntu-vm.sh` for services that need deep system integration.

**User-level (Nix):**
Add to the appropriate module in `modules/home/`:

```nix
# modules/home/dev-tools.nix
{ pkgs, ... }: {
  home.packages = with pkgs; [
    new-package
  ];
}
```

Then apply:
```bash
home-manager switch --flake .#ubuntu-vm
```

### Creating a Project DevShell

```bash
cd my-project
nix flake init -t github:psoland/os-config#devshell
# Edit flake.nix to add project-specific dependencies
echo "use flake" > .envrc
direnv allow
```

### Updating Dependencies

```bash
cd ~/os-config
nix flake update
home-manager switch --flake .#ubuntu-vm
```

## Security

### SSH Access
- SSH is restricted to Tailscale network (100.64.0.0/10)
- Key-based authentication required
- No password authentication

### Firewall (UFW)
- Default deny incoming
- Tailscale subnet allowed
- Specific service ports as needed

### Best Practices
- Keep secrets out of the repository
- Use Tailscale for all remote access
- Regularly update Nix flake dependencies
- Review UFW rules periodically

## Future Plans

### macOS Support
The flake structure is designed to support nix-darwin:

```nix
# Future flake.nix structure
{
  homeConfigurations = {
    "ubuntu-vm" = ...; # Linux
    "macbook" = ...;   # macOS via nix-darwin
  };
}
```

### Potential Additions
- Secrets management (sops-nix or age)
- Automated backups
- Monitoring and alerting
- Additional development tools
- Language-specific environments

## Troubleshooting

### Nix Installation Issues
```bash
# Verify Nix installation
nix --version

# Check flake configuration
nix flake check

# Rebuild with verbose output
home-manager switch --flake .#ubuntu-vm --show-trace
```

### SSH Locked Out
If you get locked out after UFW configuration:
1. Access via VM console (not SSH)
2. Check UFW status: `sudo ufw status`
3. Verify Tailscale is running: `tailscale status`
4. Temporarily allow SSH: `sudo ufw allow 22/tcp`

### Home Manager Issues
```bash
# Check what would change
home-manager build --flake .#ubuntu-vm

# Reset to previous generation
home-manager generations
/nix/store/...-home-manager-generation/activate
```

## Contributing

This is a personal configuration repository, but feel free to fork and adapt for your own use.

## License

MIT

## Acknowledgments

- [Nix](https://nixos.org/) - Reproducible package management
- [Home Manager](https://github.com/nix-community/home-manager) - Declarative dotfile management
- [Determinate Systems](https://determinate.systems/) - Nix installer
- [Tailscale](https://tailscale.com/) - Zero-config VPN
