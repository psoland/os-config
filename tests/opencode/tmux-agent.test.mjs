import assert from "node:assert/strict"
import test from "node:test"
import { createSender, setup } from "../../config/opencode/plugins/tmux-agent/bridge.mjs"

function harness({ status = "idle", permissions = [], forms = [] } = {}) {
  const calls = []
  let listener, render, effect
  let route = { type: "session", sessionID: "root" }
  const context = {
    location: { directory: "/worktree" },
    data: {
      listen: (callback) => { listener = callback; return () => { calls.push({ unsubscribe: true }) } },
      session: {
        root: (id) => id === "child" ? "root" : id,
        family: () => ["root", "child"],
        status: () => status,
        get: () => ({ location: { directory: "/worktree" } }),
        permission: { sync: async () => {}, list: (id) => id === "root" ? permissions : [] },
        form: { sync: async () => {}, list: (id) => id === "root" ? forms : [] },
      },
    },
    ui: {
      router: { current: () => route },
      slot: (claim) => { render = claim.render; claim.render(); return () => { calls.push({ unregister: true }) } },
    },
  }
  const cleanup = setup(context, {
    owner: "test-client", send: async (message) => { calls.push(message) },
    effect: (callback) => { effect = callback; callback() },
  })
  let counter = 0
  return {
    context, calls, cleanup,
    event(type, data = { sessionID: "root" }, id = `event-${++counter}`) { listener({ details: { type, data, id } }) },
    route(value) { route = value; effect() },
    remount() { render() },
  }
}

const tick = () => new Promise(setImmediate)
const states = (h) => h.calls.filter((call) => call.command === "state")

test("idle at startup is not a completion; running, finished and input are distinct", async () => {
  const h = harness()
  await tick()
  assert.deepEqual(states(h), [])
  h.event("session.execution.started")
  h.event("session.execution.succeeded")
  h.event("permission.asked", { sessionID: "root", id: "approval" })
  assert.deepEqual(states(h).map((call) => call.state), ["running", "finished", "needs-input"])
  assert.equal(states(h)[0].source, states(h)[1].source)
  assert.notEqual(states(h)[1].source, states(h)[2].source)
})

test("recovers initial running state and pending permission/forms without duplicate mount notifications", async () => {
  const h = harness({ status: "running", permissions: [{ id: "p" }], forms: [{ id: "f" }] })
  await tick()
  assert.deepEqual(states(h).map((call) => call.state), ["running", "needs-input", "needs-input"])
  h.remount()
  await tick()
  assert.equal(states(h).length, 3)
})

test("filters other conversations and child completions but includes child input requests", async () => {
  const h = harness()
  h.event("session.execution.succeeded", { sessionID: "unrelated" })
  h.event("session.execution.succeeded", { sessionID: "child" })
  h.event("permission.asked", { sessionID: "child", id: "child-p" })
  assert.deepEqual(states(h).map((call) => call.state), ["needs-input"])
  h.event("permission.replied", { sessionID: "child", requestID: "child-p" })
  assert.equal(h.calls.at(-1).command, "remove")
  assert.equal(h.calls.at(-1).source, states(h)[0].source)
  await tick()
})

test("each input request is independent and duplicate/recovered requests do not re-notify", async () => {
  const h = harness()
  h.event("permission.asked", { sessionID: "root", id: "first" })
  h.event("permission.asked", { sessionID: "root", id: "second" })
  h.event("permission.asked", { sessionID: "root", id: "second" })
  h.event("permission.replied", { sessionID: "root", requestID: "first" })
  assert.equal(states(h).length, 2)
  assert.equal(h.calls.at(-1).source, states(h)[0].source)
  h.event("permission.asked", { sessionID: "root", id: "first" })
  assert.equal(states(h).length, 2)
  await tick()
})

