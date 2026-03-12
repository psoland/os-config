#!/bin/bash
set -e

DOTFILES_DIR="$HOME/.dotfiles"
REPO_URL="https://github.com/psoland/os-config.git"

echo "Downloading dofiles repo"

# Check if git installed, if not, try to isntall it (for Ubuntu)
if ! command -v git &>/dev/null; then
  echo "Git is missing, trying to install.."
  if command -v git &>/dev/null; then
    sudo apt-get update && sudo apt-get install -y git
    else:
    echo "Git is not installed and package manager was not recognized"
    exit 1
  fi
fi

# Clone the repo if it doesn't exist already
if [ ! -d "$DOTFILES_DIR" ]; then
  git clone "$REPO_URL" "$DOTFILES_DIR"
else
  echo "Update existing dotfiles"
  git -C "$DOTFILES_DIR" pull
fi

# Run the local bootstrap script
echo "Running bootstrap"
cd "$DOTFILES_DIR"
bash ./bootstrap.sh
