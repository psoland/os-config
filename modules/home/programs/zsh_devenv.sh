# modules/home/programs/zsh_devenv.sh

# Print tab-separated PID, worktree, and runtime records from Linux /proc.
_devenv_manager_records_linux() {
  emulate -L zsh
  setopt null_glob

  local proc_dir pid root runtime config_path daemon_index
  local -a process_args

  for proc_dir in /proc/<->; do
    [[ -r "$proc_dir/cmdline" ]] || continue
    [[ -O "$proc_dir" ]] || continue

    process_args=("${(@0)$(<"$proc_dir/cmdline" 2>/dev/null)}")
    daemon_index="${process_args[(I)daemon-processes]}"
    (( daemon_index > 0 && daemon_index < ${#process_args} )) || continue

    config_path="${process_args[$(( daemon_index + 1 ))]}"
    [[ "${config_path:t}" == "daemon-config.json" ]] || continue

    root="$(readlink "$proc_dir/cwd" 2>/dev/null)"
    [[ -n "$root" ]] || continue

    pid="${proc_dir:t}"
    runtime="${config_path:h:h}"
    print -r -- "$pid"$'\t'"$root"$'\t'"$runtime"
  done
}

# Print native Devenv manager records on macOS, where /proc is unavailable.
_devenv_manager_records_darwin() {
  emulate -L zsh

  local pid command config_path root runtime entry

  while IFS=$' \t\n' read -r pid command; do
    [[ "$command" == *" daemon-processes "* ]] || continue

    config_path="${command#* daemon-processes }"
    [[ "${config_path:t}" == "daemon-config.json" ]] || continue

    root=""
    while IFS= read -r entry; do
      if [[ "$entry" == n* ]]; then
        root="${entry#n}"
        break
      fi
    done < <(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null)
    [[ -n "$root" ]] || continue

    runtime="${config_path:h:h}"
    print -r -- "$pid"$'\t'"$root"$'\t'"$runtime"
  done < <(ps -U "$UID" -o pid=,command= 2>/dev/null)
}

# Print tab-separated PID, worktree, and runtime records for native Devenv
# process managers owned by the current user.
_devenv_manager_records() {
  emulate -L zsh

  if [[ -d /proc ]]; then
    _devenv_manager_records_linux
  elif [[ "$OSTYPE" == darwin* ]] && command -v lsof >/dev/null 2>&1; then
    _devenv_manager_records_darwin
  fi
}

_devenv_manager_pids_for_root() {
  emulate -L zsh

  local target="${1:A}"
  local pid root runtime

  while IFS=$'\t' read -r pid root runtime; do
    [[ "${root:A}" == "$target" ]] && print -r -- "$pid"
  done < <(_devenv_manager_records)
}

_devenv_stop_worktree() {
  emulate -L zsh

  local target="${1:A}"
  local manager_output down_output
  local down_status=0
  local pid attempt
  local -a manager_pids remaining_pids

  if [[ ! -d /proc ]] && { [[ "$OSTYPE" != darwin* ]] || ! command -v lsof >/dev/null 2>&1; }; then
    echo "Error: cannot safely inspect Devenv processes on this platform."
    echo "The worktree was not removed."
    return 2
  fi

  manager_output="$(_devenv_manager_pids_for_root "$target")"
  [[ -n "$manager_output" ]] || return 0
  manager_pids=("${(@f)manager_output}")

  if ! command -v devenv >/dev/null 2>&1; then
    echo "Error: Devenv services are running for '$target', but devenv is unavailable."
    echo "Manager PID(s): ${manager_pids[*]}"
    return 1
  fi

  echo "Stopping Devenv services for '$target'..."
  down_output="$(cd "$target" && devenv processes down --no-tui 2>&1)" || down_status=$?

  for attempt in {1..50}; do
    remaining_pids=()
    for pid in "${manager_pids[@]}"; do
      kill -0 "$pid" 2>/dev/null && remaining_pids+=("$pid")
    done

    (( ${#remaining_pids} == 0 )) && return 0
    sleep 0.1
  done

  echo "Error: Devenv manager PID(s) ${remaining_pids[*]} did not stop."
  if (( down_status != 0 )) && [[ -n "$down_output" ]]; then
    print -r -- "$down_output"
  fi
  echo "The worktree was not removed."
  return 1
}

devenv-status() {
  emulate -L zsh

  local target=""
  local running_only=false

  while (( $# > 0 )); do
    case "$1" in
    --worktree)
      if (( $# < 2 )); then
        echo "Usage: devenv-status [--worktree <path>] [--running]"
        return 2
      fi
      target="${2:A}"
      shift 2
      ;;
    --running)
      running_only=true
      shift
      ;;
    -h | --help)
      echo "Usage: devenv-status [--worktree <path>] [--running]"
      return 0
      ;;
    *)
      echo "Usage: devenv-status [--worktree <path>] [--running]"
      return 2
      ;;
    esac
  done

  if [[ ! -d /proc ]] && { [[ "$OSTYPE" != darwin* ]] || ! command -v lsof >/dev/null 2>&1; }; then
    echo "Error: devenv-status requires Linux /proc or macOS with lsof."
    return 2
  fi

  if $running_only && [[ -z "$target" ]]; then
    echo "Error: --running requires --worktree <path>."
    return 2
  fi

  local pid root runtime age state children
  local found=false

  if ! $running_only; then
    printf "%-8s %-12s %-10s %s\n" "PID" "AGE" "STATE" "WORKTREE"
  fi

  while IFS=$'\t' read -r pid root runtime; do
    [[ -z "$target" || "${root:A}" == "$target" ]] || continue
    found=true

    $running_only && continue

    age="$(ps -p "$pid" -o etime= 2>/dev/null)"
    age="${age//[[:space:]]/}"
    if [[ ! -d "$root" ]]; then
      state="orphaned"
    elif [[ ! -d "$runtime" ]]; then
      state="broken"
    else
      state="running"
    fi

    printf "%-8s %-12s %-10s %s\n" "$pid" "$age" "$state" "$root"
    if [[ -d /proc ]]; then
      children="$(ps --ppid "$pid" -o pid=,etime=,args= 2>/dev/null)"
      if [[ -n "$children" ]]; then
        print -r -- "$children" | while IFS= read -r entry; do
          print -r -- "  $entry"
        done
      fi
    fi
  done < <(_devenv_manager_records)

  if $running_only; then
    $found
    return
  fi

  if ! $found; then
    echo "No detached Devenv process managers found."
  fi
  return 0
}
