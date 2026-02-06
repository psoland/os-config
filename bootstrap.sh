#!/usr/bin/env bash
#
# Minimal bootstrap script for Ubuntu VMs
# Installs Nix and applies home-manager configuration
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap.sh | bash
#

set -euo pipefail

echo "=== os-config bootstrap ==="

# Check not running as root
if [[ $EUID -eq 0 ]]; then
    echo "Error: Do not run as root. Run as your regular user."
    exit 1
fi

# Install Nix using Determinate Systems installer
if ! command -v nix &> /dev/null; then
    echo "Installing Nix..."
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
    
    # Source nix for current session
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi
else
    echo "Nix already installed"
fi

# Clone config if not already present
if [[ ! -d ~/os-config ]]; then
    echo "Cloning os-config..."
    git clone https://github.com/psoland/os-config.git ~/os-config
fi

cd ~/os-config

# Apply home-manager configuration
echo "Applying home-manager configuration..."
nix run home-manager/master -- switch --flake .#psoland@oracle-vm

echo ""
echo "=== Bootstrap complete ==="
echo "Start a new shell or run: exec zsh"
