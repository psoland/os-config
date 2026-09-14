#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TEMPORARY_DIRECTORY="$(mktemp -d)"
trap 'rm -rf -- "$TEMPORARY_DIRECTORY"' EXIT

RENDERED_UNIT="$TEMPORARY_DIRECTORY/mujo-test-cloudflared.service"
for target in sysinit.target basic.target shutdown.target network-online.target default.target; do
  printf '%s\n' '[Unit]' > "$TEMPORARY_DIRECTORY/$target"
done

sed \
  -e 's|__UNIT_DESCRIPTION__|Test Cloudflare Tunnel connector|' \
  -e 's|__CLOUDFLARED_BINARY__|/usr/bin/true|' \
  -e 's|__CLOUDFLARED_TOKEN_FILE__|/tmp/mujo-publish-test/tunnel-token|g' \
  -e 's|__CLOUDFLARED_INHIBIT_FILE__|/tmp/mujo-publish-test/inhibit|g' \
  "$ROOT/mujo-cloudflared.service.template" > "$RENDERED_UNIT"

SYSTEMD_UNIT_PATH="$TEMPORARY_DIRECTORY" systemd-analyze verify "$RENDERED_UNIT"

if grep -Eq -- '(^|[[:space:]])--token([=[:space:]]|$)' "$RENDERED_UNIT"; then
  printf '%s\n' "The rendered unit must use --token-file, never --token" >&2
  exit 1
fi
