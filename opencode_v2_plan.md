# OpenCode V2 Migration

## Scope and decisions

- Repository settings are the recovery baseline. No V1 state backups or rollback machinery.
- Retire the unused V1 systemd service on port 4090 and its Tailscale routes.
- Keep the V1 CLI, `tui.json`, and picker for existing launchers and non-V2 hosts.
- Install the pinned V2 beta on supported Linux hosts alongside V1. Use V2's own
  per-user background service, not another systemd server. `--standalone` remains available.
- Keep shared server configuration V1-compatible until the remaining V1 CLI
  launchers are migrated. Native V2 server syntax is optional, not a prerequisite.

## Implementation plan

1. Verify contracts against `0.0.0-beta-18684`, pinned in `packages/opencode2.nix`.
2. Manage V2 CLI preferences and a separate V2 worktree picker through Home Manager.
3. List root sessions with server-side directory/workspace filtering, then follow
   every `cursor.next` page. Sort the complete result by update time and group by date.
4. Remove blanket global and custom-agent permission overrides so V2's sensitive
   defaults and built-in agent restrictions survive V1 compatibility normalization.
   Correct the Luna/Terra descriptions without changing their models or variants.
5. Remove V1 service configuration and its obsolete service aliases/routes.
6. Test pagination, worktree isolation, cancellation, failures, reload cleanup,
   effective permissions, config discovery, and both V2 server modes. Evaluate Home
   Manager for Linux and ensure non-Linux configurations remain valid.

## Verified beta contracts

- `context.data.session.list()` is a cache, not a complete server listing.
  `sync(sessionID)` refreshes one session; it cannot synchronize the global list.
- Use `context.client.session.list({ directory, workspace, parentID: null,
  order: "desc", limit: 100 })`, then follow `response.cursor.next`. The promise
  client returns `{ data, cursor }` and throws on API errors.
- Session location is `session.location` (`directory` and optional `workspaceID`).
  Child sessions have `parentID`; timestamps are epoch milliseconds.
- Keymap registration is `context.keymap.layer(() => layer)`. It returns `void`.
  In this beta, calling it directly in `setup()` fails with `Keymap.Provider is
  missing`. Mount it through `context.ui.slot({ append: "app", render })` instead.
  Removing that slot disposes the layer; plugin cleanup also cancels pending work.
- `shortcuts()` returns formatted display labels, not binding definitions. The
  picker uses explicit `<leader>w` (Ctrl+X, then W); `<leader>l` remains the built-in
  all-session picker. `/worktree-sessions` and the command palette also work.
- The pinned beta discovers flat files in `plugins/tui/`, including with remote
  servers. Deploy `plugins/tui/worktree-session-picker.js` there and keep helpers
  outside that discovery directory. No V1 plugin path is migrated into `cli.json`.
  Newer online docs describe a different package layout; it fails on this pin.
- The published CLI schema rejects custom command keys, so the picker binding
  lives in the plugin's `bind` declaration rather than in `cli.json`.
- V2 writes `cli.json` with an atomic rename. A Home Manager symlink would be
  replaced by a regular file. Instead, activation installs a writable copy from
  the repository, deliberately replacing generated settings without a backup.
  TUI changes last until the next activation; commit desired changes to
  `config/opencode/cli.json`. Close V2 clients before applying to avoid write races.

## Permissions

Omit blanket `permission: "allow"` globally and on Sol/Luna/Terra. This intentionally
changes the old unrestricted policy: ordinary tools use shipped defaults, external
paths and `.env` reads ask, and `.env.example` reads remain allowed. Built-in
`explore`, `general`, and maintenance-agent restrictions are not overridden.

These are tool permission rules, not a sandbox: shell commands still run with the
user's authority. Do not use `--auto` when verifying approval prompts. Existing saved
approvals and project-level rules may also affect the result.

## Deployment and verification

- Run `node --test tests/opencode/*.test.mjs`.
- Build the relevant Home Manager activation package, then activate it with V2
  clients closed. Activation resets `cli.json` to the repository baseline.
- On hosts that previously enabled V1, stop/disable `opencode.service` and remove
  only its `/` and `/opencode` Tailscale Serve routes to `127.0.0.1:4090`.
  Do not reset unrelated Tailscale routes.
- Run `opencode2 debug config`, `opencode2 debug agents`, and `opencode2 mcp list`.
  `executor` remains enabled; OAuth authentication, if needed, is an interactive
  follow-up (`opencode2 mcp auth executor`), not an automated credential change.
- Try `opencode2` and `opencode2 --standalone`, then `/worktree-sessions` in
  multiple worktrees, including a worktree with more than 100 root sessions.
- Remote selection uses server-provided location identity, never client-side
  filesystem canonicalization. Test `--server` if used in practice.

## Later: native V2-only cutover

The existing `oc`, `td c`, `tdl c`, and `ts` launchers still run V1. Once these and
any external V1 API clients have migrated, convert the shared server file:

1. `agent` -> `agents`; each complete entry uses `disabled`, `system`, etc.
2. Join agent model and variant as `provider/model#variant`.
3. Any explicit policy uses ordered `permissions` arrays and native action names.
4. MCP entries move under `mcp.servers`, with `enabled` inverted to `disabled`.
5. Keep `default_agent` and compatible commands, skills, and `AGENTS.md` mappings.
6. Verify effective config/agents before removing V1 packages and files.

No state preservation is required for this later cutover either.

## Validation results

- All 16 unit tests pass, covering pagination beyond 100 sessions, server-side filters, root/child
  and workspace isolation, deduplication, date grouping, API failures (including
  failures after the first page), cancellation, duplicate invocation, and cleanup.
- Published CLI schema validation passed. The pinned beta loaded the managed
  plugin from Home Manager's actual Nix-store symlink layout without warnings.
- Standalone TUI: verified startup, dedicated shortcut, and empty state.
- Shared service: created 105 roots in one Git worktree, 110 in another, and an
  imported child session. The real promise client returned every matching root,
  excluded the child/other worktree, and sorted a renamed old session first.
  The TUI found and navigated to a session beyond the first page.
- Checked 60 effective permission decisions from the running server, including
  `.env`, external directories, normal tools, and built-in agent restrictions.
  `debug config` normalized all three custom models/variants correctly. On this
  beta `debug agents` returned an empty list during initialization, so verification
  used the running server's agent API instead of trusting that empty result.
  The running server also discovered the managed `bro`/`hunk` commands and three
  global skills. Executor reports `needs_auth`; it was not silently disabled.
- Changed settings through the TUI, confirmed `cli.json` was writable, and ran
  the generated activation commands against the test config directory: the
  repository baseline was restored exactly.
- Evaluated all standalone Home Manager targets plus the work Mac's CLI activation
  configuration, and built the Spark activation package and ARM64 V2 package.
  Existing upstream Nix deprecation warnings remain.
- Stopped/disabled the V1 service on the current Spark and removed only its two
  verified Tailscale routes. Other hosts need activation/service retirement there.
- Full Home Manager activation is intentionally not run over unrelated in-progress
  changes in `flake.nix`, `flake.lock`, and `packages/deepseek-harness.nix`.
- Still requires user verification: provider login/model inference, interactive
  approval prompts, executor OAuth, and an actual remote-server workflow. No model
  requests or credential changes were made by these migration tests.
