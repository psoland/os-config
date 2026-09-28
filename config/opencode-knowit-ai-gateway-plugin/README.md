# Knowit AI gateway models in OpenCode V2

The provider is configured in `config/opencode/opencode.json`. OpenCode beta `19271` cannot add models through a plugin transform, so the `voc2` launcher discovers the current model IDs and writes a generated overlay to `~/.config/opencode/opencode.jsonc` before starting OpenCode. It refreshes on each `voc2`, `voc2-start`, or `voc2-reload` invocation, and retains the last successful list if the gateway is temporarily unavailable. Model capabilities and token limits use OpenCode's defaults; `/v1/models` does not reliably report them.

## Setup

Apply Home Manager to install Varlock and the `voc2` aliases. Then install the Bitwarden resolver package and authenticate the Bitwarden CLI:

```sh
cd ~/.dotfiles/config/opencode-knowit-ai-gateway-plugin
npm ci
bw login # only if not already logged in
varlock load -p . --agent
```

The `.env.schema` resolves the **password** field of the Bitwarden Password Manager item `knowit-ai-services-api-key` into `AGW_API_KEY`. If the value is a custom field, add `field="<field-name>"` to `bwp()` instead. `--agent` redacts the sensitive value in validation output.

From any working directory, use `voc2` to run OpenCode V2 with a private server carrying the key. The plain `oc2` and `oc2-*` aliases remain ordinary OpenCode commands. For the shared service, use `oc2-stop` followed by `voc2-start` (or use `voc2-reload`) so the server, not only a client, inherits the key. A server later started by plain `oc2` will not receive the key.

The generated JSONC file contains model names and IDs only, never the API key. The launcher refuses to overwrite a pre-existing `~/.config/opencode/opencode.jsonc` that it did not create. After starting, select `knowit-ai-gateway/<model-id>` in `/models`.
