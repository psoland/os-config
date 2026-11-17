import assert from "node:assert/strict"
import { EventEmitter } from "node:events"
import { readFile } from "node:fs/promises"
import test from "node:test"
import { createSender, setup } from "../../config/opencode/plugins/herdr-agent/bridge.mjs"

const tick = () => new Promise(setImmediate)

function harness({ status = "idle", permissions = [], forms = [], pauseSync } = {}) {
  const calls = []
  let listener, effect
  let route = { type: "session", sessionID: "root" }
  const context = {
    location: { directory: "/worktree" },
    data: {
      listen: (callback) => { listener = callback; return () => calls.push({ unsubscribe: true }) },
      session: {
        root: (id) => id.startsWith("child") ? "root" : id,
        family: () => ["root", "child"],
        status: () => status,
        get: () => ({ location: { directory: "/worktree" } }),
        permission: { sync: async () => { await pauseSync }, list: () => permissions },
        form: { sync: async () => { await pauseSync }, list: () => forms },
      },
    },
    ui: {
      router: { current: () => route },
      slot: (claim) => { claim.render(); return () => calls.push({ unregister: true }) },
    },
  }
  const cleanup = setup(context, {
    send: async (method, params) => calls.push({ method, ...params }),
    effect: (callback) => { effect = callback; callback() },
  })
  return {
    calls, cleanup,
    event: (type, data = { sessionID: "root" }) => listener({ details: { type, data } }),
    route: (id) => { route = id ? { type: "session", sessionID: id } : { type: "home" }; effect() },
  }
}

const states = (h) => h.calls.filter((call) => call.method === "pane.report_agent")
const sessions = (h) => h.calls.filter((call) => call.method === "pane.report_agent_session")

test("Herdr is a V2 CLI-only plugin, not a server hook with pane-global environment", async () => {
  const base = new URL("../../config/opencode/plugins/herdr-agent/", import.meta.url)
  const manifest = JSON.parse(await readFile(new URL("package.json", base), "utf8"))
  assert.deepEqual(manifest.exports, { "./tui": "./tui.js" })
  const entry = await readFile(new URL("tui.js", base), "utf8")
  assert.match(entry, /@opencode\/plugin\/tui/)
  assert.match(entry, /createEffect/)
})

test("attaching reports session identity before state and ignores unrelated server conversations", async () => {
  const h = harness()
  assert.equal(h.calls[0].method, "pane.report_agent_session")
  assert.equal(h.calls[0].agent_session_id, "root")
  assert.equal(h.calls[0].session_start_source, "new")
  h.event("session.execution.started", { sessionID: "unrelated" })
  h.event("session.created", { sessionID: "unrelated" })
  assert.deepEqual(states(h).map((call) => call.state), ["idle"])
  await tick()
})

test("reports root working/completion, but never lets child completion finish the parent", async () => {
  const h = harness()
  h.event("session.execution.started")
  h.event("session.execution.succeeded", { sessionID: "child" })
  assert.equal(states(h).at(-1).state, "working")
  h.event("session.execution.succeeded")
  assert.equal(states(h).at(-1).state, "idle")
  assert.ok(states(h).every((call) => call.agent_session_id === "root"))
  await tick()
})

test("multiple permission/form requests, including children, remain blocked until all resolve", async () => {
  const h = harness({ status: "running" })
  h.event("permission.asked", { sessionID: "root", id: "p" })
  h.event("form.created", { form: { sessionID: "child", id: "f" } })
  h.event("permission.replied", { sessionID: "root", requestID: "p" })
  assert.equal(states(h).at(-1).state, "blocked")
  h.event("form.cancelled", { sessionID: "child", id: "f" })
  assert.equal(states(h).at(-1).state, "working")
  await tick()
})

test("recovers running state and input requests when attaching to an existing conversation", async () => {
  const h = harness({ status: "running", permissions: [{ id: "p" }], forms: [{ id: "f" }] })
  assert.equal(states(h).at(-1).state, "working")
  await tick()
  assert.equal(states(h).at(-1).state, "blocked")
})

test("late initial snapshots cannot resurrect resolved requests", async () => {
  const h = harness({ permissions: [{ id: "p" }], forms: [{ id: "f" }] })
  for (const sessionID of ["root", "child"]) {
    h.event("permission.replied", { sessionID, requestID: "p" })
    h.event("form.replied", { sessionID, id: "f" })
  }
  await tick()
  assert.deepEqual(states(h).map((call) => call.state), ["idle"])
})

