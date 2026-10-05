import { Plugin } from "@opencode/plugin/tui"
import { setup } from "./picker.mjs"

export default Plugin.define({
  id: "worktree-session-picker",
  setup,
})
