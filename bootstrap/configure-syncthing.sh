#!/usr/bin/env bash
#
# Configure Syncthing to only listen on Tailscale interface
#
# This script modifies the Syncthing configuration to bind only to the
# Tailscale IP address, ensuring it's only accessible via Tailscale.
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if Tailscale is connected
if ! tailscale status &> /dev/null; then
    log_error "Tailscale is not connected. Run 'sudo tailscale up --ssh' first."
    exit 1
fi

# Get Tailscale IP
TAILSCALE_IP=$(tailscale ip -4)
if [[ -z "$TAILSCALE_IP" ]]; then
    log_error "Could not get Tailscale IP address"
    exit 1
fi

log_info "Tailscale IP: $TAILSCALE_IP"

# Syncthing config file location
SYNCTHING_CONFIG="$HOME/.local/state/syncthing/config.xml"

# Alternative locations
if [[ ! -f "$SYNCTHING_CONFIG" ]]; then
    SYNCTHING_CONFIG="$HOME/.config/syncthing/config.xml"
fi

if [[ ! -f "$SYNCTHING_CONFIG" ]]; then
    log_error "Syncthing config not found. Make sure Syncthing has been started at least once."
    log_info "Try running: systemctl --user start syncthing"
    exit 1
fi

log_info "Found Syncthing config at: $SYNCTHING_CONFIG"

# Stop syncthing before modifying config
log_info "Stopping Syncthing..."
systemctl --user stop syncthing.service || true
sleep 2

# Backup the config
cp "$SYNCTHING_CONFIG" "${SYNCTHING_CONFIG}.backup.$(date +%Y%m%d%H%M%S)"
log_info "Config backed up"

# Update the GUI address to only listen on Tailscale IP
# Default is usually <address>127.0.0.1:8384</address> or <address>0.0.0.0:8384</address>
sed -i "s|<address>[^<]*:8384</address>|<address>${TAILSCALE_IP}:8384</address>|g" "$SYNCTHING_CONFIG"

# Update the sync protocol listener to only use Tailscale IP
# Default is usually <listenAddress>default</listenAddress> or <listenAddress>tcp://0.0.0.0:22000</listenAddress>
# We want to bind to the Tailscale IP
sed -i "s|<listenAddress>default</listenAddress>|<listenAddress>tcp://${TAILSCALE_IP}:22000</listenAddress>\n            <listenAddress>quic://${TAILSCALE_IP}:22000</listenAddress>|g" "$SYNCTHING_CONFIG"
sed -i "s|<listenAddress>tcp://0.0.0.0:22000</listenAddress>|<listenAddress>tcp://${TAILSCALE_IP}:22000</listenAddress>|g" "$SYNCTHING_CONFIG"
sed -i "s|<listenAddress>quic://0.0.0.0:22000</listenAddress>|<listenAddress>quic://${TAILSCALE_IP}:22000</listenAddress>|g" "$SYNCTHING_CONFIG"

log_success "Syncthing config updated to use Tailscale IP: $TAILSCALE_IP"

# Restart syncthing
log_info "Starting Syncthing..."
systemctl --user start syncthing.service

log_success "Syncthing restarted"
echo ""
echo "Syncthing Web UI is now accessible at:"
echo "  ${GREEN}http://${TAILSCALE_IP}:8384${NC}"
echo ""
echo "You can access this from any device on your Tailscale network."
