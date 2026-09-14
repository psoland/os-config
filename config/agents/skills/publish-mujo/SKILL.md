---
name: publish-mujo
description: Publish a local loopback application or selected file/directory through a temporary Cloudflare Quick Tunnel, or a persistent mujo.no Tunnel with public or email-restricted Zero Trust access. Use when asked to publish, expose, share, deploy, stop, resume, or remove local applications or files.
---

# Publish an application under mujo.no

Use the project-local template from
`/home/psoland/.dotfiles/templates/mujo-publish`. The template owns Cloudflare
resources and the persistent connector only. Do not change application source,
choose a runtime, or supervise the application unless separately requested.

## Safety rules

- Never infer public access. The user must explicitly choose `public`.
- A Quick Tunnel is always public; require explicit approval before starting it.
- Never deploy, destroy, or enable lingering without explicit approval.
- Show and summarize the Alchemy plan immediately before requesting approval.
- Give an additional warning when a plan removes Access protection.
- Stop on an unexpected delete, replacement, ownership conflict,
  authentication error, or failed local-origin check.
- Never use `--adopt`, replace, or delete unrelated Cloudflare resources.
- Never print, log, or place a Cloudflare credential or connector token in Git,
  a unit file, or command-line arguments.
- Provision Access successfully before starting the connector. Never fall back
  to public mode if Zero Trust provisioning fails.

## Discover

Inspect the project before asking questions:

1. Determine its normal build and start workflow.
2. Find the loopback HTTP origin and a health path if one exists.
3. Look for existing Alchemy, tunnel, DNS, Access, systemd, or Home Manager
   publishing configuration.
4. Check whether a candidate `mujo.no` hostname already appears in project
   configuration.
5. Verify the local URL with `curl --fail --show-error` before contacting
   Cloudflare.

If no safe loopback URL can be inferred and verified, ask the user for it. Do
not treat an application bound only to a non-loopback address as ready.

## Ask only what is missing

1. Is this a temporary `quick-public` share or a persistent `mujo.no` hostname?
2. For persistent publishing, which direct hostname below `mujo.no` should be used?
3. For persistent publishing, should access be `public` or protected by `zero-trust`?
4. In Zero Trust mode, which one exact email address should be allowed?
5. If user lingering is disabled, should the persistent connector persist after logout?

For either mode, ask whether the supplied loopback URL or the exact absolute
selected file/directory should be shared. For a Quick Tunnel, then obtain
explicit public approval. For persistent selected content, ask for an unused
fixed loopback port. Report current lingering behavior before asking the fifth
question. Enabling lingering is a host policy change and requires its own
approval.

## Temporary Quick Tunnel

Do not copy the template, run Alchemy, configure DNS or Access, create a token,
or install a service for a temporary share. After approval, run the helper from
the copied template or this repository:

```bash
node quick-tunnel.mjs --url http://127.0.0.1:3000
node quick-tunnel.mjs --path /absolute/path/to/selected-content
```

The helper accepts only HTTP literal-loopback origins with explicit ports. For
files, it accepts one absolute regular file or a selected directory, binds the
file server to `127.0.0.1`, serves a single file only at `/`, and has no
directory listing. It refuses repository roots, home, filesystem root,
dotfiles, common secret path names/extensions, and symlinks. These are path and
name checks, not content scanning. Do not weaken them or select a whole
checkout. The generated `trycloudflare.com` URL in `cloudflared` output is
public and ephemeral. `Ctrl-C` stops both the Quick Tunnel and the optional
local file server; do not claim that it stops an application supplied through
`--url`. The helper requires Node.js 20+; use `node quick-tunnel.mjs --help` for
its complete commands.

## Prepare

When project-specific publishing infrastructure does not exist:

1. Copy the complete template to the project root without changing the
   application's package manifest.
2. Replace every documented marker with stable project-specific names. Keep
   the unit template and render a separate `mujo-<app>-cloudflared.service`.
   Put the non-secret inhibit marker next to the token, normally at
   `<token-file>.inhibit`.
3. Create `infrastructure/cloudflare/infrastructure.env` from the example. It
   must remain ignored. Remove `MUJO_ACCESS_EMAIL` in public mode.
4. Put the connector token at an absolute path outside the repository, normally
   `~/.local/state/mujo-publish/<app>/tunnel-token`.
