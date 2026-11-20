#!/bin/bash
# Installs/removes the private *.mujo.no tailnet proxy as a system service.
# Explicit root use only; never run by Home Manager activation.
set -euo pipefail

usage() {
  cat >&2 <<EOF
Usage:
  sudo bash $0 install /absolute/path/to/built-tailnet-proxy
  sudo bash $0 remove
EOF
  exit 2
}

if [ "$(uname -s)" != Linux ] || [ "$(id -u)" -ne 0 ]; then
  echo "Run as root on the intended Linux Tailscale host." >&2
  exit 1
fi

unit=mujo-tailnet-caddy.service
unit_path="/etc/systemd/system/$unit"
marker='# Managed by dotfiles/packages/tailnet-proxy.nix'
config_dir=/etc/mujo-tailnet
credential="$config_dir/cloudflare-token"
gc_root=/nix/var/nix/gcroots/mujo-tailnet-proxy

check_owned_unit() {
  if [ -L "$unit_path" ] || { [ -e "$unit_path" ] && ! grep -Fxq "$marker" "$unit_path"; }; then
    echo "Existing $unit_path is not owned by this setup; refusing to touch it." >&2
    exit 1
  fi
}

check_gc_root() {
  if [ -e "$gc_root" ] && [ ! -L "$gc_root" ]; then
    echo "Unexpected non-symlink GC root: $gc_root" >&2
    exit 1
  fi
  if [ -L "$gc_root" ]; then
    case "$(readlink -- "$gc_root")" in
      /nix/store/*-mujo-tailnet-proxy) ;;
      *) echo "GC root belongs to another setup; refusing replacement." >&2; exit 1 ;;
    esac
  fi
}

install_proxy() {
  local bundle routes_dir
  bundle="$(readlink -f -- "$1")"
  case "$bundle" in
    /nix/store/*-mujo-tailnet-proxy) ;;
    *) echo "Expected a Nix-built mujo-tailnet-proxy bundle." >&2; exit 1 ;;
  esac
  for file in Caddyfile caddy tailscale-ip routes-dir "$unit"; do
    test -f "$bundle/$file" || { echo "Incomplete bundle: $file" >&2; exit 1; }
  done
  routes_dir="$(cat "$bundle/routes-dir")"

  if [ ! -f "$credential" ] || [ -L "$credential" ] || [ ! -s "$credential" ] \
    || [ "$(stat -c '%u:%a' "$credential")" != 0:600 ]; then
    echo "First provision $credential as a nonempty root-owned regular file, mode 0600." >&2
    exit 1
  fi
  if [ "$(tailscale ip -4)" != "$(cat "$bundle/tailscale-ip")" ]; then
    echo "This host's Tailscale IP does not match the bundle; refusing installation." >&2
    exit 1
  fi
  # Tailscale Serve/Funnel intercept tailnet port 443 inside tailscaled, which
  # `ss` cannot see. Caddy would never receive those connections.
  local serve
  if ! serve="$(tailscale serve status --json)"; then
    echo "Could not inspect Tailscale Serve; refusing installation." >&2
    exit 1
  fi
  if printf '%s' "$serve" | grep -q '"443"'; then
    echo "Tailscale Serve/Funnel already uses port 443; remove that route first." >&2
    exit 1
  fi
  if ! systemctl is-active --quiet "$unit"; then
    local listeners
    if ! listeners="$(ss -H -ltn 'sport = :443')"; then
      echo "Could not inspect TCP port 443; refusing installation." >&2
      exit 1
    fi
    if [ -n "$listeners" ]; then
      echo "TCP port 443 is already in use; resolve ownership before installing." >&2
      exit 1
    fi
  fi
  check_gc_root
  check_owned_unit

  # No certificate issuance or DNS mutation occurs before the start below.
  systemd-analyze verify "$bundle/$unit"
  install -d -m 0755 -- "$config_dir" "$routes_dir"
  ln -sfnT -- "$bundle" "$gc_root"
  install -m 0644 -- "$bundle/$unit" "$unit_path"
  systemctl daemon-reload
  systemctl enable "$unit"
  systemctl restart "$unit"
  systemctl is-active --quiet "$unit"
  echo "Installed $unit. Add services with: tailnetctl add <name> <port>"
}

remove_proxy() {
  check_owned_unit
  check_gc_root
  if [ -e "$unit_path" ]; then
    systemctl disable --now "$unit"
    rm -f -- "$unit_path"
    systemctl daemon-reload
  fi
  rm -f -- "$gc_root"
  echo "Removed $unit. Kept $config_dir (token, routes) and certificate state."
}

case "${1:-}" in
  install) [ "$#" -eq 2 ] || usage; install_proxy "$2" ;;
  remove) [ "$#" -eq 1 ] || usage; remove_proxy ;;
  *) usage ;;
esac
