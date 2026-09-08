export const command = "session.list.worktree"

function sameLocation(a, b) {
  return a.directory === b.directory && a.workspaceID === b.workspaceID
}

// The cache is not a complete list. Filter on the server before limiting, then
// exhaust the cursor so large worktrees are not silently truncated either.
export async function listWorktreeSessions(client, location, signal) {
  const sessions = new Map()
  const cursors = new Set()
  let cursor
  do {
    signal?.throwIfAborted()
    const page = await client.session.list(
      cursor
        ? { cursor, limit: 100 }
        : {
            directory: location.directory,
            workspace: location.workspaceID,
            parentID: null,
            order: "desc",
            limit: 100,
          },
      { signal },
    )
    signal?.throwIfAborted()
    for (const session of page.data) {
      // Also enforce workspace identity when an omitted workspace query would
      // otherwise include multiple workspaces with the same directory string.
      if (!session.parentID && sameLocation(session.location, location)) {
        sessions.set(session.id, session)
      }
    }
    cursor = page.cursor.next
    if (cursor && cursors.has(cursor)) throw new Error("The server repeated a session-list cursor.")
    if (cursor) cursors.add(cursor)
  } while (cursor)

  return [...sessions.values()].sort((a, b) => b.time.updated - a.time.updated || a.id.localeCompare(b.id))
}

export function sessionOptions(sessions, now = new Date()) {
  return sessions.map((session) => {
    const date = new Date(session.time.updated).toDateString()
    return {
      title: session.title || "Untitled session",
      value: session.id,
      category: date === now.toDateString() ? "Today" : date,
    }
  })
}

export function setup(context) {
  const controller = new AbortController()
  let busy = false
  let selecting = false

  async function show() {
    if (busy || controller.signal.aborted) return
    busy = true
    try {
      const route = context.ui.router.current()
      const ref = (route.type === "session" && context.data.session.get(route.sessionID)?.location)
        || context.location || context.data.location.default()
      // Resolve on the connected server, not with the local filesystem: the
      // server may be remote, and the launch path may be a symlink.
      const location = await context.client.location.get(
        { location: { directory: ref.directory, workspace: ref.workspaceID } },
        { signal: controller.signal },
      )
      const sessions = await listWorktreeSessions(context.client, location, controller.signal)
      if (!sessions.length) {
        context.ui.toast.show({ variant: "info", message: "No sessions found for the current worktree." })
        return
      }
      selecting = true
      const sessionID = await context.ui.dialog.select({
        title: "Sessions in current worktree",
        current: route.type === "session" ? route.sessionID : undefined,
        options: sessionOptions(sessions),
      })
      if (sessionID !== undefined && !controller.signal.aborted) {
        context.ui.router.navigate({ type: "session", sessionID })
      }
    } catch (error) {
      if (!controller.signal.aborted) {
        context.ui.toast.show({
          variant: "error",
          title: "Failed to load worktree sessions",
          // Declared HTTP errors are thrown as JSON objects by this client.
          message: typeof error?.message === "string" ? error.message : JSON.stringify(error) ?? String(error),
        })
      }
    } finally {
      selecting = false
      busy = false
    }
  }

  // In beta-18684 setup() runs outside Keymap.Provider. Mount the layer in
  // the app slot so it has the provider and a Solid owner for automatic cleanup.
  // shortcuts() returns display labels, so do not treat them as bind syntax.
  const unregister = context.ui.slot({
    append: "app",
    render: () => {
      context.keymap.layer(() => ({
        commands: [{
          id: command,
          title: "Switch session (current worktree)",
          group: "Session",
          bind: "<leader>w",
          palette: true,
          slash: { name: "worktree-sessions" },
          run: show,
        }],
      }))
      return null
    },
  })

  return () => {
    controller.abort()
    if (selecting) context.ui.dialog.clear()
    unregister()
  }
}
