import { Plugin } from "@opencode/plugin/tui"
import { createEffect } from "solid-js"
import { setup } from "./bridge.mjs"

export default Plugin.define({
  id: "herdr-agent",
  setup: (context) => setup(context, { effect: createEffect }),
})
