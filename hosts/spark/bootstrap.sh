#!/bin/bash
set -e

if [ "$(uname -s)" != "Linux" ]; then
  echo "Error: This script is only meant for Linux (Spark DGX)."
  exit 1

fi

echo "Starting bootstrap for DGX-spark"

USERNAME="psoland"
HOME_MANAGER_FLAKE="spark"

# 1. Update system and install system tools
apt-get update && apt-get upgrade -y
apt-get install -y ufw zsh git

# 2. Install Tailscale
if ! command -v tailscale &>/dev/null; then
  echo "Installing Tailscale.."
  curl -fsSL https://tailscale.com/install.sh | sh
else
  echo "Tailscale is already installed"
fi

# 3. Install Docker (official convenience script)
if ! command -v docker &>/dev/null; then
  echo "Installing Docker.."
  curl -fsSL https://get.docker.com | sh
else
  echo "Docker is already installed"
fi

# 4. User configs
if id "$USERNAME" &>/dev/null; then
  # Change standard shell to zsh
  usermod -s /usr/bin/zsh "$USERNAME"
  # Add user to docker group
  usermod -aG docker "$USERNAME"
else
  echo "Error: User '$USERNAME' does not exist. Please create it first via GUI or manually."
  exit 1
fi

# 5. Set up firewall (UFW)
echo "Configuring firewall.."
ufw allow 60000:61000/udp #For Mosh
ufw allow in on tailscale0 to any port 22
# ufw --force enable #Uncomment this when you are certain SSH works

# 6. Clone the dotfiles-repo for the user
DOTFILES_DIR="/home/$USERNAME/.dotfiles"
REPO_URL="https://github.com/psoland/os-config.git"

if [ ! -d "$DOTFILES_DIR" ]; then
  echo "Cloning dotfiles-repo for '$USERNAME'.."
  # 'su - USERNAME -c' runs the command as USERNAME
  su - "$USERNAME" -c "git clone $REPO_URL $DOTFILES_DIR"
else
  echo "Dotfiles-repo is already cloned"
fi

echo "$HOME_MANAGER_FLAKE" >"$DOTFILES_DIR/.hm-flake"
chown "$USERNAME":"$USERNAME" "$DOTFILES_DIR/.hm-flake"

# 7. Install Nix
if ! command -v nix &>/dev/null; then
  echo "Installing Nix.."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --no-confirm
else
  echo "Nix is already installed"
fi

# 8. Apply Home Manager configuration for the created user (pinned by flake.lock)
echo "Applying Home Manager config '$HOME_MANAGER_FLAKE' for '$USERNAME'.."
su - "$USERNAME" -c "HOME_MANAGER_FLAKE=\"$HOME_MANAGER_FLAKE\" DOTFILES_DIR=\"$DOTFILES_DIR\" bash -lc '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true; . /etc/profile.d/nix.sh 2>/dev/null || true; export PATH=/nix/var/nix/profiles/default/bin:\$PATH; cd \"\$DOTFILES_DIR\"; nix build .#homeConfigurations.\$HOME_MANAGER_FLAKE.activationPackage; ./result/activate'"

echo "==================================="
echo "Spark bootstrap is complete!"
echo "Next steps (manual):"
echo "1. Run: sudo tailscale up"
echo "2. Log out completely and log back in as '$USERNAME' for Zsh and Docker groups to take effect."
echo "==================================="