test("V2 form.created wraps form, and replied/cancelled remove only that form", async () => {
  const h = harness()
  h.event("form.created", { form: { sessionID: "root", id: "question" } })
  h.event("form.cancelled", { sessionID: "root", id: "question" })
  assert.equal(states(h)[0].state, "needs-input")
  assert.deepEqual(h.calls.at(-1), { command: "remove", source: states(h)[0].source })
  await tick()
})

test("resolved prompts cannot be resurrected by a delayed initial synchronization", async () => {
  const h = harness({ permissions: [{ id: "p" }], forms: [{ id: "f" }] })
  h.event("permission.replied", { sessionID: "root", requestID: "p" })
  h.event("form.replied", { sessionID: "root", id: "f" })
  await tick()
  assert.deepEqual(states(h), [])
})

test("tracks route changes and previously displayed background conversations", async () => {
  const h = harness()
  h.route({ type: "session", sessionID: "another-root" })
  h.event("session.execution.succeeded", { sessionID: "root" })
  h.event("session.execution.started", { sessionID: "another-root" })
  h.route({ type: "home" })
  h.event("session.execution.succeeded", { sessionID: "another-root" })
  assert.deepEqual(states(h).map((call) => call.state), ["finished", "running", "finished"])
  await tick()
})

test("failures need attention; interruption removes running and blocked records", async () => {
  const h = harness()
  h.event("session.execution.failed")
  h.event("permission.asked", { sessionID: "child", id: "p" })
  h.event("session.execution.interrupted")
  assert.equal(states(h)[0].state, "needs-input")
  assert.equal(h.calls.filter((call) => call.command === "remove").length, 2)
  await tick()
})

test("busy/retry signal running, but idle events never manufacture a completion", async () => {
  const h = harness()
  h.event("session.status", { sessionID: "root", status: { type: "retry" } })
  h.event("session.status", { sessionID: "root", status: { type: "idle" } })
  h.event("session.idle")
  assert.deepEqual(states(h).map((call) => call.state), ["running"])
  await tick()
})

test("cleanup unregisters listeners/sources and ignores late snapshots/events", async () => {
  const h = harness({ permissions: [{ id: "late" }] })
  h.event("session.execution.started")
  h.cleanup()
  h.event("session.execution.succeeded")
  await tick()
  assert.deepEqual(states(h).map((call) => call.state), ["running"])
  assert.equal(h.calls.filter((call) => call.command === "remove").length, 1)
  assert.equal(h.calls.filter((call) => call.unsubscribe || call.unregister).length, 2)
})

test("helper transport uses the client socket/pane, argument arrays and serialized calls", async () => {
  const calls = []
  let release
  const pending = new Promise((resolve) => { release = resolve })
  const sender = createSender({ TMUX: "/tmp/socket,with-comma,123,0", TMUX_PANE: "%42" }, 99, async (...args) => {
    calls.push(args)
    if (calls.length === 1) await pending
  })
  const first = sender({ command: "state", state: "finished", source: "agent; not a shell command", event: "done", at: 123 })
  const second = sender({ command: "remove", source: "agent; not a shell command" })
  await tick()
  assert.equal(calls.length, 1)
  release()
  await Promise.all([first, second])
  assert.deepEqual(calls[0][1], [
    "--socket", "/tmp/socket,with-comma", "state", "finished", "--event", "done", "--at", "123", "--pid", "99",
    "--pane", "%42", "--source", "agent; not a shell command",
  ])
  assert.equal(calls[1][1][2], "remove")
})

test("missing tmux or a failed helper does not break the CLI or stop subsequent updates", async () => {
  assert.equal(createSender({}), undefined)
  assert.equal(createSender({ TMUX: "/tmp/socket,123,0", TMUX_PANE: "bad" }), undefined)
  let count = 0
  const sender = createSender({ TMUX: "/tmp/socket,123,0", TMUX_PANE: "%1" }, 99, async () => {
    if (++count === 1) throw new Error("tmux gone")
  })
  await assert.rejects(sender({ command: "remove", source: "one" }))
  await sender({ command: "remove", source: "two" })
  assert.equal(count, 2)
})
