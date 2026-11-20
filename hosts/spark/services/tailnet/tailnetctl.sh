# shellcheck shell=bash
# Manage private https://<name>.<zone> routes on the tailnet proxy.
set -euo pipefail

zone="${TAILNET_ZONE:?TAILNET_ZONE is not set}"
routes="${TAILNET_ROUTES_DIR:?TAILNET_ROUTES_DIR is not set}"
unit="${TAILNET_UNIT:-mujo-tailnet-caddy.service}"

usage() {
  cat >&2 <<EOF
Usage: tailnetctl <command> [args]

Commands:
  add <name> <port>   Serve https://<name>.$zone from 127.0.0.1:<port>
  rm <name>           Remove a service route
  ls                  List service routes and whether their port is listening
  status              Show the proxy's systemd status

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

check_name() {
  [[ "$1" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] \
    || die "invalid name '$1': use lowercase letters, digits and inner hyphens (max 63)."
}

check_port() {
  [[ "$1" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$1" -le 65535 ] || die "invalid port '$1'."
}

listening() {
  [ -n "$(ss -H -ltn "sport = :$1" 2>/dev/null)" ]
}

render() {
  cat <<EOF
# Managed by tailnetctl
@$1 host $1.$zone
handle @$1 {
	reverse_proxy 127.0.0.1:$2
}
EOF
}

# Validate the candidate set of route files exactly as the proxy imports them.
validate() {
  local dir="$1"
  cat >"$dir/Caddyfile" <<EOF
{
	admin off
}

http://*.$zone {
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
  local name="$1" source="$2" target="$routes/$1.caddy" backup=""
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
    die "reload failed; restored the previous route for '$name'."
  fi
}

new_workdir() {
  work="$(mktemp -d)"
  trap 'rm -rf "$work"' EXIT
  mkdir "$work/routes"
}

cmd_add() {
  [ "$#" -eq 2 ] || usage
  local name="$1" port="$2" file
  check_name "$name"
  check_port "$port"
  require_installed
  new_workdir

  shopt -s nullglob
  for file in "$routes"/*.caddy; do
    [ "$(basename -- "$file")" = "$name.caddy" ] || cp -- "$file" "$work/routes/"
  done
  render "$name" "$port" >"$work/routes/$name.caddy"
  validate "$work"

  if [ -f "$routes/$name.caddy" ] && cmp -s "$work/routes/$name.caddy" "$routes/$name.caddy"; then
    echo "https://$name.$zone already routes to 127.0.0.1:$port"
  else
    apply "$name" "$work/routes/$name.caddy"
    echo "https://$name.$zone -> 127.0.0.1:$port"
  fi
  listening "$port" || echo "tailnetctl: warning: nothing is listening on port $port yet." >&2
}

cmd_rm() {
  [ "$#" -eq 1 ] || usage
  local name="$1"
  check_name "$name"
  require_installed
  [ -f "$routes/$name.caddy" ] || die "no route named '$name'."
  new_workdir
  apply "$name" ""
  echo "Removed https://$name.$zone"
}

cmd_ls() {
  [ "$#" -eq 0 ] || usage
  require_installed
  local file name port state found=0
  shopt -s nullglob
  for file in "$routes"/*.caddy; do
    found=1
    name="$(basename -- "$file" .caddy)"
    port="$(sed -n 's/^[[:space:]]*reverse_proxy 127\.0\.0\.1:\([0-9]*\)$/\1/p' "$file")"
    if [ -n "$port" ] && listening "$port"; then state=up; else state=down; fi
    printf '%-40s 127.0.0.1:%-6s %s\n' "https://$name.$zone" "${port:-?}" "$state"
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
