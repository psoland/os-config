# OpenCode V2 Plan

## Constraints

- Keep OpenCode V1 operational until V2 has been verified.
- Do not convert or remove `config/opencode/opencode.json` while V1 uses it.
- Keep `config/opencode/tui.json` and the V1 worktree session picker.
- Keep the V1 systemd service and any V1 API consumers until they are migrated separately.
- Use separate files for V2 client settings and V2 plugin implementations.

## Phase 1: Manage V2 CLI Configuration

1. Use the generated `~/.config/opencode/cli.json` as the migration baseline.
2. Add a repository-owned `config/opencode/cli.json` containing the desired V2 settings:
   - Catppuccin theme
   - `ctrl+x` leader
   - `ctrl+q` application exit
   - Custom newline bindings
   - Word-wrapped diffs
   - Hidden session sidebar
   - Visible scrollbar and thinking blocks
   - Animations
3. Do not include the V1 `tui-plugins/worktree-session-picker.js` path in the managed V2 config.
4. Decide how Home Manager should own `cli.json`:
   - Preferred: use an immutable Home Manager symlink and make the repository authoritative.
   - Alternative: install a writable copy if settings changed through the V2 TUI must persist, with an explicit policy for reconciling runtime changes.
5. Preserve the generated file before the first Home Manager deployment, then handle the existing-file collision deliberately.
6. Keep the existing Home Manager mappings for V1 `tui.json` and its plugin unchanged.
7. Add a separate Home Manager mapping for V2 `cli.json`.
8. Validate the managed file against `https://opencode.ai/v2/cli.json` and check startup logs for rejected fields or keybinding IDs.

## Phase 2: Port the Worktree Session Picker

1. Keep `config/opencode/tui-plugins/worktree-session-picker.js` as the V1 implementation.
2. Create a separate V2 plugin under `config/opencode/plugins/tui/`, using the same user-facing command name where practical.
3. Deploy it to `~/.config/opencode/plugins/tui/` so V2 discovers it without referencing the V1 plugin from `cli.json`.
4. Implement the plugin with `Plugin.define()` from `@opencode-ai/plugin/tui`.
5. Register its command with `context.keymap.layer()` and return the unregister function from `setup()`.
6. Inspect the installed V2 client types before implementing session filtering. Confirm:
   - The session location or directory field
   - How root and child sessions are represented
   - Whether `context.data.session.sync()` is required before listing
   - The return shape of `context.keymap.shortcuts("session.list")`
7. Resolve the active worktree from `context.location` or `context.data.location.default()`.
8. Preserve the existing behavior:
   - Show only root sessions for the active worktree
   - Sort by most recently updated
   - Group sessions by date
   - Show a useful empty state
   - Show a clear synchronization or API error
9. Use the native V2 APIs:
   - `context.data.session` for session data
   - `context.ui.dialog.select()` for selection
   - `context.ui.toast.show()` for feedback
   - `context.ui.router.navigate()` for navigation
10. Reuse the configured `session.list` shortcut if the V2 keymap API supports it reliably. Otherwise assign and document a dedicated binding.
11. Verify the plugin with:
   - The shared V2 service
   - `opencode2 --standalone`
   - Multiple worktrees
   - Root and child sessions
   - No matching sessions
   - Plugin reload and cleanup
   - A remote V2 server, if that is a supported workflow

## Phase 3: Review V2 Permissions

1. Keep the current V1 `permission: "allow"` setting while V1 behavior depends on it.
2. Before adopting a native V2 server config, define the intended policy explicitly rather than translating the blanket allow unchanged.
3. Preserve V2's sensitive defaults unless there is a concrete reason to override them:
   - Ask before external-directory access
   - Ask before reading `.env` and `.env.*`
   - Allow `.env.example`
4. Ensure built-in subagents retain their intended restrictions:
   - `explore` remains read-only and cannot launch subagents
   - `general` cannot launch nested subagents
   - Hidden maintenance agents remain denied normal tools
5. Add narrowly scoped allow rules only where repeated prompts create real friction.
6. Confirm effective ordering with `opencode2 debug agents`; the last matching rule wins.
7. Test representative operations for `read`, `edit`, `shell`, `subagent`, `skill`, and `external_directory` before relying on the policy.

## Phase 4: Verify Shared V1 Configuration in V2

1. Continue running `opencode2 debug config` after V2 upgrades to verify V1 compatibility normalization.
2. Confirm the custom `sol`, `luna`, and `terra` agents and their variants.
3. Correct stale agent descriptions when a safe V1-compatible config update is scheduled:
   - Luna's description says `high`, while its variant is `max`.
   - Terra's description says `default`, while its variant is `high`.
4. Authenticate the enabled `executor` MCP server if it is intended to be active.
5. Verify global commands, skills, and `AGENTS.md` discovery.
6. Treat failures in supported V1 configuration behavior as V2 compatibility bugs rather than rewriting the V1 config prematurely.

## Phase 5: Native V2 Migration

Start this phase only after V1 and V1 API consumers have been retired.

1. Back up the final shared V1 configuration.
2. Convert `agent` to `agents` and migrate each complete nested agent entry without mixing formats inside it.
3. Join model variants into `provider/model#variant` references.
4. Convert `permission` to an ordered `permissions` array using V2 action names.
5. Convert MCP entries to `mcp.servers`, invert `enabled` to `disabled`, and review OAuth behavior.
6. Keep compatible fields such as `default_agent` unchanged.
7. Validate the resulting effective configuration with `opencode2 debug config` and `opencode2 debug agents`.
8. Verify models, credentials, agents, permissions, MCP servers, commands, skills, and plugins before removing any V1-only files.

## Completion Criteria

- V1 continues to work unchanged until its planned retirement.
- V2 CLI settings are reproducible from the repository.
- V1 and V2 use separate worktree session picker implementations.
- V2 effective permissions match each agent's intended role.
- V2 reports no config or plugin compatibility warnings.
- Native V2 server configuration is adopted only after V1 is no longer consuming the shared config path.