test("failures block, a new execution clears failure, and interruption clears pending state", async () => {
  const h = harness()
  h.event("session.execution.failed")
  assert.equal(states(h).at(-1).state, "blocked")
  h.event("session.execution.started")
  assert.equal(states(h).at(-1).state, "working")
  h.event("permission.asked", { sessionID: "child", id: "p" })
  h.event("session.execution.interrupted")
  assert.equal(states(h).at(-1).state, "idle")
  await tick()
})

test("interruption invalidates a delayed snapshot of old pending requests", async () => {
  let release
  const pauseSync = new Promise((resolve) => { release = resolve })
  const h = harness({ permissions: [{ id: "old" }], pauseSync })
  h.event("session.execution.interrupted")
  release()
  await tick()
  assert.equal(states(h).at(-1).state, "idle")
})

test("navigation replaces the session ref; background conversations cannot steal the pane", async () => {
  const h = harness()
  h.route("other")
  h.event("session.execution.started")
  assert.equal(states(h).at(-1).agent_session_id, "other")
  h.route("child")
  assert.equal(sessions(h).at(-1).agent_session_id, "root")
  assert.equal(states(h).at(-1).state, "working")
  const count = sessions(h).length
  h.route("root")
  assert.equal(sessions(h).length, count)
  // Returning home retains the last root's background completion reporting.
  h.route()
  h.event("session.execution.succeeded")
  assert.equal(states(h).at(-1).state, "idle")
  await tick()
})

test("cleanup unsubscribes and suppresses late events, effects and snapshots", async () => {
  const h = harness({ permissions: [{ id: "late" }] })
  const count = states(h).length
  h.cleanup()
  h.event("session.execution.started")
  h.route("other")
  await tick()
  assert.equal(states(h).length, count)
  assert.equal(h.calls.filter((call) => call.unsubscribe || call.unregister).length, 2)
})

test("transport captures the client's environment and serializes the official socket protocol", async () => {
  const sockets = [], writes = [], paths = []
  const env = { HERDR_ENV: "1", HERDR_PANE_ID: "w1:p2", HERDR_SOCKET_PATH: "/tmp/herdr-test.sock" }
  const sender = createSender(env, (path, onConnect) => {
    paths.push(path)
    const socket = new EventEmitter()
    socket.setTimeout = (ms, callback) => { assert.equal(ms, 500); socket.timeout = callback }
    socket.destroy = () => {}
    socket.write = (line) => writes.push(JSON.parse(line))
    sockets.push(socket)
    queueMicrotask(onConnect)
    return socket
  })
  env.HERDR_PANE_ID = "wrong-pane"
  const first = sender("pane.report_agent_session", { agent_session_id: "root", session_start_source: "new" })
  const second = sender("pane.report_agent", { agent_session_id: "root", state: "working" })
  await tick()
  assert.equal(writes.length, 1)
  sockets[0].emit("data", "{}")
  await first
  await tick()
  assert.equal(writes.length, 2)
  sockets[1].emit("data", "{}")
  await second
  assert.ok(writes.every((request) => request.params.pane_id === "w1:p2"))
  assert.ok(writes.every((request) => request.params.source === "herdr:opencode" && request.params.agent === "opencode"))
  assert.ok(writes[1].params.seq > writes[0].params.seq)
  assert.deepEqual(paths, ["/tmp/herdr-test.sock", "/tmp/herdr-test.sock"])
})

test("transport is inert outside Herdr and recovers from socket failures/timeouts", async () => {
  assert.equal(createSender({}), undefined)
  assert.equal(createSender({ HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1" }), undefined)
  let calls = 0
  const send = createSender({ HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", HERDR_SOCKET_PATH: "/absent" }, () => {
    calls++
    throw new Error("Herdr stopped")
  })
  await send("pane.report_agent", { state: "idle" })
  await send("pane.report_agent", { state: "working" })
  assert.equal(calls, 2)
  let timeouts = 0
  const timeoutSender = createSender({ HERDR_ENV: "1", HERDR_PANE_ID: "w1:p1", HERDR_SOCKET_PATH: "/stalled" }, () => {
    const socket = new EventEmitter()
    socket.destroy = () => {}
    socket.setTimeout = (_ms, finish) => { timeouts++; queueMicrotask(finish) }
    return socket
  })
  await timeoutSender("pane.report_agent", { state: "idle" })
  await timeoutSender("pane.report_agent", { state: "working" })
  assert.equal(timeouts, 2)
})
