#!/usr/bin/env bash
# Waits until every given research run is finished, then prints a one-line summary per run
# and exits 0. Meant to be started with Claude Code's Bash `run_in_background: true`: the
# harness re-invokes the agent when this exits, which is the "callback" MCP cannot push.
#
#   wait-for-research.sh <run_id> [<run_id> ...]
#
# Env:   RESEARCH_ENGINE_URL   (default http://10.142.11.201/mcp)
#        RESEARCH_POLL_SECONDS (default 30; only used when the server cannot hold a long-poll)
#        RESEARCH_MAX_MINUTES  (default 150; the deep effort's deadline is 2h)
# Token: ~/.config/research-engine/token (chmod 600), or RESEARCH_ENGINE_TOKEN.
set -euo pipefail

[ "$#" -ge 1 ] || { echo "usage: $0 <run_id> [<run_id> ...]" >&2; exit 2; }
url="${RESEARCH_ENGINE_URL:-http://10.142.11.201/mcp}"
poll="${RESEARCH_POLL_SECONDS:-30}"
max_minutes="${RESEARCH_MAX_MINUTES:-150}"
token="${RESEARCH_ENGINE_TOKEN:-$(cat "$HOME/.config/research-engine/token" 2>/dev/null || true)}"
[ -n "$token" ] || { echo "no token: put one in ~/.config/research-engine/token" >&2; exit 2; }

ids_json=$(printf '"%s",' "$@"); ids_json="[${ids_json%,}]"
body="{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"research_status\",\"arguments\":{\"run_ids\":$ids_json,\"wait\":55,\"until\":\"done\"}}}"
here="$(cd "$(dirname "$0")" && pwd)"
deadline=$(( $(date +%s) + max_minutes * 60 ))

while :; do
  # Long-poll: the server holds the call until every run is done or 55 s pass.
  started=$(date +%s)
  response=$(curl -sS --max-time 75 "$url" -H "Authorization: Bearer $token" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d "$body" || true)
  if summary=$(printf '%s' "$response" | python3 -I "$here/summarize_status.py" "$#"); then
    echo "$summary"
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "gave up after ${max_minutes} min; last status:"; printf '%s\n' "$response" | python3 -I "$here/summarize_status.py" "$#" --force || true
    exit 1
  fi
  # Only sleep when the server answered at once (long-poll capacity full, or an error).
  [ $(( $(date +%s) - started )) -ge 5 ] || sleep "$poll"
done
