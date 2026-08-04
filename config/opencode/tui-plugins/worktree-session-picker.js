const command = "session.list.worktree"
const title = "Switch session (current worktree)"

function category(timestamp) {
	const date = new Date(timestamp)
	return date.toDateString() === new Date().toDateString() ? "Today" : date.toDateString()
}

async function showSessionPicker(api) {
	const result = await api.client.session.list({
		scope: "project",
		roots: true,
		limit: 100,
	})

	if (result.error) {
		api.ui.toast({
			variant: "error",
			title: "Failed to load sessions",
			message: "OpenCode could not load sessions for this project.",
		})
		return
	}

	const sessions = (result.data ?? [])
		.filter((session) => session.directory === api.state.path.directory)
		.toSorted((a, b) => b.time.updated - a.time.updated)

	if (sessions.length === 0) {
		api.ui.toast({
			variant: "info",
			message: "No sessions found for the current worktree.",
		})
		return
	}

	api.ui.dialog.setSize("large")
	api.ui.dialog.replace(() =>
		api.ui.DialogSelect({
			title: "Sessions in current worktree",
			options: sessions.map((session) => ({
				title: session.title,
				value: session.id,
				category: category(session.time.updated),
			})),
			onSelect(option) {
				api.ui.dialog.clear()
				api.route.navigate("session", { sessionID: option.value })
			},
		}),
	)
}

const tui = async (api) => {
	const unregister = api.keymap.registerLayer({
		commands: [
			{
				name: command,
				title,
				category: "Session",
				namespace: "palette",
				slashName: "worktree-sessions",
				run: () => showSessionPicker(api),
			},
		],
		bindings: api.tuiConfig.keybinds.get("session.list").map((binding) => ({
			...binding,
			cmd: command,
			desc: title,
		})),
	})

	api.lifecycle.onDispose(unregister)
}

export default {
	id: "worktree-session-picker",
	tui,
}
