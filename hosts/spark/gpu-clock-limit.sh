#!/bin/bash
# Personal Spark only. Run explicitly with sudo, never from Home Manager activation.
set -euo pipefail

usage() {
  echo "Usage: sudo bash $0 [install [MAX_MHZ] | remove]"
  echo "Default: install a persistent 2200 MHz GPU clock cap."
}

ACTION="${1:-install}"
MAX_MHZ="${2:-2200}"
case "$ACTION" in
  -h|--help) usage; exit 0 ;;
  install)
    if [ "$#" -gt 2 ] || ! [[ "$MAX_MHZ" =~ ^[1-9][0-9]{0,4}$ ]] || [ "$MAX_MHZ" -gt 10000 ]; then
      usage >&2
      exit 2
    fi
    ;;
  remove)
    if [ "$#" -gt 1 ]; then usage >&2; exit 2; fi
    ;;
  *) usage >&2; exit 2 ;;
esac

if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ]; then
  echo "Error: Run this script as root on the personal Spark (Ubuntu)." >&2
  exit 1
fi

SERVICE="spark-gpu-clock-limit.service"
UNIT_PATH="/etc/systemd/system/$SERVICE"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ "$ACTION" = remove ]; then
  if [ -e "$UNIT_PATH" ]; then
    systemctl disable --now "$SERVICE"
  fi
  /usr/bin/nvidia-smi -rgc
  rm -f -- "$UNIT_PATH"
  systemctl daemon-reload
  echo "Removed GPU clock cap; NVIDIA default clocks restored."
  exit 0
fi

if ! /usr/bin/nvidia-smi --query-gpu=name --format=csv,noheader | grep -qi 'GB10'; then
  echo "Error: A working NVIDIA GB10 GPU is required; no service installed." >&2
  exit 1
fi

TMP_UNIT="$(mktemp)"
trap 'rm -f -- "$TMP_UNIT"' EXIT
sed "s/@MAX_MHZ@/$MAX_MHZ/g" "$SCRIPT_DIR/$SERVICE" >"$TMP_UNIT"

# Check driver support before installing or overwriting a persistent service.
/usr/bin/nvidia-smi -lgc "0,$MAX_MHZ"
install -m 0644 -- "$TMP_UNIT" "$UNIT_PATH"
systemctl daemon-reload
systemctl enable "$SERVICE"
systemctl restart "$SERVICE"
echo "GPU clock cap installed: 0,$MAX_MHZ MHz (applied now and at boot)."
