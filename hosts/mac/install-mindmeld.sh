#!/usr/bin/env bash
set -euo pipefail

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Mindmeld is only available for macOS." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install gh and run gh auth login first." >&2
  exit 1
fi

installer="$(mktemp)"
trap 'rm -f "$installer"' EXIT

# Fetch completely before running, so a failed API request cannot execute a
# partial installer. Authentication stays in gh, outside the Nix store.
gh api "repos/${MINDMELD_REPO:-Knowit-Objectnet/mindmeld}/contents/scripts/install.sh" \
  --jq .content | base64 -d > "$installer"
bash "$installer" "$@"
