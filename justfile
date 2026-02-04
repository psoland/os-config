# Justfile for OS Configuration Management
# https://github.com/casey/just

# Default recipe - show available commands
default:
    @just --list

# ============================================================================
# Bootstrap Commands (run once on new machine)
# ============================================================================

# Bootstrap a fresh Ubuntu VM (run this first)
bootstrap:
    @echo "Starting Ubuntu bootstrap..."
    chmod +x ./bootstrap/ubuntu-bootstrap.sh
    ./bootstrap/ubuntu-bootstrap.sh

# Configure Syncthing to only listen on Tailscale (run after tailscale up)
configure-syncthing:
    @echo "Configuring Syncthing for Tailscale..."
    chmod +x ./bootstrap/configure-syncthing.sh
    ./bootstrap/configure-syncthing.sh

# Enable UFW firewall (run after confirming Tailscale SSH works)
enable-firewall:
    @echo "Enabling UFW firewall..."
    sudo ufw enable
    sudo ufw status verbose

# ============================================================================
# Home Manager Commands
# ============================================================================

# Apply Home Manager configuration
switch:
    @echo "Applying Home Manager configuration..."
    home-manager switch --flake ./home-manager#$(whoami)@ubuntu

# Apply Home Manager configuration for ARM
switch-arm:
    @echo "Applying Home Manager configuration for ARM..."
    home-manager switch --flake ./home-manager#$(whoami)@ubuntu-arm

# Build configuration without applying (check for errors)
check:
    @echo "Checking Home Manager configuration..."
    home-manager build --flake ./home-manager#$(whoami)@ubuntu

# Show what would change
diff:
    @echo "Showing what would change..."
    home-manager build --flake ./home-manager#$(whoami)@ubuntu
    nix store diff-closures ~/.local/state/nix/profiles/home-manager ./result

# ============================================================================
# Nix Commands
# ============================================================================

# Update all flake inputs
update:
    @echo "Updating flake inputs..."
    nix flake update ./home-manager

# Update a specific input (usage: just update-input nixpkgs)
update-input input:
    @echo "Updating {{input}}..."
    nix flake lock ./home-manager --update-input {{input}}

# Format all Nix files
fmt:
    @echo "Formatting Nix files..."
    find . -name "*.nix" -exec nixfmt {} \;

# Check Nix file formatting
fmt-check:
    @echo "Checking Nix file formatting..."
    find . -name "*.nix" -exec nixfmt --check {} \;

# Garbage collect old generations
gc:
    @echo "Running garbage collection..."
    nix-collect-garbage -d

# Garbage collect generations older than 7 days
gc-week:
    @echo "Removing generations older than 7 days..."
    nix-collect-garbage --delete-older-than 7d

# ============================================================================
# Development Shell
# ============================================================================

# Enter development shell
dev:
    @echo "Entering development shell..."
    nix develop ./home-manager

# ============================================================================
# Service Management
# ============================================================================

# Check status of all user services
services:
    systemctl --user status code-server syncthing || true

# Start code-server
start-code-server:
    systemctl --user start code-server

# Stop code-server
stop-code-server:
    systemctl --user stop code-server

# Restart code-server
restart-code-server:
    systemctl --user restart code-server

# View code-server logs
logs-code-server:
    journalctl --user -u code-server -f

# Install VS Code extensions for code-server
install-vscode-extensions:
    ~/.config/code-server/install-extensions.sh

# ============================================================================
# Utility Commands
# ============================================================================

# Show Tailscale status
tailscale-status:
    tailscale status

# Show UFW status
firewall-status:
    sudo ufw status verbose

# Install lazysql (manual installation)
install-lazysql:
    ~/.local/bin/install-lazysql

# Install opencode (manual installation)  
install-opencode:
    ~/.local/bin/install-opencode

# Show disk usage for Nix store
nix-size:
    @echo "Nix store size:"
    @du -sh /nix/store
    @echo ""
    @echo "Home Manager profile size:"
    @du -sh ~/.local/state/nix/profiles/home-manager* 2>/dev/null || echo "No home-manager profiles yet"

# ============================================================================
# Legacy (for existing myflake development shell)
# ============================================================================

# Go to devcontainer docker image
ssh_devcontainer:
    docker exec -it -w /workspaces/os-config os_config_devcontainer bash
