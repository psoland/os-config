export interface GatewayModel {
  id: string
  name: string
}

export async function discoverModels(baseURL: string, apiKey: string, signal?: AbortSignal): Promise<GatewayModel[]> {
  const response = await fetch(`${baseURL}/models`, {
    headers: { Authorization: `Bearer ${apiKey}` },
    signal,
  })
  if (!response.ok) throw new Error(`gateway model discovery returned HTTP ${response.status}`)

  const body: unknown = await response.json()
  if (!body || typeof body !== "object" || !('data' in body) || !Array.isArray(body.data)) {
    throw new Error("gateway model discovery returned an invalid model list")
  }

  const models = new Map<string, GatewayModel>()
  for (const item of body.data) {
    if (!item || typeof item !== "object" || typeof item.id !== "string" || !item.id.trim()) continue
    const name = typeof item.name === "string" && item.name.trim() ? item.name : item.id
    models.set(item.id, { id: item.id, name })
  }
  return [...models.values()]
}
