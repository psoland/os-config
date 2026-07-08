set -euo pipefail

REGISTRY="${VLLM_MODELS_CONFIG:-$HOME/.config/vllm/models.json}"

usage() {
  cat >&2 <<'EOF'
Usage: vllmctl <command> [args]

Commands:
  list | ls | plan          Show configured models/routes/ports
  ps                       Show vLLM Docker containers
  start <name> [args...]   Start configured model, appending optional vLLM args
  recreate <name> [args...] Remove and recreate configured model container
  logs | log <name>        Follow container logs
  stop <name> [name...]    Stop containers
  rm <name> [name...]      Remove containers
  doctor                   Validate registry and compare existing containers

Model config lives in hosts/spark/vllm-models.nix and is generated to:
  ~/.config/vllm/models.json
EOF
}

require_registry() {
  if [ ! -r "$REGISTRY" ]; then
    echo "Missing vLLM registry: $REGISTRY" >&2
    echo "Run: cd ~/.dotfiles && apply" >&2
    exit 1
  fi
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but was not found on PATH" >&2
    exit 1
  fi
}

model_json() {
  local name="$1"
  require_registry
  require_jq
  local json
  json="$(jq -c --arg name "$name" '.models[] | select(.name == $name)' "$REGISTRY")"
  if [ -z "$json" ]; then
    echo "Unknown model: $name" >&2
    echo "Known models:" >&2
    jq -r '.models[].name | "  " + .' "$REGISTRY" >&2
    exit 1
  fi
  printf '%s\n' "$json"
}

json_field() {
  local json="$1"
  local expr="$2"
  jq -r "$expr" <<<"$json"
}

docker_exists() {
  docker inspect "$1" >/dev/null 2>&1
}

docker_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null || echo false)" = "true" ]
}

container_label() {
  local name="$1"
  local label="$2"
  docker inspect -f "{{ index .Config.Labels \"$label\" }}" "$name" 2>/dev/null || true
}

cmd_plan() {
  require_registry
  require_jq

  printf '%-18s %-6s %-18s %-8s %-8s %s\n' "NAME" "PORT" "ROUTE" "GPU" "CTX" "MODEL"
  jq -r '.models[] | [.name, .port, .route, .gpuMemoryUtilization, (.maxModelLen // "-"), .model] | @tsv' "$REGISTRY" |
    while IFS=$'\t' read -r name port route gpu ctx model; do
      printf '%-18s %-6s %-18s %-8s %-8s %s\n' "$name" "$port" "$route" "$gpu" "$ctx" "$model"
    done

  local total_gpu
  total_gpu="$(jq -r '[.models[].gpuMemoryUtilization // 0] | add // 0' "$REGISTRY")"
  echo
  echo "Configured GPU utilization total: $total_gpu"
  if jq -e '[.models[].gpuMemoryUtilization // 0] | add > 1' "$REGISTRY" >/dev/null; then
    echo "Warning: total GPU utilization is > 1.0. Only start this combination if intentional." >&2
  fi
}

cmd_ps() {
  docker ps -a \
    --filter label=dotfiles.service=vllm \
    --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}'
}

cmd_start() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: vllmctl start <name> [vllm args...]" >&2
    exit 1
  fi

  local name="$1"
  shift

  local json model image gpus port route gpu_memory max_model_len config_hash hf_cache
  json="$(model_json "$name")"
  model="$(json_field "$json" '.model')"
  image="${VLLM_IMAGE:-$(json_field "$json" '.image')}"
  gpus="${VLLM_GPUS:-$(json_field "$json" '.gpus')}"
  port="$(json_field "$json" '.port')"
  route="$(json_field "$json" '.route')"
  gpu_memory="${VLLM_GPU_MEMORY_UTILIZATION:-$(json_field "$json" '.gpuMemoryUtilization')}"
  max_model_len="$(json_field "$json" '.maxModelLen // empty')"
  config_hash="$(json_field "$json" '.configHash')"
  hf_cache="${VLLM_HF_CACHE:-$(json_field "$json" '.hfCache // empty')}"
  hf_cache="${hf_cache:-$HOME/.cache/huggingface}"

  local -a extra_args=()
  local -a vllm_args=()

  mapfile -t extra_args < <(jq -r '.extraArgs[]?' <<<"$json")

  if [ -n "$max_model_len" ]; then
    vllm_args+=(--max-model-len "$max_model_len")
  fi

  vllm_args+=("${extra_args[@]}")
  vllm_args+=("$@")

  if docker_exists "$name"; then
    local existing_hash
    existing_hash="$(container_label "$name" dotfiles.vllm.config-hash)"

    if [ "$existing_hash" != "$config_hash" ]; then
      echo "Container '$name' exists but does not match the generated registry." >&2
      echo "Use this to recreate it with current settings:" >&2
      echo "  vllmctl recreate $name" >&2
      if [ "${VLLM_ALLOW_STALE:-0}" != "1" ]; then
        exit 1
      fi
      echo "VLLM_ALLOW_STALE=1 set; starting stale container anyway." >&2
    fi

    if docker_running "$name"; then
      echo "Container '$name' is already running."
      echo "Logs: vllmctl logs $name"
      return 0
    fi

    echo "Starting existing container '$name'. Use 'vllmctl recreate $name' to apply changed settings."
    docker start "$name"
    return 0
  fi

  echo "Starting $name"
  echo "  model: $model"
  echo "  route: $route"
  echo "  local: http://127.0.0.1:$port"
  echo "  proxy: $route"

  docker run -d \
    --name "$name" \
    --restart unless-stopped \
    --gpus "$gpus" \
    --ipc=host \
    --label dotfiles.service=vllm \
    --label "dotfiles.vllm.name=$name" \
    --label "dotfiles.vllm.model=$model" \
    --label "dotfiles.vllm.route=$route" \
    --label "dotfiles.vllm.port=$port" \
    --label "dotfiles.vllm.gpu-memory-utilization=$gpu_memory" \
    --label "dotfiles.vllm.max-model-len=$max_model_len" \
    --label "dotfiles.vllm.config-hash=$config_hash" \
    -p "127.0.0.1:$port:8000" \
    -v "$hf_cache:/root/.cache/huggingface" \
    "$image" \
    "$model" \
    --host 0.0.0.0 \
    --port 8000 \
    --gpu-memory-utilization "$gpu_memory" \
    "${vllm_args[@]}"
}

