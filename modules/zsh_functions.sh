# modules/zsh_functions.sh

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
  fi
  return 1

  echo "Cloning $1 as a bare repo..."
  git clone --bare "$1" .bare
}
