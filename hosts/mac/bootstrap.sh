#!/bin/bash
# Bootstrap wrapper for the work Mac (pettersoland).
#
# Single canonical URL pattern, per machine:
#   curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/hosts/macbook/bootstrap.sh | sudo bash
#
# This wrapper re-exports the work-machine variables and delegates to the
# canonical script. Keep this file small — all real logic lives in
# hosts/macbook/bootstrap.sh.
set -euo pipefail

export BOOTSTRAP_USERNAME="pettersoland"
export BOOTSTRAP_HM_FLAKE="pettersoland-mac"
export BOOTSTRAP_DARWIN_CONFIG="pettersoland-mac"

exec bash <(curl -fsSL https://raw.githubusercontent.com/psoland/os-config/main/hosts/macbook/bootstrap.sh) "$@"
