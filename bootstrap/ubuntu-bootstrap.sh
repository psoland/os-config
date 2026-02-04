#!/usr/bin/env bash
#
# Ubuntu VM Bootstrap Script
# This script sets up a fresh Ubuntu VM with system-level packages
# and prepares it for Home Manager configuration.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap/ubuntu-bootstrap.sh | bash
#
# Or clone the repo first and run:
#   ./bootstrap/ubuntu-bootstrap.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    log_error "This script should not be run as root. Run as your normal user (with sudo access)."
    exit 1
fi

# Get the username
USERNAME=$(whoami)
log_info "Setting up for user: $USERNAME"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        ARCH_NIX="x86_64-linux"
        ;;
    aarch64)
        ARCH_NIX="aarch64-linux"
        ;;
    *)
        log_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac
log_info "Detected architecture: $ARCH ($ARCH_NIX)"

# ============================================================================
# PHASE 1: System Package Updates
# ============================================================================
log_info "=== Phase 1: Updating system packages ==="

sudo apt-get update
sudo apt-get upgrade -y

# Install essential packages
sudo apt-get install -y \
    curl \
    wget \
    git \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common

log_success "System packages updated"

# ============================================================================
# PHASE 2: Install Tailscale
# ============================================================================
log_info "=== Phase 2: Installing Tailscale ==="

if command -v tailscale &> /dev/null; then
    log_warn "Tailscale already installed, skipping..."
else
    curl -fsSL https://tailscale.com/install.sh | sh
    log_success "Tailscale installed"
fi

# Start tailscale service
sudo systemctl enable --now tailscaled

log_info "Tailscale service enabled"
log_warn "IMPORTANT: Run 'sudo tailscale up --ssh' after this script completes to authenticate"

# ============================================================================
# PHASE 3: Install Docker
# ============================================================================
log_info "=== Phase 3: Installing Docker ==="

if command -v docker &> /dev/null; then
    log_warn "Docker already installed, skipping..."
else
    # Add Docker's official GPG key
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to Apt sources
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker "$USERNAME"

    log_success "Docker installed. You may need to log out and back in for group changes to take effect."
fi

# Enable Docker service
sudo systemctl enable --now docker

# ============================================================================
# PHASE 4: Install Mosh
# ============================================================================
log_info "=== Phase 4: Installing Mosh ==="

if command -v mosh &> /dev/null; then
    log_warn "Mosh already installed, skipping..."
else
    sudo apt-get install -y mosh
    log_success "Mosh installed"
fi

# ============================================================================
# PHASE 5: Install Syncthing
# ============================================================================
log_info "=== Phase 5: Installing Syncthing ==="

if command -v syncthing &> /dev/null; then
    log_warn "Syncthing already installed, skipping..."
else
    # Add the release PGP keys
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://syncthing.net/release-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/syncthing-archive-keyring.gpg

    # Add the stable channel to apt sources
    echo "deb [signed-by=/etc/apt/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | \
        sudo tee /etc/apt/sources.list.d/syncthing.list

    sudo apt-get update
    sudo apt-get install -y syncthing

    log_success "Syncthing installed"
fi

# Enable syncthing as a user service
systemctl --user enable syncthing.service
systemctl --user start syncthing.service || true

log_info "Syncthing user service enabled"
log_warn "Syncthing will be configured to use Tailscale IP after Tailscale is connected"

# ============================================================================
# PHASE 6: Configure UFW
# ============================================================================
log_info "=== Phase 6: Configuring UFW ==="

sudo apt-get install -y ufw

# Reset UFW to defaults
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH only on Tailscale interface
# Note: We keep port 22 open initially for setup, then restrict after Tailscale works
sudo ufw allow in on tailscale0 to any port 22 comment 'SSH via Tailscale'

# Allow mosh (UDP 60000-61000) only on Tailscale
sudo ufw allow in on tailscale0 proto udp to any port 60000:61000 comment 'Mosh via Tailscale'

# Syncthing - only on Tailscale
sudo ufw allow in on tailscale0 to any port 22000 comment 'Syncthing TCP via Tailscale'
sudo ufw allow in on tailscale0 proto udp to any port 22000 comment 'Syncthing UDP via Tailscale'
sudo ufw allow in on tailscale0 proto udp to any port 21027 comment 'Syncthing Discovery via Tailscale'

# code-server (default 8080) - only on Tailscale
sudo ufw allow in on tailscale0 to any port 8080 comment 'code-server via Tailscale'

