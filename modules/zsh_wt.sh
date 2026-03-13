# modules/zsh_wt.sh

# ---------------------------------------------------------
# Git Worktree Manager (wt)
# ---------------------------------------------------------
wt() {
  local command="$1"
  if [[ -z "$command" ]]; then
    echo "Git Worktree Manager (wt)"
    echo "Usage: wt <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  clone <url>           Clone a repo as a bare repo into .bare"
    echo "  add <branch> [base]   Create a new worktree; if[base] omitted, use origin/<branch> if it exists, otherwise origin's default branch"
    echo "  ls                    List all worktrees"
    echo "  rm <branch>           Remove a worktree safely"
    return 1
  fi

  shift

  local -a gitcmd
  if [[ -d ".bare" ]]; then
    gitcmd=(git --git-dir=.bare)
  else
    gitcmd=(git)
  fi

  case "$command" in
  clone)
    local repo_url="$1"
    if [[ -z "$repo_url" ]]; then
      echo "Usage: wt clone <repo-url>"
      return 1
    fi
    git clone --bare "$repo_url" .bare
    ;;

  add)
    local branch_name="$1"
    local target_dir="$1"
    local base_branch="$2"
    local default_origin_branch=""

    if [[ -z "$branch_name" ]]; then
      echo "Usage: wt add <branch-name>[base-branch]"
      return 1
    fi

    if [[ -d ".bare" ]] && ! ${gitcmd[@]} config --get remote.origin.fetch &>/dev/null; then
      ${gitcmd[@]} config remote.origin.fetch "+refs/heads/*:refs/remotes/origin/*"
    fi

    ${gitcmd[@]} fetch --prune origin >/dev/null 2>&1

    if [[ -z "$base_branch" ]]; then
      if ${gitcmd[@]} show-ref --verify --quiet "refs/remotes/origin/${branch_name}"; then
        base_branch="origin/${branch_name}"
      else
        local origin_head_ref
        origin_head_ref="$(${gitcmd[@]} symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null)"
        if [[ -n "$origin_head_ref" ]]; then
          default_origin_branch="${origin_head_ref##*/}"
        elif ${gitcmd[@]} show-ref --verify --quiet refs/remotes/origin/main; then
          default_origin_branch="main"
        elif ${gitcmd[@]} show-ref --verify --quiet refs/remotes/origin/master; then
          default_origin_branch="master"
        fi

        if [[ -n "$default_origin_branch" ]]; then
          base_branch="origin/${default_origin_branch}"
        else
          base_branch="HEAD"
        fi
      fi
    fi

    if ${gitcmd[@]} show-ref --verify --quiet "refs/heads/${branch_name}"; then
      if ${gitcmd[@]} show-ref --verify --quiet "refs/remotes/origin/${branch_name}"; then
        local local_sha remote_sha
        local_sha="$(${gitcmd[@]} rev-parse "refs/heads/${branch_name}")"
        remote_sha="$(${gitcmd[@]} rev-parse "refs/remotes/origin/${branch_name}")"
        if [[ "$local_sha" != "$remote_sha" ]]; then
          if ${gitcmd[@]} merge-base --is-ancestor "refs/heads/${branch_name}" "refs/remotes/origin/${branch_name}"; then
            echo "Fast-forwarding local branch '${branch_name}' to match origin/${branch_name}..."
            ${gitcmd[@]} branch -f "$branch_name" "origin/${branch_name}"
          else
            echo "Warning: local '${branch_name}' has diverged from origin/${branch_name}."
            echo "  Local:  ${local_sha:0:10}"
            echo "  Remote: ${remote_sha:0:10}"
            local answer
            read -r "answer?Overwrite local branch with origin/${branch_name}? [y/N] "
            if [[ "$answer" =~ ^[Yy]$ ]]; then
              echo "Resetting local branch '${branch_name}' to origin/${branch_name}..."
              ${gitcmd[@]} branch -f "$branch_name" "origin/${branch_name}"
            else
              echo "Keeping local branch as-is."
            fi
          fi
        fi
      fi
      echo "Attaching worktree to existing branch '${branch_name}'..."
      if ! ${gitcmd[@]} worktree add "$target_dir" "$branch_name"; then
        echo "Error: failed to create worktree for branch '${branch_name}'"
        return 1
      fi
    else
      echo "Creating worktree with new branch '${branch_name}' from ${base_branch}..."
      if ! ${gitcmd[@]} worktree add -b "$branch_name" "$target_dir" "$base_branch"; then
        echo "Error: failed to create worktree for branch '${branch_name}'"
        return 1
      fi
    fi

    local env_src=""
    if [[ -z "$default_origin_branch" && "$base_branch" == origin/* ]]; then
      default_origin_branch="${base_branch#origin/}"
    fi
    if [[ -n "$default_origin_branch" && -f "${default_origin_branch}/.env" ]]; then
      env_src="${default_origin_branch}/.env"
    elif [[ -f "main/.env" ]]; then
      env_src="main/.env"
    fi
    if [[ -n "$env_src" ]]; then
      cp "$env_src" "$target_dir/.env"
      echo "✅ Copied .env from '${env_src%/.env}' to '$target_dir'"
    fi
    ;;

  ls | list)
    ${gitcmd[@]} worktree list
    ;;

  rm | remove)
    local target_dir="$1"
    if [[ -z "$target_dir" ]]; then
      echo "Usage: wt rm <branch-name>"
      return 1
    fi

    ${gitcmd[@]} worktree remove "$target_dir"
    ;;

  *)
    echo "Git Worktree Manager (wt)"
    echo "Usage: wt <command> [arguments]"
    echo ""
    echo "Commands:"
    echo "  clone <url>           Clone a repo as a bare repo into .bare"
    echo "  add <branch> [base]   Create a new worktree and branch (optionally from a base branch)"
    echo "  ls                    List all worktrees"
    echo "  rm <branch>           Remove a worktree safely"
    return 1
    ;;
  esac
}
