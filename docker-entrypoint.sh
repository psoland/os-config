#!/bin/bash
# Entrypoint script for Nix container
# Starts the Nix daemon and sets up the environment

set -e

# Start the Nix daemon in the background as root
echo "Starting Nix daemon..."
sudo /nix/var/nix/profiles/default/bin/nix-daemon &

# Wait a moment for the daemon to initialize
sleep 2

# Source the Nix profile to set up environment variables
if [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

# Print confirmation
echo "Nix daemon started successfully"
echo "Environment ready. Working directory: $(pwd)"
echo ""

# Execute the command passed to docker run, or default to bash
exec "$@"