5. Add the provided ignore snippet, adapting only its path if needed.
6. Run `pnpm install --frozen-lockfile` and `pnpm run check` inside the
   infrastructure directory.
7. Configure `pnpm exec alchemy login --profile mujo --configure` only when the
   named profile is not usable.

For persistent selected content, set `MUJO_ORIGIN_URL` to the chosen fixed
loopback port and render `mujo-selected-content.service` from
`systemd/mujo-selected-content.service.template`. Use absolute paths for Node,
the copied `quick-tunnel.mjs`, and selected content. Its command must be
`--serve-only --path <absolute-path> --port <fixed-port>`. This separate unit
owns the helper server only; do not create it for an application that the
project already runs. Install, enable, and start it before planning, then verify
the configured `MUJO_ORIGIN_URL` with `curl`; this server remains loopback-only.

If a declarative Home Manager service already exists for this project, adapt
that service rather than installing a second connector. Ensure its command is
`cloudflared tunnel --no-autoupdate run --token-file <absolute-path>` and that
the binary has an explicit Nix store path or another explicitly resolved path.
Also add the template's negative `ConditionPathExists` for the persistent
inhibit marker.

## Plan and approve

Run from `infrastructure/cloudflare`:

```bash
pnpm exec alchemy plan --stage prod --profile mujo --env-file infrastructure.env
```

Summarize the hostname, local origin, access mode and allowed email if any,
creates/updates/deletes/replacements, whether Access will be removed, and the
token destination. For public mode, state clearly that anyone can reach the
hostname. Ask for explicit deployment approval only after this summary.

## Deploy and connect

After approval, first handle an existing protected connector. If the target
mode is Zero Trust and this project's connector is already installed,
atomically create its configured inhibit marker with mode `0600`, then disable
and stop it. Before deploying, install and reload the updated unit, or activate
its updated Home Manager declaration, and verify that the loaded unit contains
the intended negative `ConditionPathExists` and remains inactive. Stop if that
persistent inhibit cannot be established. The marker must persist across
user-manager and host restarts. Leave it in place if deployment fails. Remove
it, re-enable it, and restart only after the complete protected deployment
succeeds. This is required because Alchemy may reconcile independent
Cloudflare resources concurrently.

Then run:

```bash
pnpm exec alchemy deploy --stage prod --profile mujo --env-file infrastructure.env
```

For a first deployment, only after successful provisioning, render and verify
the unit, install it in `~/.config/systemd/user/`, reload the user manager, and
enable/start it. Do not start a second connector if the same project tunnel is
already running.

For selected content, verify that its already-running server unit still responds
at `MUJO_ORIGIN_URL`, then start the connector. The server is loopback-only; it
does not expose content until the named Tunnel runs.

## Verify

Verify the local origin, active connector, DNS resolution, and absence of a
Cloudflare tunnel error. In public mode, verify an unauthenticated request
reaches the application. In Zero Trust mode, verify an unauthenticated request
redirects to Cloudflare Access, then give the user the HTTPS URL for an
interactive browser login. Do not claim the browser authentication succeeded
without the user's confirmation.

## Diagnose

Use standard tools rather than custom wrappers:

```bash
systemctl --user status mujo-<app>-cloudflared.service
journalctl --user -u mujo-<app>-cloudflared.service
systemctl --user restart mujo-<app>-cloudflared.service
```

Normal application code changes and restarts do not require Alchemy.

For a persistent publication, pause and resume only the connector when needed:

```bash
systemctl --user stop mujo-<app>-cloudflared.service
systemctl --user start mujo-<app>-cloudflared.service
```

This does not alter Cloudflare resources, the application process, or data.

For a selected-content origin, the agent may pause and resume the generated
server unit with the same commands using `mujo-<app>-selected-content.service`.
It must never use that unit to stop or supervise a supplied application.

## Remove

Show the `alchemy destroy` plan and confirm the exact hostname before changing
anything. After approval, stop and disable the connector, destroy only the
project-owned stack, and remove the rendered connector unit and non-secret local
state. Also stop, disable, and remove the generated selected-content unit when
one exists. Offer to remove the generated `infrastructure.env` and `.alchemy`
state after a successful destroy. Keep the token unless the user separately
approves deleting it. Do not stop, modify, or delete the application runtime or
its data.
