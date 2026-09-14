# Mujo Cloudflare Publishing

This directory owns one persistent named Cloudflare Tunnel, one proxied
`mujo.no` CNAME, and optional email-restricted Cloudflare Access resources. It
does not build or run the application. The workspace file pins Effect's matching
release-candidate packages and allowlists the pinned dependencies that use
install scripts.

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

For persistent selected content rather than an existing application, also render
`systemd/mujo-selected-content.service.template`, for example as
`mujo-demo-selected-content.service`. Its `__NODE_BINARY__` and
`__QUICK_TUNNEL_SCRIPT__` markers must be absolute paths, and its selected path
and port must exactly match `MUJO_ORIGIN_URL`. This unit owns only the helper
server, never an application supplied by the project.

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

- one lowercase direct subdomain of `mujo.no` (not a nested name);
- an HTTP origin on a literal loopback address with an explicit port;
- an explicit `public` or `zero-trust` access mode;
- exactly one email address in Zero Trust mode;
- an absolute connector-token path outside the repository.

The browser session duration for Zero Trust is fixed at the conservative
default of 24 hours. Cloudflare Zero Trust and a usable account-level login
method must already exist.

## Persistent selected content

Use the same helper for a named Tunnel when the selected content, not an
application, is the origin. Pick an unused fixed loopback port and configure it
as the normal origin, for example `MUJO_ORIGIN_URL=http://127.0.0.1:8787`. Render
the selected-content unit with the same port and an absolute selected file or
directory path. It runs no Cloudflare command:

```bash
node ../../quick-tunnel.mjs --serve-only --path /absolute/path/to/public --port 8787
```

Install and start this unit before planning, then verify the exact local origin
with `curl`. It is loopback-only, so this does not expose content publicly; the
connector is still installed only after a successful deployment. The helper has
the same selected-path and loopback protections as Quick Tunnel mode. Its checks
filter paths and file names; they do not inspect file contents, so select a
deliberately public directory rather than relying on the helper to discover
secrets.

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
connector unit under `~/.config/systemd/user/`. The selected-content unit has
already been installed and verified locally before planning. Then run:

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

To pause the public connector without changing Cloudflare state, stop its unit;
start it again to resume. Neither action touches the application or its data:

```bash
systemctl --user stop mujo-demo-cloudflared.service
systemctl --user start mujo-demo-cloudflared.service
```

For a selected-content origin, pause and resume its separate unit only when the
publication should have no local origin. Do not use it to supervise a supplied
application:

```bash
systemctl --user stop mujo-demo-selected-content.service
systemctl --user start mujo-demo-selected-content.service
```

The connector token is a local Alchemy resource: every plan checks its content,
parent mode `0700`, and file mode `0600`. A deploy repairs a missing, changed,
or permissive token file without exposing its value.

For removal, first show and approve the destroy plan for the exact hostname.
Then stop and disable the connector, destroy only this Alchemy stack, and
remove its rendered unit. If it was generated for selected content, stop,
disable, and remove that unit too. Offer to remove the generated
`infrastructure.env` and `.alchemy` state after the destroy completes, but
retain the connector token unless its deletion is approved separately. Never
alter the application runtime or data.

## Temporary public sharing

`../../quick-tunnel.mjs` is intentionally separate from this persistent
infrastructure. It starts a Cloudflare Quick Tunnel in the foreground, with no
Alchemy stack, DNS record, Access policy, service, token, or generated config.
Its random public URL is printed by `cloudflared`; anyone who receives it can
reach the selected content until the process stops. Get explicit public-exposure
approval before running it.

For an existing local application, use its already-running loopback origin:

```bash
node ../../quick-tunnel.mjs --url http://127.0.0.1:3000
```

For a file or static directory, select the exact absolute path. The helper binds
its local server to `127.0.0.1` on an ephemeral port and passes only that origin
to `cloudflared`:

```bash
node ../../quick-tunnel.mjs --path /absolute/path/to/public
node ../../quick-tunnel.mjs --path /absolute/path/to/report.html
```

Directory mode serves `/index.html` and requested regular files only. It has no
directory listing and rejects repository roots, home, filesystem root, selected
symlinks, all symlinks below the selected directory, dotfiles, and common secret
path names/extensions. These are path and name checks, not content scanning. A
single selected regular file is available only at `/`. Run `node
../../quick-tunnel.mjs --help` for the complete commands. Press `Ctrl-C` to stop
the temporary tunnel and, when used, the file server. The application itself
remains running. There is no Quick Tunnel teardown or local cleanup because it
creates no persistent resources. The helper supports Node.js 20+.
