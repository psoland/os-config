# modules/home/programs/zsh_functions.sh

# ---------------------------------------------------------
# Terraform Functions
# ---------------------------------------------------------
function terraform_init() {
  local CURRENT_DIR=$(basename $(pwd))
  terraform init -backend-config=${CURRENT_DIR}.backend.conf
}

function terraform_plan() {
  terraform plan -var-file=terraform.tfvars
}

function terraform_apply() {
  terraform apply -var-file=terraform.tfvars
}

# ---------------------------------------------------------
# Git Functions
# ---------------------------------------------------------
function git_log() {
  git --no-pager log --reverse -n 10
}

function gl() {
  git log --oneline --reverse -n "${1:-20}"
}

function git_clone() {
  if [ -z "$1" ]; then
    echo "Error: You are missing the url"
    echo "Use: git_clone <url>"
    return 1
  fi

  echo "Cloning $1 as a bare repo..."
  git clone --bare "$1" .bare
}

# Update this repository's Nix flake inputs.
function update() {
  local dotfiles_root="$HOME/.dotfiles"

  if [[ "$(git rev-parse --show-toplevel 2>/dev/null)" != "$dotfiles_root" ]]; then
    echo "update must be run from $dotfiles_root or one of its subdirectories." >&2
    return 1
  fi

  nix flake update "$@"
}

# Send a file to a Tailscale device via Taildrop.
function drop() {
  tailscale file cp "$1" "$2:"
}

# Copy a file or directory from a remote machine with rsync over SSH.
# If the remote username is omitted, use the current local username.
function rcopy() {
  if [[ $# -lt 1 || $# -gt 2 || "$1" != *:* ]]; then
    echo "Usage: rcopy [user@]machine:/path/to/source [destination]" >&2
    return 2
  fi

  if ! command -v rsync >/dev/null 2>&1; then
    echo "rcopy requires rsync to be installed." >&2
    return 1
  fi

  local source="$1"
  local destination="${2:-.}"

  if [[ "$source" != *@*:* ]]; then
    source="${USER}@${source}"
  fi

  rsync -av -- "$source" "$destination"
}

# Open a complete file in Hunk so unchanged lines can receive review notes.
function hda() {
  if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "Usage: hda <file>" >&2
    return 2
  fi

  hunk diff --files /dev/null "$1" --watch
}
