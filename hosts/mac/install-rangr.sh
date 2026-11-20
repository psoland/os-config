#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: rangr-install [release-tag]"
  echo "Installs the latest Rangr release by default. Requires gh access to joexbayer/rangr."
}

if [ "$#" -gt 1 ]; then
  usage >&2
  exit 1
fi
case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
  -*)
    usage >&2
    exit 1
    ;;
esac

if [ "$(uname -s)" != "Darwin" ] || [ "$(uname -m)" != "arm64" ]; then
  echo "Rangr releases are only available for Apple Silicon macOS." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install gh and run gh auth login first." >&2
  exit 1
fi

repo="${NEXUS_REPO:-joexbayer/rangr}"
tag="${1:-}"
if [ -z "$tag" ]; then
  tag="$(gh release view --repo "$repo" --json tagName --jq .tagName)"
fi
if [ -z "$tag" ] || [[ "$tag" == -* ]]; then
  echo "Could not resolve a valid Rangr release tag." >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Resolve latest once: the installer and the app it downloads must use the same
# release. Fetch completely before executing; authentication stays in gh, not Nix.
gh release download "$tag" --repo "$repo" --pattern install-release.sh --dir "$work"
echo "Installing Rangr release $tag..."
# The upstream installer verifies the archive checksum and Developer ID signature,
# installs the writable app, and links the CLI. Keep its destination/CLI overrides.
NEXUS_REPO="$repo" bash "$work/install-release.sh" "$tag"
