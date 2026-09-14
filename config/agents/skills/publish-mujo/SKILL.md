---
name: publish-mujo
description: Publish an existing loopback HTTP application at a mujo.no hostname through Cloudflare Tunnel, with explicit public or email-restricted Zero Trust access. Use when asked to publish, expose, deploy, or remove a local web application under mujo.no.
---

# Publish an application under mujo.no

Use the project-local Alchemy template from
`/home/psoland/.dotfiles/templates/mujo-publish`. The template owns Cloudflare
resources and the connector only. Do not change application source, choose a
runtime, or supervise the application unless separately requested.

## Safety rules

- Never infer public access. The user must explicitly choose `public`.
- Never deploy, destroy, or enable lingering without explicit approval.
- Show and summarize the Alchemy plan immediately before requesting approval.
- Give an additional warning when a plan removes Access protection.
- Stop on an unexpected delete, replacement, ownership conflict,
  authentication error, or failed local-origin check.
- Never use `--adopt`; replace or delete unrelated Cloudflare resources.
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

1. Which hostname below `mujo.no` should be used?
2. Should access be `public` or protected by `zero-trust`?
3. In Zero Trust mode, which one exact email address should be allowed?
4. If user lingering is disabled, should the connector persist after logout?

Report current lingering behavior before asking the fourth question. Enabling
lingering is a host policy change and requires its own approval.

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

## Remove

Show the `alchemy destroy` plan and confirm the exact hostname before changing
anything. After approval, stop and disable the connector, destroy only the
project-owned stack, and remove the rendered unit and non-secret local state.
Keep the token unless the user separately approves deleting it. Do not stop,
modify, or delete the application runtime or its data.
