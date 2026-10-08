import { execFile } from "node:child_process"
import { randomUUID } from "node:crypto"
import { promisify } from "node:util"

// This runs in the CLI, never the shared server. Capture the CLI's socket and
// pane once; its location or tmux session name may change later.
export function createSender(env = process.env, pid = process.pid, execute = promisify(execFile)) {
  const socket = /^(.*),\d+,\d+$/.exec(env.TMUX ?? "")?.[1]
  const pane = env.TMUX_PANE
  if (!socket || !/^%\d+$/.test(pane ?? "")) return undefined
  let tail = Promise.resolve()
  return (message) => {
    const args = ["--socket", socket, message.command]
    if (message.command === "state") {
      args.push(message.state, "--event", message.event, "--at", String(message.at), "--pid", String(pid))
    }
    args.push("--pane", pane, "--source", message.source)
    const next = tail.then(() => execute("tmux-agent", args, { timeout: 10000, windowsHide: true }))
    // Preserve ordering even if tmux exited or the helper is not installed yet.
    tail = next.catch(() => {})
    return next
  }
}

export function setup(context, {
  send = createSender(),
  owner = `opencode:${process.pid}:${randomUUID().slice(0, 8)}`,
  effect = (callback) => callback(),
} = {}) {
  if (!send) return () => {}
  let stopped = false
  const tracked = new Set()
  const sources = new Map()
  const settled = new Set()

  function emit(message) {
    // Indicators must never interfere with the agent if tmux/helper is absent.
    try { Promise.resolve(send(message)).catch(() => {}) } catch {}
  }

  function state(root, source, value, event) {
    if (stopped) return
    sources.set(source, root)
    emit({ command: "state", source, state: value, event, at: Date.now() })
  }

  function remove(source) {
    sources.delete(source)
    emit({ command: "remove", source })
  }

  const execution = (root) => `${owner}:${root}:execution`
  const request = (session, kind, id) => `${owner}:${session}:${kind}:${id}`

  function needsInput(root, session, kind, id) {
    const source = request(session, kind, id)
    if (!id || settled.has(source) || sources.has(source)) return
    state(root, source, "needs-input", `${kind}:${id}`)
  }

  function resolve(session, kind, id) {
    const source = request(session, kind, id)
    settled.add(source)
    remove(source)
  }

  async function observe(sessionID) {
    const root = context.data.session.root(sessionID)
    if (stopped || tracked.has(root)) return
    tracked.add(root)
    // An idle conversation at startup is not a new completion notification.
    if (context.data.session.status(root) === "running") {
      state(root, execution(root), "running", "initial-running")
    }
    // Recover pending prompts when attaching/reloading. Keep each request as a
    // separate source: resolving one must not re-notify an acknowledged sibling.
    const family = new Set([root, ...context.data.session.family(root)])
    await Promise.all([...family].map(async (session) => {
      const location = context.data.session.get(session)?.location ?? context.location
      await Promise.allSettled([
        context.data.session.permission.sync(session),
        context.data.session.form.sync(session, location),
      ])
      if (stopped) return
      for (const permission of context.data.session.permission.list(session) ?? []) {
        needsInput(root, session, "permission", permission.id)
      }
      for (const form of context.data.session.form.list(session, location) ?? []) {
        needsInput(root, session, "form", form.id)
      }
    }))
  }

  const unsubscribe = context.data.listen(({ details: event }) => {
    if (stopped) return
    const data = event.data
    const session = data?.sessionID ?? data?.form?.sessionID
    if (!session) return
    const root = context.data.session.root(session)
    if (!tracked.has(root)) return
    if (event.type === "permission.asked") needsInput(root, session, "permission", data.id)
    else if (event.type === "permission.replied") resolve(session, "permission", data.requestID)
    else if (event.type === "form.created") needsInput(root, session, "form", data.form.id)
    else if (event.type === "form.replied" || event.type === "form.cancelled") resolve(session, "form", data.id)
    // A subagent finishing is not the parent conversation finishing. Its input
    // requests above still contribute to the parent's attention indicator.
    else if (session === root) {
      if (event.type === "session.execution.started"
        || (event.type === "session.status" && ["busy", "retry"].includes(data.status.type))) {
        state(root, execution(root), "running", event.id)
      } else if (event.type === "session.execution.succeeded") {
        state(root, execution(root), "finished", event.id)
      } else if (event.type === "session.execution.failed") {
        state(root, execution(root), "needs-input", event.id)
      } else if (event.type === "session.execution.interrupted") {
        for (const [source, target] of sources) {
          if (target === root) {
            settled.add(source)
            remove(source)
          }
        }
      }
    }
  })

  // Mount under a Solid owner; observe route changes without a polling timer.
  // Previously displayed conversations stay tracked if they run in background.
  const unregister = context.ui.slot({
    append: "app",
    render: () => {
      effect(() => {
        const route = context.ui.router.current()
        if (route.type === "session") void observe(route.sessionID).catch(() => {})
      })
      return null
    },
  })

  return () => {
    stopped = true
    unsubscribe()
    unregister()
    for (const source of [...sources.keys()]) remove(source)
  }
}
