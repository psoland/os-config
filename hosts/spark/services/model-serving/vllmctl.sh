set -euo pipefail

SOURCE_REGISTRY="${VLLM_MODELS_CONFIG:-$HOME/.config/vllm/models.json}"
DEFAULTS_CONFIG="${VLLM_DEFAULTS_CONFIG:-$HOME/.config/vllm/defaults.json}"
STATE_DIR="${VLLM_STATE_DIR:-$HOME/.local/state/vllm}"
REGISTRY="${VLLM_REGISTRY_STATE:-$STATE_DIR/registry.json}"
ROUTES_DIR="${VLLM_CADDY_ROUTES_DIR:-$STATE_DIR/routes}"
ROUTES_FILE="$ROUTES_DIR/models.caddy"
LOCK_FILE="$STATE_DIR/update.lock"

usage() {
  cat >&2 <<'EOF'
Usage: vllmctl <command> [args]

Commands:
  update                   Validate models, assign ports, and update Caddy
  list | ls | plan          Show configured models/routes/ports
  ps                       Show vLLM Docker containers
  start <name> [args...]   Start configured model, appending optional vLLM args
  recreate <name> [args...] Remove and recreate configured model container
  logs | log <name>        Follow container logs
  stop <name> [name...]    Stop containers
  rm <name> [name...]      Remove containers
  doctor                   Validate registry and compare existing containers

Edit model config locally, then run `vllmctl update`:
  ~/.config/vllm/models.json

Resolved model state is generated at:
  ~/.local/state/vllm/registry.json
EOF
}

require_registry() {
  if [ ! -r "$REGISTRY" ]; then
    echo "Missing resolved vLLM registry: $REGISTRY" >&2
    echo "Run: vllmctl update" >&2
    exit 1
  fi
}

