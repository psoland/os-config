import assert from "node:assert/strict"
import test from "node:test"
import { listWorktreeSessions, sessionOptions, setup } from "../../config/opencode/plugins/worktree-session-picker/picker.mjs"

const location = { directory: "/server/repo/worktree" }
const session = (id, updated = 1, extra = {}) => ({ id, title: id, location, time: { updated }, ...extra })
const page = (data, next) => ({ data, cursor: { next } })

function harness(sessions = []) {
  const calls = { queries: [], dialogs: [], toasts: [], routes: [], clears: 0, unregisters: 0 }
  let command
  const context = {
    location,
    client: {
      location: { get: async () => location },
      session: { list: async (query) => { calls.queries.push(query); return page(sessions) } },
    },
    data: {
      session: { get: () => undefined },
      location: { default: () => location },
    },
    keymap: { layer: (input) => { command = input().commands[0] } },
    ui: {
      slot: (claim) => {
        assert.equal(claim.append, "app")
        assert.equal(claim.render(), null)
        return () => { calls.unregisters++ }
      },
      router: { current: () => ({ type: "home" }), navigate: (route) => calls.routes.push(route) },
      toast: { show: (toast) => calls.toasts.push(toast) },
      dialog: {
        select: async (input) => { calls.dialogs.push(input); return input.options[0]?.value },
        clear: () => { calls.clears++ },
      },
    },
  }
  return { context, calls, start() { return { cleanup: setup(context), command } } }
}

function deferred() {
  let resolve
  const promise = new Promise((done) => { resolve = done })
  return { promise, resolve }
}

test("filters on the server before limiting, follows all cursors, deduplicates and sorts", async () => {
  const queries = []
  const first = Array.from({ length: 100 }, (_, i) => session(`first-${i}`, i))
  const responses = [page(first, "page-2"), page([session("old-but-updated", 500), session("first-0", 300)], "page-3"), page([session("last", 200)])]
  const client = { session: { list: async (input) => { queries.push(input); return responses.shift() } } }
  const sessions = await listWorktreeSessions(client, location)
  assert.equal(sessions.length, 102)
  assert.deepEqual(sessions.slice(0, 3).map((s) => s.id), ["old-but-updated", "first-0", "last"])
  assert.deepEqual(queries, [
    { directory: location.directory, workspace: undefined, parentID: null, order: "desc", limit: 100 },
    { cursor: "page-2", limit: 100 },
    { cursor: "page-3", limit: 100 },
  ])
})

test("excludes children, other worktrees and distinct workspaces with identical paths", async () => {
  const h = harness([
    session("root"), session("child", 5, { parentID: "root" }),
    session("other", 10, { location: { directory: "/server/repo/other" } }),
    session("workspace", 20, { location: { ...location, workspaceID: "remote-workspace" } }),
  ])
  assert.deepEqual((await listWorktreeSessions(h.context.client, location)).map((s) => s.id), ["root"])
  const workspace = { ...location, workspaceID: "remote-workspace" }
  assert.deepEqual((await listWorktreeSessions(h.context.client, workspace)).map((s) => s.id), ["workspace"])
  assert.equal(h.calls.queries[1].workspace, "remote-workspace")
})

test("reports repeated cursors instead of looping forever", async () => {
  const client = { session: { list: async () => page([], "repeat") } }
  await assert.rejects(listWorktreeSessions(client, location), /repeated.*cursor/)
})

test("does not present a partial list when a later page fails", async () => {
  const h = harness()
  let requests = 0
  h.context.client.session.list = async () => {
    if (requests++ === 0) return page([session("partial")], "next")
    throw new Error("Server unavailable on page 2")
  }
  await h.start().command.run()
  assert.equal(h.calls.dialogs.length, 0)
  assert.equal(h.calls.toasts[0].variant, "error")
  assert.match(h.calls.toasts[0].message, /page 2/)
})

test("groups by local calendar day and supplies a title for untitled sessions", () => {
  const now = new Date(2026, 7, 20, 12)
  const yesterday = new Date(2026, 7, 19, 12)
  assert.deepEqual(sessionOptions([session("today", now.getTime(), { title: undefined }), session("yesterday", yesterday.getTime())], now), [
    { title: "Untitled session", value: "today", category: "Today" },
    { title: "yesterday", value: "yesterday", category: yesterday.toDateString() },
  ])
})

