#!/bin/bash
set -e

echo "Starting ubuntu bootstrap"

USERNAME="psoland"
ARCH="$(uname -m)"

case "$ARCH" in
  x86_64)
    HOME_MANAGER_FLAKE="psoland-vm"
    ;;
  aarch64 | arm64)
    HOME_MANAGER_FLAKE="psoland-vm-arm"
    ;;
  *)
    echo "Warning: Unknown architecture '$ARCH'. Falling back to psoland-vm."
    HOME_MANAGER_FLAKE="psoland-vm"
    ;;
esac

# 1. Update system and install system tools
apt-get update && apt-get upgrade -y
apt-get install -y ufw zsh git

# 2. Install Tailscale
echo "Installing Tailscale.."
curl -fsSL https://tailscale.com/install.sh | sh

# 3. Install Docker (official convenience script)
echo "Installing Docker.."
curl -fsSL https://get.docker.com | sh

# 4. Create the user with Zsh as standard
if id "$USERNAME" &>/dev/null; then
  echo "Username '$USERNAME' already exists."
  usermod -s /usr/bin/zsh "$USERNAME"
  usermod -aG docker "$USERNAME"
else
  echo "Creating user '$USERNAME' with Zsh.."
  # Create the user with home area (-m) and Zsh as standard shell (-s)
  useradd -m -s /usr/bin/zsh "$USERNAME"

  # Add the user to sudo and docker group
  usermod -aG sudo,docker "$USERNAME"

  # Let the user run sudo without password
  echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >"/etc/sudoers.d/90-$USERNAME"
  chmod 0440 "/etc/sudoers.d/90-$USERNAME"
fi

# 5. Copy SSH-keys from 'ubuntu' user
if [ -d "/home/ubuntu/.ssh" ]; then
  echo "Copying SSH-keys to '$USERNAME'.."
  mkdir -p "/home/$USERNAME/.ssh"
  cp /home/ubuntu/.ssh/authorized_keys "/home/$USERNAME/.ssh/"

  # Give user access to the folders
  chown -R "$USERNAME":"$USERNAME" "/home/$USERNAME/.ssh"
  chmod 700 "/home/$USERNAME/.ssh"
  chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
fi

# 6. Set up firewall (UFW)
echo "Configuring firewall.."
ufw allow OpenSSH
ufw allow 60000:61000/udp #For Mosh
# ufw --force enable #Uncomment this when you are certain SSH works

# 7. Clone the dotfiles-repo for the user
DOTFILES_DIR="/home/$USERNAME/.dotfiles"
REPO_URL="https://github.com/psoland/os-config.git"

if [ ! -d "$DOTFILES_DIR" ]; then
  echo "Cloning dotfiles-repo for '$USERNAME'.."
  # 'su - USERNAME -c' runs the command as USERNAME
  su - "$USERNAME" -c "git clone $REPO_URL $DOTFILES_DIR"
else
  echo "Dotfiles-repo is already cloned"
fi

if ! command -v nix &>/dev/null; then
  echo "Installing Nix.."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --no-confirm
else
  echo "Nix is already installed"
fi

# 8. Apply Home Manager configuration for the created user
echo "Applying Home Manager config '$HOME_MANAGER_FLAKE' for '$USERNAME'.."
su - "$USERNAME" -c "HOME_MANAGER_FLAKE=\"$HOME_MANAGER_FLAKE\" DOTFILES_DIR=\"$DOTFILES_DIR\" bash -lc '. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh 2>/dev/null || true; . /etc/profile.d/nix.sh 2>/dev/null || true; export PATH=/nix/var/nix/profiles/default/bin:\$PATH; cd \"\$DOTFILES_DIR\"; nix run home-manager/master -- switch --flake .#\$HOME_MANAGER_FLAKE'"

echo "Ubuntu bootstrap is complete"
echo "Next (manual): sudo tailscale up"
echo "Then sign out and sign in as '$USERNAME'"
