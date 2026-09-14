# Mujo Cloudflare Publishing

This directory owns one Cloudflare Tunnel, one proxied `mujo.no` CNAME, and
optional email-restricted Cloudflare Access resources. It does not build or run
the application. The workspace file pins Effect's matching release-candidate
packages and allowlists the pinned dependencies that use install scripts.

## Instantiate the template

Copy the complete `templates/mujo-publish` directory to the project root, then
replace these markers in `alchemy.run.ts`:

- `__ALCHEMY_STACK_NAME__`: stable PascalCase stack name, such as `MujoDemo`;
- `__RESOURCE_PREFIX__`: stable PascalCase logical ID prefix, such as `Demo`;
- `__TUNNEL_NAME__`: stable account-unique tunnel name, such as `mujo-demo`;
- `__DISPLAY_NAME__`: human-readable application name.

Keep `systemd/mujo-cloudflared.service.template` for verification. Render a
copy with a stable project-specific name such as
`mujo-demo-cloudflared.service` and replace its four markers in that copy.
Use a non-secret inhibit path next to the token, such as `tunnel-token.inhibit`,
for `__CLOUDFLARED_INHIBIT_FILE__`.
Apply `gitignore.snippet` to the project `.gitignore`, adapting its anchored
path only if this directory was copied elsewhere.

Do not change or remove logical IDs after the first deployment. The pinned
Alchemy dependency carries a narrow compatibility patch that marks tunnel and
Access policy discoveries as unowned and rejects apply-time DNS and Access
application collisions when deferred outputs prevent a planning probe. Do not
use Alchemy's `--adopt` option: a pre-existing DNS record, tunnel, Access
application, or Access policy is an ownership conflict that must stop
deployment.

## Configure

Copy `infrastructure.env.example` to the ignored `infrastructure.env` and fill
in every value. Remove `MUJO_ACCESS_EMAIL` in public mode. The configuration
requires:

- a lowercase hostname strictly below `mujo.no`;
- an HTTP origin on a literal loopback address with an explicit port;
- an explicit `public` or `zero-trust` access mode;
- exactly one email address in Zero Trust mode;
- an absolute connector-token path outside the repository.

The browser session duration for Zero Trust is fixed at the conservative
default of 24 hours. Cloudflare Zero Trust and a usable account-level login
method must already exist.

Install the pinned dependencies and configure the named profile if necessary:

```bash
pnpm install --frozen-lockfile
pnpm exec alchemy login --profile mujo --configure
pnpm run check
```

## Plan and deploy

Verify the local origin first, then create a plan:

```bash
curl --fail --show-error http://127.0.0.1:3000/
pnpm exec alchemy plan --stage prod --profile mujo --env-file infrastructure.env
```

Review all creates, updates, replacements, and deletes. Public exposure always
needs explicit approval. Removing Access from an existing deployment needs a
separate warning and confirmation. Stop on any unexpected deletion,
replacement, ownership conflict, authentication failure, or origin failure.

After explicit approval, first handle an existing protected connector. If the
target mode is Zero Trust and this project's connector is already installed,
create the configured inhibit file with mode `0600`, then stop and disable the
connector. Before deploying any hostname, policy, or public-to-protected
change, install and reload this updated unit, or activate the equivalent Home
Manager declaration. Verify the loaded unit contains the intended negative
`ConditionPathExists` and remains inactive; stop if it does not. The inhibit
then keeps it stopped across user-manager and host restarts. Leave the inhibit
file in place if deployment fails. Remove it, re-enable the unit, and restart
the connector only after the complete protected deployment succeeds.

Then deploy:

```bash
pnpm exec alchemy deploy --stage prod --profile mujo --env-file infrastructure.env
```

For a first deployment, only after deployment succeeds, install the rendered
systemd user unit under `~/.config/systemd/user/`, then run:

```bash
systemctl --user daemon-reload
systemctl --user enable --now mujo-demo-cloudflared.service
systemctl --user status mujo-demo-cloudflared.service
```

Check DNS and the HTTPS response. Public mode must reach the application
without authentication. Zero Trust mode must redirect an unauthenticated
request to Cloudflare Access; complete the interactive login in a browser.

## Operations and removal

Use `systemctl --user` and `journalctl --user -u` for connector operations.
Application restarts do not require an infrastructure deployment. Changes to
hostname, origin, or access mode require a new reviewed plan.

The connector token is a local Alchemy resource: every plan checks its content,
parent mode `0700`, and file mode `0600`. A deploy repairs a missing, changed,
or permissive token file without exposing its value.

For removal, first show and approve the destroy plan for the exact hostname.
Then stop and disable the connector, destroy only this Alchemy stack, and
remove the rendered unit. Keep the connector token unless its deletion is
approved separately. Never alter the application runtime or data.