log_success "UFW rules configured"
log_warn "UFW is NOT enabled yet. Enable with 'sudo ufw enable' after confirming Tailscale SSH works"

# Show current rules
sudo ufw status verbose

# ============================================================================
# PHASE 7: Install Nix
# ============================================================================
log_info "=== Phase 7: Installing Nix ==="

if command -v nix &> /dev/null; then
    log_warn "Nix already installed, skipping..."
else
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

    # Source nix
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    log_success "Nix installed"
fi

# ============================================================================
# PHASE 8: Clone os-config repo (if not already in it)
# ============================================================================
log_info "=== Phase 8: Setting up os-config repository ==="

OS_CONFIG_DIR="$HOME/os-config"

if [[ -d "$OS_CONFIG_DIR" ]]; then
    log_warn "os-config directory already exists at $OS_CONFIG_DIR"
else
    if [[ -d ".git" ]] && grep -q "os-config" .git/config 2>/dev/null; then
        log_info "Already in os-config repository"
        OS_CONFIG_DIR="$(pwd)"
    else
        log_info "Cloning os-config repository..."
        git clone https://github.com/psoland/os-config.git "$OS_CONFIG_DIR"
    fi
fi

log_success "os-config repository ready at $OS_CONFIG_DIR"

# ============================================================================
# PHASE 9: Apply Home Manager Configuration
# ============================================================================
log_info "=== Phase 9: Applying Home Manager Configuration ==="

# Need to source nix again in case it was just installed
if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

cd "$OS_CONFIG_DIR/home-manager"

# Determine the hostname for the home-manager configuration
HOSTNAME=$(hostname)
HM_CONFIG="${USERNAME}@${HOSTNAME}"

log_info "Looking for Home Manager configuration: $HM_CONFIG"

# Check if the specific config exists, otherwise use default
if nix flake show --json 2>/dev/null | grep -q "\"$HM_CONFIG\""; then
    log_info "Found configuration for $HM_CONFIG"
else
    log_warn "No specific configuration for $HM_CONFIG, using ${USERNAME}@ubuntu"
    HM_CONFIG="${USERNAME}@ubuntu"
fi

# Apply Home Manager configuration
log_info "Applying Home Manager configuration..."
nix run home-manager/master -- switch --flake ".#$HM_CONFIG"

log_success "Home Manager configuration applied"

# ============================================================================
# PHASE 10: Post-setup Configuration
# ============================================================================
log_info "=== Phase 10: Post-setup Configuration ==="

# Change default shell to zsh if not already
ZSH_PATH=$(which zsh || echo "/home/$USERNAME/.nix-profile/bin/zsh")
if [[ -x "$ZSH_PATH" ]]; then
    if [[ "$SHELL" != *"zsh"* ]]; then
        log_info "Changing default shell to zsh..."
        # Add zsh to /etc/shells if not present
        if ! grep -q "$ZSH_PATH" /etc/shells; then
            echo "$ZSH_PATH" | sudo tee -a /etc/shells
        fi
        sudo chsh -s "$ZSH_PATH" "$USERNAME"
        log_success "Default shell changed to zsh"
    else
        log_info "Shell is already zsh"
    fi
else
    log_warn "zsh not found, shell not changed"
fi

# ============================================================================
# Summary and Next Steps
# ============================================================================
echo ""
echo "============================================================================"
echo -e "${GREEN}Bootstrap Complete!${NC}"
echo "============================================================================"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Authenticate Tailscale (required for secure remote access):"
echo "   ${YELLOW}sudo tailscale up --ssh${NC}"
echo ""
echo "2. From another machine on your Tailscale network, test SSH:"
echo "   ${YELLOW}ssh $USERNAME@$(hostname)${NC}  # or use Tailscale hostname/IP"
echo ""
echo "3. Once Tailscale SSH is confirmed working, enable UFW:"
echo "   ${YELLOW}sudo ufw enable${NC}"
echo ""
echo "4. Configure Syncthing to use Tailscale IP only:"
echo "   ${YELLOW}$OS_CONFIG_DIR/bootstrap/configure-syncthing.sh${NC}"
echo ""
echo "5. Log out and back in for shell changes to take effect, or run:"
echo "   ${YELLOW}exec zsh${NC}"
echo ""
echo "6. If you need to re-apply Home Manager configuration:"
echo "   ${YELLOW}cd $OS_CONFIG_DIR && just switch${NC}"
echo ""
echo "============================================================================"
