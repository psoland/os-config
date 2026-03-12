#!/bin/bash
set -e

BASE_URL="https://raw.githubusercontent.com/psoland/os-config/main"

OS_NAME="$(uname -s)"

if [ "$OS_NAME" = "Darwin" ]; then
  echo "Discovered macOS. Create a bootstrap script for macOS"
  exit 1

elif [ "$OS_NAME" = "Linux" ]; then
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]; then
      echo "Discovered Ubuntu/Debian. Downloading and running Ubuntu bootstrap"
      curl -sL "$BASE_URL/hosts/ubuntu/bootstrap.sh" | sudo bash
    else
      echo "Error: Does not support: '$ID'."
      exit 1
    fi
  else
    echo "Error: Could not identify the Linux distribution."
    exit 1
  fi
else
  echo "Error: Unknown operating system: $OS_NAME"
  exit 1
fi