test("registers palette, slash command and a dedicated binding without reusing display shortcuts", () => {
  const h = harness()
  const { command, cleanup } = h.start()
  assert.equal(command.id, "session.list.worktree")
  assert.equal(command.bind, "<leader>w")
  assert.equal(command.palette, true)
  assert.equal(command.slash.name, "worktree-sessions")
  assert.equal(typeof cleanup, "function")
  cleanup()
  assert.equal(h.calls.unregisters, 1)
})

test("uses active session location and resolves paths on the server", async () => {
  const h = harness([session("root")])
  const active = { directory: "/server/symlink", workspaceID: "workspace" }
  h.context.ui.router.current = () => ({ type: "session", sessionID: "root" })
  h.context.data.session.get = () => ({ location: active })
  h.context.client.location.get = async (input) => {
    assert.deepEqual(input, { location: { directory: active.directory, workspace: active.workspaceID } })
    return location
  }
  await h.start().command.run()
  assert.equal(h.calls.dialogs[0].current, "root")
  assert.deepEqual(h.calls.routes, [{ type: "session", sessionID: "root" }])
})

test("falls back to default location on the home screen", async () => {
  const h = harness()
  h.context.location = undefined
  h.context.client.location.get = async (input) => {
    assert.equal(input.location.directory, location.directory)
    return location
  }
  await h.start().command.run()
  assert.equal(h.calls.toasts[0].variant, "info")
  assert.equal(h.calls.dialogs.length, 0)
})

test("canceling a selection does not navigate", async () => {
  const h = harness([session("root")])
  h.context.ui.dialog.select = async () => undefined
  await h.start().command.run()
  assert.deepEqual(h.calls.routes, [])
})

test("location synchronization failures are visible, not treated as an empty list", async () => {
  const h = harness()
  h.context.client.location.get = async () => { throw new Error("Location disconnected") }
  await h.start().command.run()
  assert.equal(h.calls.toasts[0].variant, "error")
  assert.equal(h.calls.toasts[0].message, "Location disconnected")
})

test("declared API errors expose their message rather than [object Object]", async () => {
  const h = harness()
  h.context.client.session.list = async () => {
    throw { _tag: "InvalidRequestError", message: "Invalid session cursor" }
  }
  await h.start().command.run()
  assert.equal(h.calls.toasts[0].variant, "error")
  assert.equal(h.calls.toasts[0].message, "Invalid session cursor")
})

test("prevents duplicate requests while the picker is loading", async () => {
  const h = harness()
  const pending = deferred()
  let count = 0
  h.context.client.session.list = async () => { count++; return pending.promise }
  const { command } = h.start()
  const first = command.run()
  await command.run()
  pending.resolve(page([]))
  await first
  assert.equal(count, 1)
})

test("cleanup aborts requests and suppresses late dialogs and error toasts", async () => {
  const h = harness()
  const pending = deferred()
  let signal
  h.context.client.session.list = async (_input, options) => { signal = options.signal; return pending.promise }
  const { command, cleanup } = h.start()
  const running = command.run()
  await new Promise(setImmediate)
  cleanup()
  assert.equal(signal.aborted, true)
  pending.resolve(page([session("late")]))
  await running
  assert.deepEqual(h.calls.dialogs, [])
  assert.deepEqual(h.calls.toasts, [])
})

test("cleanup closes an open picker and prevents stale navigation after reload", async () => {
  const h = harness([session("root")])
  const pending = deferred()
  h.context.ui.dialog.select = () => pending.promise
  const { command, cleanup } = h.start()
  const running = command.run()
  await new Promise(setImmediate)
  cleanup()
  assert.equal(h.calls.clears, 1)
  pending.resolve("root")
  await running
  assert.deepEqual(h.calls.routes, [])
  await command.run()
  assert.equal(h.calls.queries.length, 1)
  const reloaded = h.start()
  h.context.ui.dialog.select = async () => "root"
  await reloaded.command.run()
  assert.equal(h.calls.routes.length, 1)
  reloaded.cleanup()
})
