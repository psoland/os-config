# Quick Start Guide

This is a minimal Nix + Home Manager configuration for Ubuntu VMs, designed following best practices from expert configurations.

## Architecture

```
os-config/
├── flake.nix              # Main flake with homeConfigurations
├── lib/
│   └── mkHome.nix         # Factory function (inspired by mitchellh/mksystem.nix)
├── home/
│   ├── psoland.nix        # User config (inspired by ironicbadger/alex.nix)
│   └── starship/
│       └── starship.toml  # Starship prompt config
├── hosts/
│   └── oracle-vm/
│       └── default.nix    # Host-specific settings
├── docker/
│   └── Dockerfile         # Ubuntu 24.04 test container
├── justfile               # Command shortcuts
└── bootstrap.sh           # Initial setup script
```

## What You Get

- **Modern Shell**: zsh + starship prompt + autosuggestions + syntax highlighting
- **Better CLI Tools**: eza (ls), bat (cat), fd (find), ripgrep (grep), fzf
- **Smart Navigation**: zoxide (z command)
- **Git Integration**: Configured git with aliases + gh CLI
- **Project Environments**: direnv + nix-direnv for per-project shells
- **Easy Commands**: `just switch`, `just update`, `just gc`

## Quick Start on Oracle Cloud VM

### Option 1: One-Line Bootstrap

```bash
curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap.sh | bash
```

This will:
1. Install Nix (using Determinate Systems installer)
2. Clone this repository to `~/os-config`
3. Apply the home-manager configuration
4. Set up all tools and shell

After completion:
```bash
exec zsh  # Start using zsh
```

### Option 2: Manual Setup

```bash
# 1. Install Nix
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install

# 2. Start new shell to load Nix
exec bash

# 3. Clone this repo
git clone https://github.com/psoland/os-config.git ~/os-config
cd ~/os-config

# 4. Apply configuration
nix run home-manager/master -- switch --flake .#psoland@oracle-vm

# 5. Start zsh
exec zsh
```

## Using Just Commands

This repo uses [just](https://github.com/casey/just) for command shortcuts:

```bash
# Build and switch to new configuration
just switch

# See what would change (dry-run)
just dry-run

# Update all flake inputs
just update

# Validate flake
just check

# Format nix files
just fmt

# Garbage collect old generations
just gc

# Enter dev shell
just dev
```

## Docker Testing

Test the configuration in a Docker container before deploying:

```bash
# Build test image
just docker-build

# Run interactive container
just docker-run

# Test full bootstrap in container
just docker-test
```

## Customization

### Update Git Config

Edit `home/psoland.nix`:

```nix
programs.git = {
  # ...
  userName = "Your Name";        # <- Update this
  userEmail = "you@example.com"; # <- Update this
};
```

Then apply:
```bash
just switch
```

### Add More Packages

Edit `home/psoland.nix`:

```nix
home.packages = with pkgs; [
  # Existing packages...
  neovim    # Add new packages here
  tmux
];
```

### Add a New Host

1. Create `hosts/new-host/default.nix`
2. Add to `flake.nix`:
   ```nix
   homeConfigurations = {
     "psoland@oracle-vm" = mkHome { ... };
     "psoland@new-host" = mkHome {
       hostname = "new-host";
       username = "psoland";
     };
   };
   ```

### Add macOS Support (Future)

The `mkHome` factory is designed to support macOS:

```nix
"psoland@macbook" = mkHome {
  hostname = "macbook";
  username = "psoland";
  system = "aarch64-darwin";  # or "x86_64-darwin"
};
```

## Extending the Configuration

This is intentionally minimal. Here are extension points:

### Add Neovim

Create `home/neovim.nix`:
```nix
{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    # Add plugins, config, etc.
  };
}
```

Import in `home/psoland.nix`:
```nix
{
  imports = [ ./neovim.nix ];
  # ...
}
```

### Add Tmux

In `home/psoland.nix`:
```nix
programs.tmux = {
  enable = true;
  keyMode = "vi";
  mouse = true;
  # Add more config
};
```

## Key Design Patterns

This configuration follows patterns from expert Nix configs:

1. **Factory Function** (`lib/mkHome.nix`) - From mitchellh's `mksystem.nix`
   - Reduces repetition
   - Consistent structure across hosts
   - Easy to add new configurations

2. **Single User File** (`home/psoland.nix`) - From ironicbadger's `alex.nix`
   - All user config in one place
   - Programs configured declaratively
   - External files (like starship.toml) imported

3. **Host Separation** (`hosts/oracle-vm/`) - From both inspiration repos
   - Host-specific overrides
   - Shared config in `home/psoland.nix`

4. **Build Tools** (`justfile`) - From ironicbadger's justfile
   - Platform-aware commands
   - Common operations simplified

## Troubleshooting

### Nix Command Not Found

After installing Nix, start a new shell:
```bash
exec bash
# or
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Home Manager Errors

Show detailed trace:
```bash
home-manager switch --flake .#psoland@oracle-vm --show-trace
```

### Rollback to Previous Generation

```bash
home-manager generations
# Find the generation number
/nix/store/...-home-manager-generation/activate
```

## Resources

- [Nix Pills](https://nixos.org/guides/nix-pills/) - Learn Nix fundamentals
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Home Manager Options](https://mipmip.github.io/home-manager-option-search/)
- Inspiration repos in `inspiration/` directory

## Next Steps

1. Customize git config with your details
2. Add more packages as needed
3. Explore creating project-specific devShells
4. Consider adding neovim, tmux, or other tools
5. Set up Tailscale/UFW for security (see README.md)
