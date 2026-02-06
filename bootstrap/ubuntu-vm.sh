#!/usr/bin/env bash
#
# Ubuntu VM Bootstrap Script
# Prepares a fresh Ubuntu VM for Nix-based configuration
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/bootstrap/ubuntu-vm.sh | bash
#   # OR
#   ./bootstrap/ubuntu-vm.sh
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should NOT be run as root. Run as your regular user."
        exit 1
    fi
}

# Check Ubuntu version
check_ubuntu() {
    if ! command -v lsb_release &> /dev/null; then
        log_error "lsb_release not found. Is this Ubuntu?"
        exit 1
    fi

    local version
    version=$(lsb_release -rs)
    local major_version
    major_version=$(echo "$version" | cut -d. -f1)

    if [[ $major_version -lt 22 ]]; then
        log_error "Ubuntu 22.04 or later required. Found: $version"
        exit 1
    fi

    log_info "Detected Ubuntu $version"
}

# Update system packages
update_system() {
    log_info "Updating system packages..."
    sudo apt-get update
    sudo apt-get upgrade -y
    log_success "System packages updated"
}

# Install essential apt packages
install_essentials() {
    log_info "Installing essential packages..."
    sudo apt-get install -y \
        git \
        curl \
        wget \
        build-essential \
        ca-certificates \
        gnupg \
        lsb-release \
        xz-utils

    log_success "Essential packages installed"
}

# Install UFW (Uncomplicated Firewall)
install_ufw() {
    log_info "Installing and configuring UFW..."
    sudo apt-get install -y ufw

    # Don't enable UFW yet - we need Tailscale first
    # Just set up the default rules
    sudo ufw default deny incoming
    sudo ufw default allow outgoing

    # Temporarily allow SSH from anywhere (will be locked down after Tailscale)
    sudo ufw allow ssh

    log_warning "UFW installed but NOT enabled yet. Will be enabled after Tailscale setup."
    log_success "UFW installed and configured"
}

# Install Tailscale
install_tailscale() {
    log_info "Installing Tailscale..."

    # Add Tailscale's GPG key and repository
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs).tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list

    sudo apt-get update
    sudo apt-get install -y tailscale

    log_success "Tailscale installed"
    log_warning "Run 'sudo tailscale up' after this script to authenticate"
}

# Install Docker
install_docker() {
    log_info "Installing Docker..."

    # Check if Docker is already installed
    if command -v docker &> /dev/null; then
        log_info "Docker is already installed"
        return
    fi

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

    # Add current user to docker group
    sudo usermod -aG docker "$USER"

    log_success "Docker installed"
    log_warning "Log out and back in for docker group membership to take effect"
}

# Install Mosh
install_mosh() {
    log_info "Installing Mosh..."
    sudo apt-get install -y mosh
    log_success "Mosh installed"
}

# Install Nix using Determinate Systems installer
install_nix() {
    log_info "Installing Nix..."

    # Check if Nix is already installed
    if command -v nix &> /dev/null; then
        log_info "Nix is already installed"
        nix --version
        return
    fi

    # Use Determinate Systems installer (better flake support)
    curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm

    # Source nix
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        # shellcheck source=/dev/null
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    fi

    log_success "Nix installed"
}

# Clone the os-config repository
clone_repo() {
    local repo_url="https://github.com/psoland/os-config.git"
    local target_dir="$HOME/os-config"

    log_info "Setting up os-config repository..."

    if [[ -d "$target_dir" ]]; then
        log_info "Repository already exists at $target_dir"
        cd "$target_dir"
        git pull
    else
        git clone "$repo_url" "$target_dir"
    fi

    log_success "Repository ready at $target_dir"
}

# Create UFW lockdown script for after Tailscale setup
create_lockdown_script() {
    local script_path="$HOME/os-config/bootstrap/lockdown-ssh.sh"

    log_info "Creating SSH lockdown script..."

    cat > "$script_path" << 'LOCKDOWN_EOF'
#!/usr/bin/env bash
#
# Lock down SSH to Tailscale only
# Run this AFTER confirming Tailscale is working!
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}WARNING: This will restrict SSH to Tailscale network only!${NC}"
echo ""

# Check Tailscale status
if ! tailscale status &> /dev/null; then
    echo -e "${RED}ERROR: Tailscale is not running or not connected${NC}"
    echo "Run 'sudo tailscale up' first and verify connectivity"
    exit 1
