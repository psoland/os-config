# Knowit AI Services model discovery for OpenCode V2

The repository's `config/opencode/opencode.json` already loads this plugin and defines the provider. Apply the Home Manager configuration to link the updated config into `~/.config/opencode/`. `AGW_API_KEY` must be available to the OpenCode **server**, for both model discovery and requests.

## Using Varlock

Varlock is installed by Home Manager from `profiles/home/common.nix`. The adjacent `.env.schema` marks the key required and sensitive and reads the **password** field of the Bitwarden Password Manager item named `knowit-ai-services-api-key`. Install this plugin directory's npm dependencies with `npm ci`, and sign in to the Bitwarden CLI with `bw login` once. Run `varlock load -p ~/.dotfiles/config/opencode-knowit-ai-gateway-plugin --agent` from a terminal to unlock Bitwarden and validate the resolution without printing the key. If the item stores the key in a custom field rather than its password, set `field="<field-name>"` on the `bwp()` call in `.env.schema`.

After applying Home Manager, use the `oc2` alias to launch OpenCode V2 with a private server under Varlock. You can use it from any directory and pass normal OpenCode arguments. The existing shared-server helpers `oc2-start` and `oc2-reload` also resolve the key via Varlock; `oc2-stop` and `oc2-status` do not need it.

Equivalent manual command for a private server:

```sh
varlock run -p ~/.dotfiles/config/opencode-knowit-ai-gateway-plugin --inject vars -- opencode2 --standalone
```

For the shared background service, stop the existing server first and start it under Varlock so the **server process** inherits the variable:

```sh
opencode2 service stop
varlock run -p ~/.dotfiles/config/opencode-knowit-ai-gateway-plugin --inject vars -- opencode2 service start
```

Launching only the client under `varlock run` does not change the environment of an existing shared server. A later server restart must likewise be launched under Varlock. Avoid using `varlock load --format shell` or `varlock printenv` in commands whose output gets logged, because those formats reveal raw secrets.

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["/home/psoland/.dotfiles/config/opencode-knowit-ai-gateway-plugin"],
  "providers": {
    "knowit-ai-gateway": {
      "name": "Knowit AI Services",
      "env": ["AGW_API_KEY"],
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "https://ai.aiservices.knowit.no/v1"
      }
    }
  }
}
```

If using the plugin outside this dotfiles checkout, merge these entries into your existing config and change the path to the plugin directory on the machine running the OpenCode server. Restart the service after setting the environment variable (`opencode2 service restart`), then use `/models` and select `knowit-ai-gateway/<model-id>`.

The plugin fetches `https://ai.aiservices.knowit.no/v1/models` with bearer authentication on startup and every five minutes. A failed refresh retains the most recent successful model list. Without a key, the plugin does not contact the gateway. The `providers.knowit-ai-gateway` entry lets OpenCode resolve the same environment key for model requests, without storing the key in plugin-created provider metadata. Model names and IDs come from the gateway; model capabilities and token limits use OpenCode's defaults because the standard OpenAI `/models` response does not describe them reliably. Configure known limits or capabilities separately with `providers.knowit-ai-gateway.models` in your config if needed.
