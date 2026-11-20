# shellcheck shell=bash
# Manage private https://<name>.<zone> routes on the tailnet proxy.
set -euo pipefail

read -r -a zones <<<"${TAILNET_ZONES:?TAILNET_ZONES is not set}"
[ "${#zones[@]}" -gt 0 ] || { echo "tailnetctl: TAILNET_ZONES is empty" >&2; exit 1; }
default_zone="${zones[0]}"
routes="${TAILNET_ROUTES_DIR:?TAILNET_ROUTES_DIR is not set}"
unit="${TAILNET_UNIT:-mujo-tailnet-caddy.service}"

usage() {
  cat >&2 <<EOF
Usage: tailnetctl <command> [args]

Commands:
  add <name|host> <port>   Serve https://<host> from 127.0.0.1:<port>
  rm <name|host>           Remove a service route
  ls                       List service routes and whether their port is listening
  status                   Show the proxy's systemd status

A bare <name> uses $default_zone (agents -> agents.$default_zone).
A full <host> must be one label under a configured domain: ${zones[*]}

Changes are validated, written to $routes with sudo, and reloaded live.
EOF
  exit 2
}

die() {
  echo "tailnetctl: $*" >&2
  exit 1
}

require_installed() {
  [ -d "$routes" ] || die "$routes does not exist; install the proxy first (README: Private tailnet services)."
}

# Print the full hostname for a bare name or a <label>.<configured zone>.
resolve_host() {
  local input="$1" label zone candidate
  if [[ "$input" == *.* ]]; then
    label="${input%%.*}"
    zone="${input#*.}"
    for candidate in "${zones[@]}"; do
      [ "$zone" = "$candidate" ] && break
      candidate=""
    done
    [ -n "$candidate" ] || die "'$input' is not under a configured domain (${zones[*]})."
  else
    label="$input"
    zone="$default_zone"
  fi
  [[ "$label" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] \
    || die "invalid name '$label': use lowercase letters, digits and inner hyphens (max 63)."
  echo "$label.$zone"
}

check_port() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$1" -le 65535 ] || die "invalid port '$1'."
}

listening() {
  [ -n "$(ss -H -ltn "sport = :$1" 2>/dev/null)" ]
}

render() {
  local host="$1" port="$2" matcher="${1//./_}"
  cat <<EOF
# Managed by tailnetctl
@$matcher host $host
handle @$matcher {
	reverse_proxy 127.0.0.1:$port
}
EOF
}

# Validate the candidate set of route files exactly as the proxy imports them.
validate() {
  local dir="$1" sites="" zone
  for zone in "${zones[@]}"; do
    sites+="${sites:+, }http://*.$zone"
  done
  cat >"$dir/Caddyfile" <<EOF
{
	admin off
}

$sites {
	import $dir/routes/*.caddy

	handle {
		respond 404
	}
}
EOF
  if ! caddy validate --config "$dir/Caddyfile" --adapter caddyfile >"$dir/validate.log" 2>&1; then
    cat "$dir/validate.log" >&2
    die "the resulting routes are invalid; nothing was changed."
  fi
}

reload() {
  if systemctl is-active --quiet "$unit"; then
    sudo systemctl reload "$unit"
  else
    echo "tailnetctl: $unit is not running; the change applies when it starts." >&2
  fi
}

# Apply one route change (a file to install, or "" to delete), rolling back on reload failure.
apply() {
  local host="$1" source="$2" target="$routes/$1.caddy" backup=""
  if [ -f "$target" ]; then
    backup="$work/previous.caddy"
    cp -- "$target" "$backup"
  fi
  if [ -n "$source" ]; then
    sudo install -m 0644 -- "$source" "$target"
  else
    sudo rm -f -- "$target"
  fi
  if ! reload; then
    if [ -n "$backup" ]; then
      sudo install -m 0644 -- "$backup" "$target"
    else
      sudo rm -f -- "$target"
    fi
    reload || true
    die "reload failed; restored the previous route for '$host'."
  fi
}

new_workdir() {
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/routes"
}

cmd_add() {
  [ "$#" -eq 2 ] || usage
  local host port="$2" file
  host="$(resolve_host "$1")"
  check_port "$port"
  require_installed
  new_workdir

  shopt -s nullglob
  for file in "$routes"/*.caddy; do
    [ "$(basename -- "$file")" = "$host.caddy" ] || cp -- "$file" "$work/routes/"
  done
  render "$host" "$port" >"$work/routes/$host.caddy"
  validate "$work"

  if [ -f "$routes/$host.caddy" ] && cmp -s "$work/routes/$host.caddy" "$routes/$host.caddy"; then
    echo "https://$host already routes to 127.0.0.1:$port"
  else
    apply "$host" "$work/routes/$host.caddy"
    echo "https://$host -> 127.0.0.1:$port"
  fi
  listening "$port" || echo "tailnetctl: warning: nothing is listening on port $port yet." >&2
}

cmd_rm() {
  [ "$#" -eq 1 ] || usage
  local host
  host="$(resolve_host "$1")"
  require_installed
  [ -f "$routes/$host.caddy" ] || die "no route for '$host'."
  new_workdir
  apply "$host" ""
  echo "Removed https://$host"
}

cmd_ls() {
  [ "$#" -eq 0 ] || usage
  require_installed
  local file host port state found=0
  shopt -s nullglob
  for file in "$routes"/*.caddy; do
    found=1
    host="$(basename -- "$file" .caddy)"
    port="$(sed -n 's/^[[:space:]]*reverse_proxy 127\.0\.0\.1:\([0-9]*\)$/\1/p' "$file")"
    if [ -n "$port" ] && listening "$port"; then state=up; else state=down; fi
    printf '%-40s 127.0.0.1:%-6s %s\n' "https://$host" "${port:-?}" "$state"
  done
  [ "$found" -eq 1 ] || echo "No services. Add one with: tailnetctl add <name> <port>"
}

case "${1:-}" in
  add) shift; cmd_add "$@" ;;
  rm | remove) shift; cmd_rm "$@" ;;
  ls | list) shift; cmd_ls "$@" ;;
  status) systemctl status --no-pager "$unit" ;;
  *) usage ;;
esac