fi

echo "Current Tailscale status:"
tailscale status
echo ""

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
echo -e "Your Tailscale IP: ${GREEN}$TAILSCALE_IP${NC}"
echo ""

read -p "Have you verified you can SSH via Tailscale IP ($TAILSCALE_IP)? [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted. Please test SSH via Tailscale first."
    exit 1
fi

echo ""
echo "Configuring UFW rules..."

# Reset UFW to clean state
sudo ufw --force reset

# Set defaults
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH only from Tailscale subnet (100.64.0.0/10)
sudo ufw allow from 100.64.0.0/10 to any port 22 proto tcp comment 'SSH via Tailscale'

# Allow Mosh from Tailscale subnet
sudo ufw allow from 100.64.0.0/10 to any port 60000:61000 proto udp comment 'Mosh via Tailscale'

# Enable UFW
sudo ufw --force enable

echo ""
echo -e "${GREEN}UFW configured! Current rules:${NC}"
sudo ufw status verbose

echo ""
echo -e "${GREEN}SSH is now restricted to Tailscale network only.${NC}"
echo "Connect via: ssh $USER@$TAILSCALE_IP"
LOCKDOWN_EOF

    chmod +x "$script_path"
    log_success "Lockdown script created at $script_path"
}

# Create psoland user with SSH access
create_psoland_user() {
    log_info "Creating psoland user with SSH access..."
    
    if id -u psoland &>/dev/null; then
        log_info "User psoland already exists, skipping creation"
        return
    fi
    
    # Create user
    sudo useradd -m -s /bin/bash -u 1001 psoland
    
    # Add to sudoers
    echo "psoland ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/psoland
    sudo chmod 0440 /etc/sudoers.d/psoland
    
    # Enable lingering for user services
    sudo mkdir -p /var/lib/systemd/linger
    sudo touch /var/lib/systemd/linger/psoland
    
    # Create XDG_RUNTIME_DIR
    sudo mkdir -p /run/user/1001
    sudo chown psoland:psoland /run/user/1001
    sudo chmod 700 /run/user/1001
    
    log_success "Created user psoland"
    log_info "NOTE: Set a password for psoland with: sudo passwd psoland"
    log_info "Or copy SSH keys from ubuntu user: sudo cp -r /home/ubuntu/.ssh /home/psoland/ && sudo chown -R psoland:psoland /home/psoland/.ssh"
}

# Print next steps
print_next_steps() {
    echo ""
    echo "========================================"
    echo -e "${GREEN}Bootstrap Complete!${NC}"
    echo "========================================"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Start a new shell or run:"
    echo "   source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    echo ""
    echo "2. Authenticate Tailscale:"
    echo "   sudo tailscale up"
    echo ""
    echo "3. Verify Tailscale connectivity from another device:"
    echo "   ssh $USER@\$(tailscale ip -4)"
    echo ""
    echo "4. (Optional) Create psoland user for SSH access:"
    echo "   ~/os-config/bootstrap/create-psoland-user.sh"
    echo "   sudo passwd psoland  # Set password"
    echo ""
    echo "5. Apply Home Manager configuration:"
    echo "   cd ~/os-config"
    echo "   nix run home-manager/master -- switch --flake .#ubuntu-vm"
    echo "   # OR for psoland user:"
    echo "   # nix run home-manager/master -- switch --flake .#psoland-vm"
    echo ""
    echo "6. Set ZSH as default shell:"
    echo "   chsh -s \$(which zsh)"
    echo ""
    echo "7. Lock down SSH to Tailscale only (AFTER verifying Tailscale works):"
    echo "   ~/os-config/bootstrap/lockdown-ssh.sh"
    echo ""
    echo "8. Log out and back in to apply all changes"
    echo ""
    echo -e "${YELLOW}IMPORTANT: Don't run the lockdown script until you've verified${NC}"
    echo -e "${YELLOW}SSH access works via Tailscale IP!${NC}"
    echo ""
}

# Main function
main() {
    echo ""
    echo "========================================"
    echo "Ubuntu VM Bootstrap Script"
    echo "========================================"
    echo ""

    check_not_root
    check_ubuntu
    update_system
    install_essentials
    install_ufw
    install_tailscale
    install_docker
    install_mosh
    install_nix
    clone_repo
    create_lockdown_script
    create_psoland_user
    print_next_steps
}

# Run main
main "$@"
