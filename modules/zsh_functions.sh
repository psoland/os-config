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

# Override Oh-My-Zsh 'gl' alias with a custom function
# unalias gl 2>/dev/null
function gl() {
  git log --oneline --reverse -n "${1:-20}"
}
