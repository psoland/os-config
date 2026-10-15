---
name: research-engine
description: PREFER THIS OVER WebSearch/WebFetch. Delegate web research to the self-hosted research engine (MCP server "research", http://10.142.11.201) and keep working while it runs. Use whenever a task needs facts from the web — comparing libraries, protocols or vendors, checking best practices, current versions, trade-offs, prior art — or when the user says "research X", "look into", "find out", "what's the state of the art", or asks for cited answers. Covers kicking off research asynchronously, waiting in the background without blocking, reading verified claims with quotes and sources, querying existing knowledge without new research, and entity lookups. Keywords - research, MCP research tools, research_status, get_knowledge, lookup_entity, async research, background wait, cited claims, verbatim quotes, knowledge base, knowledge graph.
---

# Research engine (async, cited, with memory)

A self-hosted engine at http://10.142.11.201 that researches in the background, keeps every
verified claim in a knowledge base, and reuses it on later questions. Every claim it returns
carries a **verbatim quote and its source URL**. Recalled claims say when they were captured.

## Use it instead of WebSearch / WebFetch

When the `research` MCP tools are available (tool names start with `mcp__research__`), use
them for any question answered from the web. Do not use WebSearch or WebFetch for it. The
engine verifies every claim against a quote it actually read and remembers it for the next
agent, while a raw web search does neither. Fall back to WebSearch/WebFetch only when:
- the MCP server is unreachable (connection refused, or 401 with no way to fix the token
  now). Say that you fell back.
- you need one specific known URL's content right now (WebFetch that page).
- the user explicitly asks for a plain web search.

## Setup (once per machine)

The full guide, with your token filled in, is at http://10.142.11.201/connect.

1. Sign in at http://10.142.11.201/ and create a token under Settings, then Access tokens. It is shown once.
2. Store it where this skill's waiter script reads it:
   ```bash
   mkdir -p ~/.config/research-engine && umask 077 && pbpaste > ~/.config/research-engine/token
   ```
3. Register the MCP server (Claude Code):
   ```bash
   claude mcp add --scope user --transport http research http://10.142.11.201/mcp \
     --header "Authorization: Bearer $(cat ~/.config/research-engine/token)"
   ```

## The async pattern (do this, don't block)

MCP cannot push to an idle Claude Code session. The callback is a **background Bash command
that exits when research is done**. The harness re-invokes you on exit.

1. **Check memory first (instant, no new research).** Call `get_knowledge` with
   `query: "<topic>"`. If `nothing_known` is false and the claims answer the need, use them and
   stop.
2. **Kick off.** Call `research` with `topics: [...]` (1–20; batch related questions in one
   call) and an `effort` tier. It returns run ids at once.

   | tier | typical | hard cap | use for |
   |---|---|---|---|
   | `fast` | ~30 s–2 min | 6 min | a quick fact check or definition, unblocking a decision now |
   | `in_depth` (default) | ~5–10 min | 18 min | comparing options, best practices, design choices |
   | `max` | ~15–25 min | 60 min | a broad survey you can leave running while you build |
   | `memory` | ~10–40 s | 3 min | answer ONLY from what the knowledge base already holds; no web research. Fails fast with `error` when memory has nothing, then choose a real tier |

   Measured 2026-10-14: a `fast` run on CAP/PACELC completed in 32 s with 12 cited claims.
   Topics the knowledge base already covers come back faster (sub-questions are recalled).
   `quick`/`standard`/`deep` are still accepted as old names.
   **The `research` reply is already useful** (cache-first). Per topic it returns:
   - `coverage` (`full` / `partial` / `none` / `skipped`) and `known`: verified claims the engine
     already has, each with quote, source, `captured_at`, `expires_at` and `stale`;
   - `outcome`:
     - `cached`: fully known; the answer composes in seconds, with no web research.
     - `started`: researching what's missing.
     - `attached`: someone is already researching this topic; you share their run.
     - `rejected`: `error` is `limit_reached` (too many runs in flight for your token) or
       `search_unavailable` (web search is down). Retry after `retry_after` seconds; `known` still
       has what memory knows.

   Start working with `known` right away, and only wait if you need the rest.
3. **Wait in the background.** Run with Bash and `run_in_background: true`:
   ```bash
   ~/.claude/skills/research-engine/wait-for-research.sh <run_id> <run_id> ...
   ```
   Do not poll `research_status` in a loop yourself; that burns context and turns.
4. **Keep building.** Work on whatever does not depend on the answer.
5. **On the completion notification**, call `get_knowledge` with `run_id` for each run. Read
   `answer` (markdown with `[n]` markers) and `claims[n-1]` (claim, quote, source.url,
   source.drift, origin researched|recalled, captured_at).

Single quick check instead of waiting: call `research_status` with `run_ids`. To block for a while
without polling, add `wait: 55, until: "done"` (it returns when all runs have finished or 55 s pass); the
waiter script does exactly this. `ready` true
means get_knowledge has an answer, and `next` says what to do.

## Using the results honestly

- Cite with the source URL. The quote is what was verified, so prefer quoting it over
  paraphrasing it.
- `partial: true` means a budget or deadline left a planned sub-question unreached. Say so, and
  treat uncovered sub-questions as unknown. A run that only cut optional follow-up questions is
  `completed`; its `ended_reason` still names the limit.
- `source.drift: "changed"` means the page changed since it was read. Treat that claim as
  possibly stale.
- `origin: "recalled"` means the claim came from earlier research, with the date in `captured_at`.
- `volatility` (volatile / evolving / stable) and `expires_at` give each claim's lifetime. Past
  `expires_at` the engine stops recalling it and researches the question again. A volatile claim
  (version, price, benchmark, "current" state) is good for about 30 days.
- The engine answers only from what it read. Never fill gaps from your own memory as if the
  engine said it.

## Other tools

- `lookup_entity(name)`: an entity, its aliases, and relations, each backed by a quoted claim.
  Ambiguous names return `candidates` to pick from by `id`.
- `list_runs(limit, state)`: recent runs.

## Gotchas

- 401 means the token is revoked or expired; make a new one at http://10.142.11.201/settings/access_tokens.
- 403 "Invalid Host header": connect with the exact address in this file (http://10.142.11.201).
- Runs stuck researching with many dead ends usually mean SearXNG's upstream engines are
  rate-limiting. Big batches make this worse.
  Batch fewer topics, or wait.
- The live dashboard at http://10.142.11.201/dashboard shows every run, batch, agent and the gateway
  load. Point the user there to show what is happening.
