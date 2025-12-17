# Nix Configuration Repository

A cross-platform, modular Nix configuration for managing development environments, dotfiles, and system settings across macOS and Linux using Nix flakes, home-manager, and nix-darwin.

## Overview

This repository provides:
- Reproducible development environments across multiple machines
- Unified package and dotfile management
- Support for both stable and unstable nixpkgs
- Safe testing environment via Docker
- Modular configuration that's easy to customize

## Supported Systems

- **macOS** (Apple Silicon & Intel) - via nix-darwin
- **Ubuntu** - via home-manager
- **Spark OS** - via home-manager

## Repository Structure

```
os-config/
├── flake.nix                    # Main flake configuration
├── flake.lock                   # Lock file (auto-generated)
├── Dockerfile                   # Ubuntu testing environment
│
├── hosts/                       # Host-specific configurations
│   ├── ubuntu/
│   │   ├── default.nix         # Ubuntu home-manager config
│   │   └── packages.nix        # Ubuntu-specific packages
│   ├── spark/
│   │   ├── default.nix         # Spark OS config
│   │   └── packages.nix        # Spark-specific packages
│   └── macbook/
│       ├── darwin.nix          # macOS system config
│       ├── home.nix            # macOS home-manager config
│       └── packages.nix        # macOS-specific packages
│
├── modules/                     # Reusable configuration modules
│   ├── shell.nix               # Zsh configuration
│   ├── git.nix                 # Git configuration
│   ├── starship.nix            # Starship prompt
│   └── packages.nix            # Common packages
│
└── home/                        # Platform-specific home configs
    ├── common.nix              # Shared config
    ├── linux.nix               # Linux-specific
    └── darwin.nix              # macOS-specific
```

## Quick Start

### Option 1: Using Dev Container (Recommended for Development)

If you use VS Code, this is the easiest way to get started:

1. **Install prerequisites:**
   - [VS Code](https://code.visualstudio.com/)
   - [Dev Containers extension](https://marketplace.visualstudio.com/items?itemName=ms-vscode-remote.remote-containers)
   - [Docker Desktop](https://www.docker.com/products/docker-desktop)

2. **Open in Dev Container:**
   - Open this repository in VS Code
   - Press `Cmd+Shift+P` (Mac) or `Ctrl+Shift+P` (Windows/Linux)
   - Select "Dev Containers: Reopen in Container"
   - Wait for the container to build (first time takes 5-10 minutes)

3. **You're ready!** The dev container includes:
   - Nix with flakes enabled
   - All required tools (git, zsh, etc.)
   - Your workspace mounted (changes persist)
   - VS Code extensions for Nix development

4. **Test your configuration:**
   ```bash
   nix flake check
   home-manager switch --flake .#psoland
   ```

### Option 2: Install Nix Directly

For production use on your actual machines:

1. **Install Nix** (if not already installed):
   ```bash
   curl -L https://nixos.org/nix/install | sh -s -- --daemon
   ```

2. **Enable flakes** (add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`):
   ```
   experimental-features = nix-command flakes
   ```

### Installation

#### On macOS

1. Install nix-darwin:
   ```bash
   nix run nix-darwin -- switch --flake .#psoland
   ```

2. For subsequent updates:
   ```bash
   darwin-rebuild switch --flake .#psoland
   ```

#### On Ubuntu/Linux

1. Install home-manager:
   ```bash
   nix run home-manager/release-24.11 -- switch --flake .#ubuntu
   ```

2. For subsequent updates:
   ```bash
   home-manager switch --flake .#ubuntu
   ```

#### On Spark OS

Same as Ubuntu, but use `spark` instead:
```bash
home-manager switch --flake .#spark
```

## Testing with Docker

### Using Dev Container (Recommended)

See "Quick Start - Option 1" above. The dev container gives you:
- Instant testing without rebuilding
- Full IDE integration
- Persistent workspace
- Proper Git integration

### Using Standalone Docker Container

For CI/CD or quick one-off testing without VS Code:

1. Build the Docker image:
   ```bash
   docker build -t nix-config-test .
   ```

2. Run the container:
   ```bash
   docker run -it nix-config-test
   ```

3. Inside the container, test your configuration:
   ```bash
   # Validate the flake
   nix flake check
   
   # Build the home-manager configuration
   nix build .#homeConfigurations.psoland.activationPackage
   
   # Apply the configuration (safe in container)
   home-manager switch --flake .#psoland
   ```

**Note:** The standalone Docker container copies files at build time. For iterative development, use the dev container instead.

## Customization

### Adding Packages

**Common packages** (available on all systems):
- Edit `modules/packages.nix`

**Host-specific packages**:
- Edit `hosts/{ubuntu,spark,macbook}/packages.nix`

**Using unstable packages**:
```nix
{ pkgs, pkgs-unstable, ... }:
{
  home.packages = [
    pkgs.git              # Stable version
    pkgs-unstable.neovim  # Unstable version
  ];
}
```

### Modifying System Settings (macOS)

Edit `hosts/macbook/darwin.nix` and uncomment the system defaults section:

```nix
system.defaults = {
  dock = {
    autohide = true;
    # ... more settings
  };
};
```

### Using Homebrew (macOS)

Uncomment the homebrew section in `hosts/macbook/darwin.nix`:

```nix
homebrew = {
  enable = true;
  casks = [
    "visual-studio-code"
    "firefox"
  ];
};
```

### Customizing Shell

Edit `modules/shell.nix` to:
- Add shell aliases
- Modify zsh configuration
- Add custom initialization scripts

### Customizing Git

Edit `modules/git.nix` to change:
- User name and email
- Git aliases
- Core settings

## Common Commands

### Flake Commands

```bash
# Check flake for errors
nix flake check

# Update flake inputs (nixpkgs, home-manager, etc.)
nix flake update

# Update a specific input
nix flake lock --update-input nixpkgs

# Show flake info
nix flake show

# Format nix files
nix fmt
```

### macOS (darwin-rebuild)

```bash
# Apply configuration
darwin-rebuild switch --flake .#psoland

# Build without applying
darwin-rebuild build --flake .#psoland

# View changelog
darwin-rebuild changelog
```

### Linux (home-manager)

```bash
# Apply configuration
home-manager switch --flake .#ubuntu

# Build without applying
home-manager build --flake .#ubuntu

# View generations
home-manager generations
```

### Garbage Collection

```bash
# Remove old generations and cleanup
nix-collect-garbage -d

# On macOS, also remove old darwin generations
sudo nix-collect-garbage -d
```

## Architecture Notes

### System Architecture

The flake supports both architectures, easily switchable:
- **Apple Silicon (M1/M2/M3)**: `aarch64-darwin` (default in flake)
- **Intel Mac**: `x86_64-darwin`
- **Linux**: `x86_64-linux`

To change architecture, edit `flake.nix` and update the system value.

### Package Sources

- **Stable packages**: From nixpkgs 24.11
- **Unstable packages**: From nixpkgs-unstable
- Both are available in all modules via `pkgs` and `pkgs-unstable`

### Configuration Layers

1. **Common modules** (`modules/`): Shared across all systems
2. **Platform configs** (`home/`): Linux vs macOS differences
3. **Host configs** (`hosts/`): Machine-specific settings

## Development

### Project-Specific Toolchains

Python, Node, and Rust are NOT installed globally. Use per-project `flake.nix` files:

```nix
{
  description = "Project environment";
  
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };
  
  outputs = { nixpkgs, ... }: {
    devShells.x86_64-linux.default = let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in pkgs.mkShell {
      buildInputs = with pkgs; [
        python311
        nodejs_20
        rustc
        cargo
      ];
    };
  };
}
```

Then enter the environment:
```bash
nix develop
```

## Troubleshooting

### Flake evaluation errors

```bash
# Check what's wrong
nix flake check --show-trace
```

### Home-manager activation fails

```bash
# View detailed error messages
home-manager switch --flake .#ubuntu --show-trace
```

### macOS architecture mismatch

If you're on Intel Mac, change `aarch64-darwin` to `x86_64-darwin` in `flake.nix`.

### Docker Nix not found

Inside the Docker container, source the Nix profile:
```bash
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

## Additional Resources

- [Nix Manual](https://nixos.org/manual/nix/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [nix-darwin Manual](https://daiderd.com/nix-darwin/manual/)
- [Nixpkgs Manual](https://nixos.org/manual/nixpkgs/stable/)

## License

This configuration is provided as-is for personal use. Feel free to fork and customize for your own needs.
