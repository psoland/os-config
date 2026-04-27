#!/bin/bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Error: This script is only meant for macOS."
  exit 1
fi

echo "Starting macOS bootstrap"

USERNAME="psoland"
HOME_MANAGER_FLAKE="psoland-mac"
DOTFILES_DIR="$HOME/.dotfiles"
REPO_URL="https://github.com/psoland/os-config.git"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

if [ "$(id -un)" != "$USERNAME" ]; then
  echo "Warning: expected user '$USERNAME' but running as '$(id -un)'."
  echo "Continuing anyway."
fi

# Do NOT run this whole script under sudo; individual steps will sudo as needed.
if [ "$(id -u)" -eq 0 ]; then
  echo "Error: do not run this script as root. Run as your normal user."
  exit 1
fi

# 1. Xcode Command Line Tools (provides git, clang, make, etc.)
if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing Xcode Command Line Tools (a GUI dialog will appear)..."
  xcode-select --install || true
  echo "Re-run this script once the CLT install completes."
  exit 0
else
  echo "Xcode Command Line Tools already installed."
fi

# 2. Homebrew (kept for GUI casks; not strictly required by Home Manager)
if ! command -v brew >/dev/null 2>&1; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Make brew available in this shell for the rest of the script
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# 3. Nix (Determinate Systems installer)
if ! command -v nix >/dev/null 2>&1; then
  echo "Installing Nix (Determinate Systems installer)..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | \
    sh -s -- install --no-confirm
  # Source the nix-daemon profile for this shell
  if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck disable=SC1091
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
else
  echo "Nix is already installed."
fi

# 4. Clone dotfiles repo if missing
if [ ! -d "$DOTFILES_DIR" ]; then
  echo "Cloning dotfiles repo to $DOTFILES_DIR..."
  git clone "$REPO_URL" "$DOTFILES_DIR"
else
  echo "Dotfiles repo already present at $DOTFILES_DIR."
fi

echo "$HOME_MANAGER_FLAKE" > "$DOTFILES_DIR/.hm-flake"

# 5. Backup files Home Manager would refuse to overwrite
backup_path() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    local rel="${target#$HOME/}"
    local dest="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    echo "  backing up $target -> $dest"
    mv "$target" "$dest"
  fi
}

echo "Backing up conflicting dotfiles to $BACKUP_DIR (if any)..."
backup_path "$HOME/.zshrc"
backup_path "$HOME/.zprofile"
backup_path "$HOME/.zshenv"
backup_path "$HOME/.tmux.conf"
backup_path "$HOME/.gitconfig"
# Only back up ~/.config/nvim if it isn't already our symlink
if [ -e "$HOME/.config/nvim" ] || [ -L "$HOME/.config/nvim" ]; then
  link_target="$(readlink "$HOME/.config/nvim" 2>/dev/null || true)"
  if [ "$link_target" != "$DOTFILES_DIR/config/nvim" ]; then
    backup_path "$HOME/.config/nvim"
  fi
fi

# 6. Build and activate Home Manager
echo "Building Home Manager configuration '$HOME_MANAGER_FLAKE'..."
cd "$DOTFILES_DIR"
nix build ".#homeConfigurations.${HOME_MANAGER_FLAKE}.activationPackage"
./result/activate

echo
echo "macOS bootstrap complete."
echo
echo "Next steps:"
echo "  1. Open a new terminal (so the new ~/.zshrc and ~/.zprofile are loaded)."
echo "  2. Verify: which nvim tmux starship git"
echo "  3. Backed-up originals are in: $BACKUP_DIR"