cmd_update() {
  require_jq

  if [ ! -r "$SOURCE_REGISTRY" ]; then
    echo "Missing editable vLLM registry: $SOURCE_REGISTRY" >&2
    exit 1
  fi
  if [ ! -r "$DEFAULTS_CONFIG" ]; then
    echo "Missing vLLM defaults: $DEFAULTS_CONFIG" >&2
    echo "Run: cd ~/.dotfiles && apply" >&2
    exit 1
  fi
  if ! command -v caddy >/dev/null 2>&1; then
    echo "caddy is required but was not found on PATH" >&2
    exit 1
  fi
  if ! command -v flock >/dev/null 2>&1; then
    echo "flock is required but was not found on PATH" >&2
    exit 1
  fi

  if ! jq -e 'type == "object" and (.models | type == "array")' "$SOURCE_REGISTRY" >/dev/null 2>&1; then
    echo "Invalid model config: expected a JSON object containing a models array: $SOURCE_REGISTRY" >&2
    exit 1
  fi
  if ! jq -e '
    type == "object"
    and (.basePort | type == "number" and floor == . and . >= 1 and . <= 65535)
  ' "$DEFAULTS_CONFIG" >/dev/null 2>&1; then
    echo "Invalid vLLM defaults or basePort: $DEFAULTS_CONFIG" >&2
    exit 1
  fi
  if ! jq -e '
    all(.models[];
      (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9_.-]*$"))
      and (.model | type == "string" and length > 0)
      and ((.port // null) == null or (.port | type == "number" and floor == . and . >= 1 and . <= 65535))
      and ((.route // null) == null or (.route | type == "string" and test("^/[A-Za-z0-9][A-Za-z0-9._/-]*$") and (endswith("/") | not)))
      and ((.extraArgs // []) | type == "array" and all(.[]; type == "string"))
      and ((.environment // {}) | type == "object" and all(to_entries[];
        (.key | test("^[A-Za-z_][A-Za-z0-9_]*$")) and (.value | type == "string")))
      and ((.gpuMemoryUtilization // 0.5) | type == "number" and . > 0 and . <= 1)
      and ((.maxModelLen // null) == null or (.maxModelLen | type == "number" and floor == . and . > 0))
    )
  ' "$SOURCE_REGISTRY" >/dev/null 2>&1; then
    echo "Invalid model entry in $SOURCE_REGISTRY" >&2
    echo "Check names, model IDs, routes, ports, GPU utilization, context lengths, environment, and extraArgs." >&2
    exit 1
  fi
  if ! jq -e '[.models[].name] | length == (unique | length)' "$SOURCE_REGISTRY" >/dev/null; then
    echo "Model names must be unique in $SOURCE_REGISTRY" >&2
    exit 1
  fi
  if ! jq -e '[.models[].port? | select(. != null)] | length == (unique | length)' "$SOURCE_REGISTRY" >/dev/null; then
    echo "Explicit model ports must be unique in $SOURCE_REGISTRY" >&2
    exit 1
  fi

  mkdir -p "$STATE_DIR" "$ROUTES_DIR"
  exec 9>"$LOCK_FILE"
  flock 9

  local work previous
  work="$(mktemp -d "$STATE_DIR/.update.XXXXXX")"
  trap "rm -rf '$work'" EXIT
  previous="$work/previous.json"
  if [ -r "$REGISTRY" ] && jq empty "$REGISTRY" >/dev/null 2>&1; then
    cp "$REGISTRY" "$previous"
  else
    jq -n '{ models: [] }' > "$previous"
  fi

  local normalized hashed candidate_routes validation_config
  normalized="$work/normalized.json"
  hashed="$work/hashed.ndjson"
  candidate_routes="$work/models.caddy"
  validation_config="$work/Caddyfile"

  jq -n \
    --slurpfile source "$SOURCE_REGISTRY" \
    --slurpfile defaults "$DEFAULTS_CONFIG" \
    --slurpfile previous "$previous" '
      def first_free($used; $start):
        first(range($start; 65536) | . as $port | select(($used | index($port)) == null));

      ($source[0].models // []) as $models
      | ($defaults[0].basePort // 8015) as $basePort
      | ($defaults[0] | del(.basePort)) as $modelDefaults
      | [$models[].port? | select(. != null)] as $explicitPorts
      | [
          $models[]
          | select((.port // null) == null) as $model
          | $previous[0].models[]?
          | select(.name == $model.name)
          | .port
          | select(type == "number" and . >= 1 and . <= 65535)
          | . as $port
          | select(($explicitPorts | index($port)) == null)
        ] | unique as $reservedPorts
      | reduce range(0; $models | length) as $index (
          { models: [], used: ($explicitPorts + $reservedPorts) };
          . as $state
          | $models[$index] as $model
          | ([ $previous[0].models[]? | select(.name == $model.name) | .port ][0] // null) as $previousPort
          | (if $model.port != null then $model.port
             elif $previousPort != null and ($reservedPorts | index($previousPort)) != null then $previousPort
             else first_free($state.used; $basePort)
             end) as $port
          | (($model.route // ("/" + $model.name))) as $route
          | ($modelDefaults + $model + {
              port: $port,
              route: $route,
              matcher: ("model_" + ($index | tostring))
            }
            | .extraArgs = (.extraArgs // [])
            | .environment = (.environment // {})
            | .maxModelLen = (.maxModelLen // null)) as $normalized
          | .models += [$normalized]
          | .used += [$port]
        )
      | { defaults: $defaults[0], models: .models }
    ' > "$normalized"

  if ! jq -e '[.models[].route] | length == (unique | length)' "$normalized" >/dev/null; then
    echo "Resolved model routes must be unique." >&2
    return 1
  fi
  if ! jq -e '[.models[].port] | length == (unique | length)' "$normalized" >/dev/null; then
    echo "Resolved model ports must be unique." >&2
    return 1
  fi

  : > "$hashed"
  while IFS= read -r model_json; do
    local config_hash
    config_hash="$(jq -S -c 'del(.configHash, .matcher)' <<<"$model_json" | sha256sum | cut -d' ' -f1)"
    jq -c --arg hash "$config_hash" '. + { configHash: $hash }' <<<"$model_json" >> "$hashed"
  done < <(jq -c '.models[]' "$normalized")

  jq -s --slurpfile normalized "$normalized" '
    . as $models | $normalized[0] | .models = $models
  ' "$hashed" > "$work/registry.json"

  : > "$candidate_routes"
  while IFS=$'\t' read -r matcher route port; do
    cat >> "$candidate_routes" <<EOF
@${matcher} path ${route} ${route}/*
handle @${matcher} {
  uri strip_prefix ${route}
  reverse_proxy 127.0.0.1:${port}
}

EOF
  done < <(jq -r '.models[] | [.matcher, .route, .port] | @tsv' "$work/registry.json")

  cat > "$validation_config" <<EOF
:8000 {
  import ${candidate_routes}

  handle {
    respond "unknown model route" 404
  }
}
EOF

  if ! caddy validate --config "$validation_config" --adapter caddyfile >"$work/caddy-validation.log" 2>&1; then
    cat "$work/caddy-validation.log" >&2
    echo "Generated Caddy routes are invalid; existing state was not changed." >&2
    return 1
  fi

  mv "$work/registry.json" "$REGISTRY"
  mv "$candidate_routes" "$ROUTES_FILE"

  echo "Updated vLLM registry and Caddy routes:"
  jq -r '.models[] | "  \(.name): port=\(.port) route=\(.route)"' "$REGISTRY"

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    while IFS=$'\t' read -r name expected_hash; do
      if docker_exists "$name"; then
        local existing_hash
        existing_hash="$(container_label "$name" dotfiles.vllm.config-hash)"
        if [ "$existing_hash" != "$expected_hash" ]; then
          echo "Stale container: $name (recreate with: vllmctl recreate $name)" >&2
        fi
      fi
    done < <(jq -r '.models[] | [.name, .configHash] | @tsv' "$REGISTRY")
  fi

  if [ "${VLLM_SKIP_CADDY_RELOAD:-0}" != "1" ] \
    && command -v systemctl >/dev/null 2>&1 \
    && systemctl --user is-active --quiet caddy; then
    systemctl --user reload caddy
    echo "Reloaded Caddy."
  fi

  rm -rf "$work"
  trap - EXIT
}

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required but was not found on PATH" >&2
    exit 1
  fi
}

require_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "docker is required but was not found on PATH" >&2
    exit 1
  fi

  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not reachable. Is Docker running?" >&2
    exit 1
  fi
}

port_listeners() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    local output
    output="$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)"
    awk 'NR > 1' <<<"$output"
    return 0
  fi

  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp "sport = :$port" 2>/dev/null || true
    return 0
  fi

  return 2
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
  require_docker

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

  local json model image gpus port route gpu_memory max_model_len restart_policy config_hash hf_cache
  json="$(model_json "$name")"
  model="$(json_field "$json" '.model')"
  image="${VLLM_IMAGE:-$(json_field "$json" '.image')}"
  gpus="${VLLM_GPUS:-$(json_field "$json" '.gpus')}"
  port="$(json_field "$json" '.port')"
  route="$(json_field "$json" '.route')"
  gpu_memory="${VLLM_GPU_MEMORY_UTILIZATION:-$(json_field "$json" '.gpuMemoryUtilization')}"
  max_model_len="$(json_field "$json" '.maxModelLen // empty')"
  restart_policy="${VLLM_RESTART_POLICY:-$(json_field "$json" '.restartPolicy // "on-failure:5"')}"
  config_hash="$(json_field "$json" '.configHash')"
  hf_cache="${VLLM_HF_CACHE:-$(json_field "$json" '.hfCache // empty')}"
  hf_cache="${hf_cache:-$HOME/.cache/huggingface}"

  require_docker

  local -a extra_args=()
  local -a environment_args=()
  local -a vllm_args=()

  mapfile -t extra_args < <(jq -r '.extraArgs[]?' <<<"$json")
  mapfile -t environment_args < <(
    jq -r '(.environment // {}) | to_entries[] | "\(.key)=\(.value)"' <<<"$json"
  )

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
  echo "  restart: $restart_policy"

  docker run -d \
    --name "$name" \
    --restart "$restart_policy" \
    --gpus "$gpus" \
    --ipc=host \
    --label dotfiles.service=vllm \
    --label "dotfiles.vllm.name=$name" \
    --label "dotfiles.vllm.model=$model" \
    --label "dotfiles.vllm.route=$route" \
    --label "dotfiles.vllm.port=$port" \
    --label "dotfiles.vllm.gpu-memory-utilization=$gpu_memory" \
    --label "dotfiles.vllm.max-model-len=$max_model_len" \
    --label "dotfiles.vllm.restart-policy=$restart_policy" \
    --label "dotfiles.vllm.config-hash=$config_hash" \
    -p "127.0.0.1:$port:8000" \
    -v "$hf_cache:/root/.cache/huggingface" \
    "${environment_args[@]/#/--env=}" \
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

  require_docker

  if docker_exists "$name"; then
    docker rm -f "$name" >/dev/null
  fi

  cmd_start "$name" "$@"
}

cmd_logs() {
  require_docker

  if [ "$#" -ne 1 ]; then
    echo "Usage: vllmctl logs <name>" >&2
    exit 1
  fi

  docker logs -f "$1"
}

cmd_stop() {
  require_docker

  if [ "$#" -lt 1 ]; then
    echo "Usage: vllmctl stop <name> [name...]" >&2
    exit 1
  fi

  docker stop "$@"
}

cmd_rm() {
  require_docker

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
  local warnings=0

  add_error() {
    echo "Error: $*" >&2
    errors=$((errors + 1))
  }

  add_warning() {
    echo "Warning: $*" >&2
    warnings=$((warnings + 1))
  }

  if ! jq empty "$REGISTRY" >/dev/null 2>&1; then
    add_error "Registry is not valid JSON: $REGISTRY"
    echo "vllm doctor found $errors error(s) and $warnings warning(s)." >&2
    exit 1
  fi

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
  bad_routes="$(jq -r '.models[] | select(((.route | startswith("/")) | not) or (.route | endswith("/"))) | .name + " -> " + .route' "$REGISTRY")"
  if [ -n "$bad_routes" ]; then
    echo "Routes must start with / and must not end with /:" >&2
    echo "$bad_routes" | sed 's/^/  /' >&2
    errors=$((errors + 1))
  fi

  local total_gpu
  total_gpu="$(jq -r '[.models[].gpuMemoryUtilization // 0] | add // 0' "$REGISTRY")"
  if jq -e '[.models[].gpuMemoryUtilization // 0] | add > 1' "$REGISTRY" >/dev/null; then
    add_warning "configured GPU utilization total is $total_gpu (> 1.0)."
  fi

  local docker_ok=0
  if ! command -v docker >/dev/null 2>&1; then
    add_error "docker is not on PATH."
  elif ! docker info >/dev/null 2>&1; then
    add_error "Docker daemon is not reachable. Is Docker running?"
  else
    docker_ok=1
  fi

  if [ "$docker_ok" -eq 1 ]; then
    local runtimes
    runtimes="$(docker info --format '{{json .Runtimes}}' 2>/dev/null || true)"
    if ! grep -q '"nvidia"' <<<"$runtimes"; then
      add_warning "Docker does not report an NVIDIA runtime; vllmctl start uses --gpus and may fail."
    fi

    if ! command -v nvidia-smi >/dev/null 2>&1; then
      add_warning "nvidia-smi is not on PATH; cannot verify host GPU visibility."
    elif ! nvidia-smi >/dev/null 2>&1; then
      add_warning "nvidia-smi failed on the host; check NVIDIA driver health."
    fi

    local port_check_unavailable=0
    while IFS=$'\t' read -r name port; do
      if docker_exists "$name" && docker_running "$name"; then
        continue
      fi

      local listeners=""
      local port_status=0
      listeners="$(port_listeners "$port")" || port_status=$?
      if [ "$port_status" -eq 2 ]; then
        port_check_unavailable=1
        break
      fi

      if [ -n "$listeners" ]; then
        echo "Port $port for configured model '$name' is already in use:" >&2
        echo "$listeners" | sed 's/^/  /' >&2
        errors=$((errors + 1))
      fi
    done < <(jq -r '.models[] | [.name, .port] | @tsv' "$REGISTRY")

    if [ "$port_check_unavailable" -eq 1 ]; then
      add_warning "Neither lsof nor ss is available; skipping configured port checks."
    fi

    while IFS=$'\t' read -r name expected_hash; do
      if docker_exists "$name"; then
        local existing_hash
        existing_hash="$(container_label "$name" dotfiles.vllm.config-hash)"
        if [ "$existing_hash" != "$expected_hash" ]; then
          add_warning "Stale container: $name (recreate with: vllmctl recreate $name)"
        fi
      fi
    done < <(jq -r '.models[] | [.name, .configHash] | @tsv' "$REGISTRY")

    while IFS= read -r container_name; do
      [ -z "$container_name" ] && continue
      if ! jq -e --arg name "$container_name" '.models[] | select(.name == $name)' "$REGISTRY" >/dev/null; then
        add_warning "Orphan vLLM container not in registry: $container_name (remove with: docker rm -f $container_name)"
      fi
    done < <(docker ps -a --filter label=dotfiles.service=vllm --format '{{.Names}}')

    while IFS= read -r image; do
      [ -z "$image" ] && continue
      if ! docker image inspect "$image" >/dev/null 2>&1; then
        add_warning "Docker image is not present locally; first start will pull it: $image"
      fi
    done < <(jq -r '.models[].image' "$REGISTRY" | sort -u)

    local smoke_image=""
    while IFS= read -r image; do
      if docker image inspect "$image" >/dev/null 2>&1; then
        smoke_image="$image"
        break
      fi
    done < <(jq -r '.models[].image' "$REGISTRY" | sort -u)

    if [ -n "$smoke_image" ]; then
      if ! docker run --rm --pull=never --gpus all --entrypoint /bin/sh "$smoke_image" -c 'if command -v nvidia-smi >/dev/null 2>&1; then nvidia-smi -L >/dev/null; else test -e /dev/nvidiactl && ls /dev/nvidia[0-9]* >/dev/null 2>&1; fi' >/dev/null 2>&1; then
        add_error "Docker GPU smoke test failed with image: $smoke_image"
      fi
    else
      add_warning "Skipping Docker GPU smoke test because none of the configured images are present locally."
    fi
  fi

  if [ "$errors" -gt 0 ]; then
    echo "vllm doctor found $errors error(s) and $warnings warning(s)." >&2
    exit 1
  fi

  if [ "$warnings" -gt 0 ]; then
    echo "vllm doctor OK with $warnings warning(s)."
  else
    echo "vllm doctor OK"
  fi
}

main() {
  local command="${1:-}"
  if [ -z "$command" ]; then
    usage
    exit 1
  fi
  shift

  case "$command" in
    update)
      cmd_update "$@"
      ;;
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
