import assert from "node:assert/strict"
import { readFile } from "node:fs/promises"
import test from "node:test"

const root = new URL("../../config/opencode/", import.meta.url)
const cli = JSON.parse(await readFile(new URL("cli.json", root), "utf8"))
// This repository's server config uses full-line comments, not inline comments.
const server = JSON.parse((await readFile(new URL("opencode.json", root), "utf8")).replace(/^\s*\/\/.*$/gm, ""))

test("V2 preferences use native built-in key IDs and do not migrate the V1 plugin", () => {
  assert.deepEqual(cli.keybinds, {
    leader: "ctrl+x",
    "app.exit": "ctrl+q",
    "input.newline": "shift+return,ctrl+return,alt+return",
  })
  assert.equal(cli.plugins, undefined)
  assert.equal(cli.theme.name, "catppuccin")
  assert.equal(cli.diffs.wrap, "word")
  assert.deepEqual(cli.session, { sidebar: "hide", scrollbar: true, thinking: "show" })
  assert.equal(cli.animations, true)
})

test("shared config grants custom agents full access without overriding built-in permissions", () => {
  assert.equal(server.agents, undefined)
  assert.equal(server.permissions, undefined)
  assert.equal(server.permission, undefined)
  assert.equal(server.default_agent, "sol")
  for (const name of ["astra", "sol", "luna", "terra"]) assert.equal(server.agent[name].permission, "allow")
  assert.equal(server.agent.luna.model, "openai/gpt-6-luna")
  assert.equal(server.agent.sol.model, "openai/gpt-6-sol")
  assert.equal(server.agent.sol.variant, "medium")
  assert.equal(server.agent.astra.variant, "medium")
  assert.equal(server.agent.luna.variant, "max")
  assert.equal(server.agent.terra.variant, "high")
  assert.equal(server.agent.build.disable, true)
  assert.equal(server.agent.plan.disable, true)
  assert.equal(server.mcp.executor.enabled, true)
})
