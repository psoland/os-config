import { Model, Plugin, Provider } from "@opencode/plugin"
import { discoverModels } from "./models.ts"

const baseURL = "https://ai.aiservices.knowit.no/v1"
const interval = 5 * 60_000
const providerID = Provider.ID.make("knowit-ai-gateway")

export default Plugin.define({
  id: "knowit-ai-gateway",
  async setup(ctx) {
    const apiKey = process.env.AGW_API_KEY
    if (!apiKey) {
      console.warn("knowit-ai-gateway: set AGW_API_KEY in the OpenCode server environment to discover models")
      return
    }

    let models: Model.Info[] = []
    let discovered = false
    const registration = await ctx.provider.transform((editor) => {
      const provider = editor.get("knowit-ai-gateway")
      if (!provider || !discovered) return
      editor.models.set("knowit-ai-gateway", models.map((model) => ({
        ...model,
        ...provider.models.get(model.id),
      })))
    })

    const controller = new AbortController()
    const refresh = async () => {
      try {
        const result = await discoverModels(baseURL, apiKey, AbortSignal.any([
          controller.signal,
          AbortSignal.timeout(10_000),
        ]))
        if (controller.signal.aborted) return
        models = result.map(({ id, name }) => ({
          ...Model.Info.default(providerID, Model.ID.make(id)),
          name,
        }))
        discovered = true
        await ctx.provider.reload()
      } catch (error) {
        if (!controller.signal.aborted) console.warn("knowit-ai-gateway: model discovery failed", error)
      }
    }

    await refresh()
    const timer = setInterval(() => void refresh(), interval)
    return () => {
      controller.abort()
      clearInterval(timer)
      void registration.dispose()
    }
  },
})
