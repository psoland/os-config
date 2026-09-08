import { Plugin } from "@opencode-ai/plugin/tui"
import { setup } from "../worktree-session-picker/picker.mjs"

export default Plugin.define({
  id: "worktree-session-picker",
  setup,
})
