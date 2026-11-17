import net from "node:net"
import { randomUUID } from "node:crypto"

// Only the terminal client has the right Herdr pane environment. Never run this
// in the shared OpenCode server, which may have been started in another pane.
export function createSender(env = process.env, connect = net.createConnection) {
  const pane = env.HERDR_PANE_ID
  const socket = env.HERDR_SOCKET_PATH
  if (env.HERDR_ENV !== "1" || !pane || !socket) return undefined
  let sequence = Date.now() * 1000
  let tail = Promise.resolve()
  return (method, params) => {
    const message = {
      id: `herdr:opencode:${randomUUID()}`,
      method,
      params: { ...params, pane_id: pane, source: "herdr:opencode", agent: "opencode", seq: ++sequence },
    }
    const next = tail.then(() => new Promise((resolve) => {
      let client
      const finish = () => { client?.destroy(); resolve() }
      try {
        client = connect(socket, () => { client.write(`${JSON.stringify(message)}\n`) })
        client.setTimeout(500, finish)
        client.once("data", finish)
        client.once("error", finish)
        client.once("end", finish)
        client.once("close", resolve)
      } catch { finish() }
    }))
    // A missing/stopped Herdr server must not break the agent or future reports.
    tail = next.catch(() => {})
    return next
  }
}

export function setup(context, {
  send = createSender(),
  effect = (callback) => callback(),
} = {}) {
  if (!send) return () => {}
  let stopped = false
  let active
  let lastState
  const roots = new Map()
  const settled = new Set()

  function emit(method, params) {
    if (stopped) return
    try { Promise.resolve(send(method, params)).catch(() => {}) } catch {}
  }

  function publish() {
    const root = roots.get(active)
    if (!root) return
    const state = root.pending.size || root.failed ? "blocked" : root.running ? "working" : "idle"
    if (state === lastState) return
    lastState = state
    emit("pane.report_agent", { state, agent_session_id: active })
  }

  const requestKey = (session, kind, id) => `${session}:${kind}:${id}`
  function pending(root, session, kind, id) {
    const key = requestKey(session, kind, id)
    if (id && !settled.has(key)) root.pending.add(key)
  }
  function resolve(root, session, kind, id) {
    const key = requestKey(session, kind, id)
    settled.add(key)
    root.pending.delete(key)
  }

  async function recover(id, root) {
    const generation = root.generation
    const family = new Set([id, ...context.data.session.family(id)])
    await Promise.all([...family].map(async (session) => {
      const location = context.data.session.get(session)?.location ?? context.location
      await Promise.allSettled([
        context.data.session.permission.sync(session),
        context.data.session.form.sync(session, location),
      ])
      if (stopped || generation !== root.generation) return
      for (const permission of context.data.session.permission.list(session) ?? []) {
        pending(root, session, "permission", permission.id)
      }
      for (const form of context.data.session.form.list(session, location) ?? []) {
        pending(root, session, "form", form.id)
      }
    }))
    publish()
  }

  const unsubscribe = context.data.listen(({ details: event }) => {
    if (stopped) return
    const data = event.data
    const session = data?.sessionID ?? data?.form?.sessionID
    if (!session) return
    const id = context.data.session.root(session)
    const root = roots.get(id)
    if (!root) return
    if (event.type === "permission.asked") pending(root, session, "permission", data.id)
    else if (event.type === "permission.replied") resolve(root, session, "permission", data.requestID)
    else if (event.type === "form.created") pending(root, session, "form", data.form.id)
    else if (event.type === "form.replied" || event.type === "form.cancelled") resolve(root, session, "form", data.id)
    // Child completions must not mark the parent idle; child requests still
    // contribute to its pending set until every request has been resolved.
    else if (session === id) {
      if (event.type === "session.execution.started") {
        root.running = true
        root.failed = false
      } else if (event.type === "session.execution.succeeded") {
        root.running = false
      } else if (event.type === "session.execution.failed") {
        root.running = false
        root.failed = true
      } else if (event.type === "session.execution.interrupted") {
        root.generation++
        root.running = false
        root.failed = false
        for (const key of root.pending) settled.add(key)
        root.pending.clear()
      } else if (event.type === "session.status") {
        root.running = ["busy", "retry", "running"].includes(data.status.type)
      }
    }
    publish()
  })

  const unregister = context.ui.slot({
    append: "app",
    render: () => {
      effect(() => {
        if (stopped) return
        const route = context.ui.router.current()
        if (route.type !== "session") return
        const id = context.data.session.root(route.sessionID)
        if (!id || id === active) return
        active = id
        lastState = undefined
        // Explicit navigation authorizes replacing this pane's session ref.
        // Merely observing unrelated server session.created events does not.
        emit("pane.report_agent_session", { agent_session_id: id, session_start_source: "new" })
        if (!roots.has(id)) {
          const root = { running: context.data.session.status(id) === "running", failed: false, pending: new Set(), generation: 0 }
          roots.set(id, root)
          void recover(id, root).catch(() => {})
        }
        publish()
      })
      return null
    },
  })

  return () => {
    stopped = true
    unsubscribe()
    unregister()
  }
}
