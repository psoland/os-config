import assert from "node:assert/strict"
import { afterEach, test } from "node:test"
import { discoverModels } from "../models.ts"

const originalFetch = globalThis.fetch
afterEach(() => { globalThis.fetch = originalFetch })

test("discovers IDs with bearer authentication, keeps valid IDs, and deduplicates", async () => {
  globalThis.fetch = async (input, init) => {
    assert.equal(input, "https://gateway.example/v1/models")
    assert.equal(new Headers(init?.headers).get("Authorization"), "Bearer example-key")
    return Response.json({ data: [
      { id: "vendor/coder", name: "Coder" },
      { id: "vendor/coder", name: "Coder" },
      { id: "other" },
      { id: "" },
      { name: "missing id" },
    ] })
  }
  assert.deepEqual(await discoverModels("https://gateway.example/v1", "example-key"), [
    { id: "vendor/coder", name: "Coder" },
    { id: "other", name: "other" },
  ])
})

test("fails on HTTP errors and malformed lists instead of clearing inventory", async () => {
  globalThis.fetch = async () => new Response(null, { status: 401 })
  await assert.rejects(discoverModels("https://gateway.example/v1", "bad-key"), /HTTP 401/)
  globalThis.fetch = async () => Response.json({ models: [] })
  await assert.rejects(discoverModels("https://gateway.example/v1", "bad-key"), /invalid model list/)
})