cmd_recreate() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: vllmctl recreate <name> [vllm args...]" >&2
    exit 1
  fi

  local name="$1"
  shift

  if docker_exists "$name"; then
    docker rm -f "$name" >/dev/null
  fi

  cmd_start "$name" "$@"
}

cmd_logs() {
  if [ "$#" -ne 1 ]; then
    echo "Usage: vllmctl logs <name>" >&2
    exit 1
  fi

  docker logs -f "$1"
}

cmd_stop() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: vllmctl stop <name> [name...]" >&2
    exit 1
  fi

  docker stop "$@"
}

cmd_rm() {
  if [ "$#" -lt 1 ]; then
    echo "Usage: vllmctl rm <name> [name...]" >&2
    exit 1
  fi

  docker rm -f "$@"
}

cmd_doctor() {
  require_registry
  require_jq

  local errors=0

  for field in name route port; do
    local duplicates
    duplicates="$(jq -r --arg field "$field" '.models | group_by(.[$field])[] | select(length > 1) | .[0][$field]' "$REGISTRY")"
    if [ -n "$duplicates" ]; then
      echo "Duplicate $field values:" >&2
      echo "$duplicates" | sed 's/^/  /' >&2
      errors=$((errors + 1))
    fi
  done

  local bad_routes
  bad_routes="$(jq -r '.models[] | select((.route | startswith("/")) | not) | .name + " -> " + .route' "$REGISTRY")"
  if [ -n "$bad_routes" ]; then
    echo "Routes must start with /:" >&2
    echo "$bad_routes" | sed 's/^/  /' >&2
    errors=$((errors + 1))
  fi

  local total_gpu
  total_gpu="$(jq -r '[.models[].gpuMemoryUtilization // 0] | add // 0' "$REGISTRY")"
  if jq -e '[.models[].gpuMemoryUtilization // 0] | add > 1' "$REGISTRY" >/dev/null; then
    echo "Warning: configured GPU utilization total is $total_gpu (> 1.0)." >&2
  fi

  while IFS=$'\t' read -r name expected_hash; do
    if docker_exists "$name"; then
      local existing_hash
      existing_hash="$(container_label "$name" dotfiles.vllm.config-hash)"
      if [ "$existing_hash" != "$expected_hash" ]; then
        echo "Stale container: $name" >&2
        echo "  recreate with: vllmctl recreate $name" >&2
      fi
    fi
  done < <(jq -r '.models[] | [.name, .configHash] | @tsv' "$REGISTRY")

  if [ "$errors" -gt 0 ]; then
    exit 1
  fi

  echo "vllm registry OK"
}

main() {
  local command="${1:-}"
  if [ -z "$command" ]; then
    usage
    exit 1
  fi
  shift

  case "$command" in
    list|ls|plan)
      cmd_plan "$@"
      ;;
    ps)
      cmd_ps "$@"
      ;;
    start)
      cmd_start "$@"
      ;;
    recreate)
      cmd_recreate "$@"
      ;;
    logs|log)
      cmd_logs "$@"
      ;;
    stop)
      cmd_stop "$@"
      ;;
    rm)
      cmd_rm "$@"
      ;;
    doctor)
      cmd_doctor "$@"
      ;;
    help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"
