#!/usr/bin/env bash
#
# Create psoland user script
# Can be run independently or as part of bootstrap
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${RED}[ERROR]${NC} This script should NOT be run as root. Run as ubuntu user."
        exit 1
    fi
}

# Create psoland user
create_user() {
    log_info "Creating psoland user..."
    
    if id -u psoland &>/dev/null; then
        log_info "User psoland already exists"
        return 0
    fi
    
    # Create user
    sudo useradd -m -s /bin/bash -u 1001 psoland
    
    # Add to sudoers
    echo "psoland ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/psoland > /dev/null
    sudo chmod 0440 /etc/sudoers.d/psoland
    
    # Enable lingering for user services (syncthing, etc.)
    sudo mkdir -p /var/lib/systemd/linger
    sudo touch /var/lib/systemd/linger/psoland
    
    # Create XDG_RUNTIME_DIR
    sudo mkdir -p /run/user/1001
    sudo chown psoland:psoland /run/user/1001
    sudo chmod 700 /run/user/1001
    
    log_success "Created user psoland"
}

# Setup SSH access
setup_ssh() {
    log_info "Setting up SSH access for psoland..."
    
    # Copy SSH keys from ubuntu user
    if [[ -d ~/.ssh ]]; then
        sudo cp -r ~/.ssh /home/psoland/
        sudo chown -R psoland:psoland /home/psoland/.ssh
        sudo chmod 700 /home/psoland/.ssh
        sudo chmod 600 /home/psoland/.ssh/*
        log_success "Copied SSH keys from ubuntu user"
    else
        log_warning "No .ssh directory found for ubuntu user"
    fi
}

# Set password
set_password() {
    log_info "Setting password for psoland..."
    sudo passwd psoland
}

# Clone os-config for psoland
clone_config() {
    log_info "Setting up os-config for psoland..."
    
    if [[ -d /home/psoland/os-config ]]; then
        log_info "os-config already exists for psoland"
        return 0
    fi
    
    sudo cp -r ~/os-config /home/psoland/
    sudo chown -R psoland:psoland /home/psoland/os-config
    log_success "Copied os-config to /home/psoland/"
}

# Main
main() {
    check_not_root
    
    echo ""
    echo "========================================"
    echo "Create psoland User"
    echo "========================================"
    echo ""
    
    create_user
    setup_ssh
    clone_config
    
    echo ""
    echo -e "${GREEN}User psoland created successfully!${NC}"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Set password (optional, if not using SSH keys):"
    echo "   sudo passwd psoland"
    echo ""
    echo "2. Switch to psoland user:"
    echo "   sudo su - psoland"
    echo ""
    echo "3. Apply home-manager configuration:"
    echo "   cd ~/os-config"
    echo "   nix run home-manager/master -- switch --flake .#psoland-vm"
    echo ""
    echo "4. Connect via SSH:"
    echo "   ssh psoland@<tailscale-ip>"
    echo ""
}

main "$@"
