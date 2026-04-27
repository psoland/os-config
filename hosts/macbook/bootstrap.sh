#!/bin/bash
set -euo pipefail

error() {
  echo "Error: $*" >&2
  exit 1
}

info() {
  echo "==> $*"
}

USERNAME="psoland"
HOME_MANAGER_FLAKE="psoland-mac"
REPO_URL="https://github.com/psoland/os-config.git"
DOTFILES_DIR="$HOME/.dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

OS="$(uname -s)"
ARCH="$(uname -m)"
CURRENT_USER="$(id -un)"

[ "$OS" = "Darwin" ] || error "this script is only meant for macOS."

case "$ARCH" in
  arm64 | aarch64) ;;
  *) error "unsupported architecture '$ARCH'. This bootstrap currently supports Apple Silicon only (arm64)." ;;
esac

# Do NOT run this whole script under sudo; individual steps will sudo as needed.
[ "$(id -u)" -ne 0 ] || error "do not run this script as root. Run as your normal user."

[ "$CURRENT_USER" = "$USERNAME" ] || error "expected user '$USERNAME', but running as '$CURRENT_USER'."
[ "$HOME" = "/Users/$USERNAME" ] || error "expected HOME to be '/Users/$USERNAME', got '$HOME'."

command -v curl >/dev/null 2>&1 || error "curl is required but not found."

info "Starting macOS bootstrap for $USERNAME ($ARCH)"

# 1. Xcode Command Line Tools (provides git, clang, make, etc.)
if ! xcode-select -p >/dev/null 2>&1; then
  info "Installing Xcode Command Line Tools (a GUI dialog will appear)..."
  xcode-select --install || true
  echo "Re-run this script once the CLT install completes."
  exit 0
fi

command -v git >/dev/null 2>&1 || error "git not found after CLT check. Ensure Xcode Command Line Tools are installed."

# 2. Homebrew (kept for GUI casks; not strictly required by Home Manager)
if ! command -v brew >/dev/null 2>&1; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Make brew available in this shell for the rest of the script
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

command -v brew >/dev/null 2>&1 || error "brew is not available after installation."

# 3. Nix (Determinate Systems installer)
if ! command -v nix >/dev/null 2>&1; then
  info "Installing Nix (Determinate Systems installer)..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix |
    sh -s -- install --no-confirm
fi

# Source Nix profile scripts for this shell
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
  # shellcheck disable=SC1091
  . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi
if [ -f /etc/profile.d/nix.sh ]; then
  # shellcheck disable=SC1091
  . /etc/profile.d/nix.sh
fi
export PATH="/nix/var/nix/profiles/default/bin:$PATH"

command -v nix >/dev/null 2>&1 || error "nix is not available after installation."

# 4. Clone dotfiles repo if missing
if [ ! -e "$DOTFILES_DIR" ]; then
  info "Cloning dotfiles repo to $DOTFILES_DIR..."
  git clone "$REPO_URL" "$DOTFILES_DIR"
else
  if ! git -C "$DOTFILES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    error "$DOTFILES_DIR exists but is not a git repository. Move it aside and re-run."
  fi
  info "Dotfiles repo already present at $DOTFILES_DIR."
fi

printf '%s\n' "$HOME_MANAGER_FLAKE" > "$DOTFILES_DIR/.hm-flake"

# 5. Backup files Home Manager would refuse to overwrite
had_backups=0
backup_path() {
  local target="$1"
  if [ -e "$target" ] || [ -L "$target" ]; then
    mkdir -p "$BACKUP_DIR"
    local rel="${target#$HOME/}"
    local dest="$BACKUP_DIR/$rel"
    mkdir -p "$(dirname "$dest")"
    echo "  backing up $target -> $dest"
    mv "$target" "$dest"
    had_backups=1
  fi
}

info "Backing up conflicting dotfiles to $BACKUP_DIR (if any)..."
backup_path "$HOME/.zshrc"
backup_path "$HOME/.zprofile"
backup_path "$HOME/.zshenv"
backup_path "$HOME/.tmux.conf"
backup_path "$HOME/.gitconfig"
backup_path "$HOME/.config/tmux"
backup_path "$HOME/.config/starship.toml"
backup_path "$HOME/.config/opencode"

# Only back up ~/.config/nvim if it isn't already our symlink
if [ -e "$HOME/.config/nvim" ] || [ -L "$HOME/.config/nvim" ]; then
  link_target="$(readlink "$HOME/.config/nvim" 2>/dev/null || true)"
  if [ "$link_target" != "$DOTFILES_DIR/config/nvim" ]; then
    backup_path "$HOME/.config/nvim"
  fi
fi

# 6. Build and activate Home Manager
info "Building Home Manager configuration '$HOME_MANAGER_FLAKE'..."
cd "$DOTFILES_DIR"
nix build ".#homeConfigurations.${HOME_MANAGER_FLAKE}.activationPackage"
./result/activate

echo
echo "macOS bootstrap complete."
echo
echo "Next steps:"
echo "  1. Open a new terminal (so the new ~/.zshrc and ~/.zprofile are loaded)."
echo "  2. Verify: which nvim tmux starship git"
if [ "$had_backups" -eq 1 ]; then
  echo "  3. Backed-up originals are in: $BACKUP_DIR"
else
  echo "  3. No conflicting files needed backup."
fi
