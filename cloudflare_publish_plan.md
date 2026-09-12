# Cloudflare Publish: Detailed Implementation Plan

## 1. Objective

Build a standalone tool named `cf-publish` that makes publishing local static
content and web applications through a domain on Cloudflare predictable,
secure, and repeatable.

The intended workflow is:

```bash
cf-publish init
cf-publish plan
cf-publish up
cf-publish doctor
```

The tool must handle the complete publishing lifecycle:

- describe a deployment in a small project manifest;
- provision a Cloudflare Tunnel and DNS record;
- optionally protect the hostname with Cloudflare Access;
- run a loopback-only static origin when needed;
- supervise the tunnel connector;
- store secrets outside the project and outside Git;
- verify the public endpoint and its access behavior;
- stop or destroy a deployment safely;
- produce the same result when commands are run repeatedly.

## 2. Scope

### 2.1 Version 1 scope

Version 1 will support:

- Linux hosts with a systemd user manager;
- installation and execution through a Nix flake;
- Cloudflare authentication through named Alchemy profiles;
- one Cloudflare Tunnel per project and stage;
- one DNS hostname per deployment;
- existing HTTP applications listening on loopback;
- static files or directories served by a managed Caddy origin;
- public hostnames;
- browser authentication through Cloudflare Access email policies;
- machine authentication through Cloudflare Access service tokens;
- local connector supervision through systemd user services;
- remote Alchemy state through `Cloudflare.state()`;
- human-readable output and stable JSON output for automation.

### 2.2 Non-goals for version 1

Version 1 will not include:

- deployment of application source code to remote compute;
- building arbitrary application frameworks automatically;
- management of Cloudflare zones or domain registration;
- shared tunnels containing routes owned by unrelated projects;
- Kubernetes, Nomad, or other orchestrator integration;
- macOS launchd or Windows service supervision;
- Cloudflare Pages, Workers, R2, or object-storage hosting;
- automatic modification of application source files;
- automatic migration of existing tunnel deployments;
- a hosted control plane or web dashboard;
- arbitrary shell hooks from the manifest.

Applications remain responsible for their own build and runtime. `cf-publish`
only manages static origins itself. An HTTP application must already be running
and healthy before it is published.

## 3. Design Principles

### 3.1 Declarative ownership

Every deployment is described by a checked-in `.cf-publish.yaml` manifest. The
manifest contains no secrets. Cloudflare resources and local runtime state are
derived from that manifest.

### 3.2 One deployment, one tunnel

Each project and stage receives a separate tunnel and connector token. This
provides independent ownership, revocation, logs, rollout, and teardown. A
project cannot overwrite another project's ingress rules.

### 3.3 Explicit exposure

Public access must be explicitly declared. Changing an existing protected
deployment to public requires an additional command-line confirmation.

### 3.4 Loopback origins

Managed origins listen only on loopback. Existing HTTP origins must use a
loopback URL unless the user provides an explicit unsafe override. No inbound
firewall rule is required for a Cloudflare Tunnel.

### 3.5 Secrets stay out of repositories and process arguments

Connector tokens and Access client secrets are written atomically with mode
`0600` beneath the XDG state directory. `cloudflared` receives its connector
token through `--token-file`, never through a command-line token value.

### 3.6 Deterministic CLI before agent automation

The CLI is the only implementation of provisioning and runtime operations. An
OpenCode skill may inspect a project, create a manifest, and invoke the CLI, but
must not contain a second implementation of Cloudflare operations.

### 3.7 Safe failure

If provisioning, origin startup, connector startup, or verification fails, the
deployment must fail closed. A protected deployment must never be made public
as a fallback.

## 4. Proposed Repository

Create a dedicated repository for the tool:

```text
cloudflare-publisher/
  flake.nix
  flake.lock
  package.json
  pnpm-lock.yaml
  pnpm-workspace.yaml
  tsconfig.json
  src/
    cli.ts
    commands/
      init.ts
      validate.ts
      plan.ts
      up.ts
      down.ts
      status.ts
      logs.ts
      doctor.ts
      destroy.ts
      rotate-access-token.ts
    config/
      global-config.ts
      manifest.ts
      schema.ts
    cloudflare/
      stack.ts
      published-app.ts
      access.ts
      dns.ts
      tunnel.ts
      secret-actions.ts
    runtime/
      deployment-state.ts
      ports.ts
      static-site.ts
      systemd.ts
      connector.ts
    verification/
      local-origin.ts
      dns.ts
      access.ts
      endpoint.ts
    output/
      console.ts
      json.ts
    errors.ts
  templates/
    manifest.yaml
    systemd/
  tests/
    unit/
    integration/
    fixtures/
    live/
  skill/
    publish-cloudflare/
      SKILL.md
  docs/
    manifest.md
    commands.md
    access.md
    operations.md
    troubleshooting.md
```

Alchemy, Effect, TypeScript, Node.js, Caddy, and `cloudflared` versions must be
pinned by the lockfiles and Nix flake.

## 5. Installation and Packaging

The primary installation interface will be a Nix flake:

```bash
nix run github:<owner>/cloudflare-publisher -- init
```

For regular use, install it into a profile:

```bash
nix profile install github:<owner>/cloudflare-publisher
cf-publish --version
```

The Nix package will provide:

- the `cf-publish` CLI;
- a compatible Node.js runtime;
- the pinned `cloudflared` binary;
- the pinned Caddy binary;
- required runtime utilities;
- wrapper environment variables containing immutable Nix store paths for Caddy
  and `cloudflared`.

The CLI must not depend on globally installed npm packages. A development shell
will provide pnpm, TypeScript, formatting, linting, and test tools.

## 6. Configuration Model

### 6.1 Global configuration

Optional user defaults live at:

```text
${XDG_CONFIG_HOME:-~/.config}/cf-publish/config.yaml
```

Example:

```yaml
version: 1
defaults:
  profile: mujo
  zone: mujo.no
  stage: dev
  accessTokenDuration: 8760h
```

The global configuration contains preferences only. Cloudflare credentials stay
in the Alchemy profile store, and deployment secrets stay in the XDG state
directory.

Precedence from highest to lowest:

1. Command-line flag.
2. Project manifest.
3. Global configuration.
4. Built-in default.

### 6.2 Project manifest

The project manifest is named `.cf-publish.yaml`.

Recommended version 1 schema:

```yaml
apiVersion: cf-publish/v1
id: product-demo
stage: prod

cloudflare:
  profile: mujo
  zone: mujo.no
  hostname: product-demo.mujo.no

origin:
  type: static
  source: ./dist
  spa: false

access:
  mode: email
  sessionDuration: 24h
  emails:
    - operator@example.com
```

`id` is a stable lowercase slug and must not be changed after deployment unless
the user intends to create a new deployment. Resource names are derived from
`id` and `stage`, not from the absolute checkout path.

### 6.3 Manifest validation

Validation must reject:

- unknown fields;
- unsupported `apiVersion` values;
- invalid IDs, stages, hostnames, URLs, durations, or email addresses;
- a hostname outside the configured zone;
- non-loopback HTTP origins without an explicit unsafe override;
- empty allow-lists for protected access modes;
- Access fields that do not belong to the selected mode;
- static source paths that do not exist;
- static sources containing unsafe symlinks;
- credential values placed directly in the manifest;
- duplicate service-token client names;
- reserved or colliding local ports.

Unknown fields must be errors rather than warnings so misspelled security
settings cannot silently change behavior.

## 7. Origin Types

### 7.1 Existing HTTP application

Example:

```yaml
origin:
  type: http
  url: http://127.0.0.1:3000
  healthPath: /health
```

Behavior:

- `cf-publish up` verifies the origin before changing Cloudflare resources;
- the application process remains owned by the user or its existing runtime;
- the connector targets the exact configured URL;
- the tool does not restart or terminate the application;
- `doctor` checks both the configured health path and the public endpoint.

Optional version 1 fields:

```yaml
origin:
  type: http
  url: http://127.0.0.1:3000
  healthPath: /api/health
  hostHeader: localhost
  connectTimeout: 10s
```

The initial release should support HTTP origins only. HTTPS origins with custom
certificate trust can be added after the trust model is designed explicitly.

### 7.2 Static content

Example:

```yaml
origin:
  type: static
  source: ./dist
  index: index.html
  spa: true
```

The static source may be a single HTML file or a directory. The tool must not
serve the project checkout directly. It creates an isolated deployment snapshot
at:

```text
${XDG_DATA_HOME:-~/.local/share}/cf-publish/<id>/<stage>/site/
```

Snapshot rules:

- resolve the source to a canonical path;
- copy regular files into a fresh staging directory;
- reject symlinks that resolve outside the source root;
- reject sockets, devices, FIFOs, and other special files;
- reject known secret files such as `.env`, private keys, and credential files;
- preserve only required read permissions;
- atomically replace the previously deployed snapshot;
- show the resolved source and file count in the plan;
- calculate a content digest for idempotency and status output.

A managed Caddy user service serves the snapshot from a loopback-only allocated
port. SPA mode uses an explicit `try_files {path} /index.html` fallback. Directory
listing is disabled.

## 8. Access Modes

### 8.1 Public

```yaml
access:
  mode: public
```

Resources:

- tunnel;
- proxied DNS record;
- no Access application;
- no Access policy;
- no Access client credentials.

The plan must display a prominent `PUBLIC` classification. Changing a deployed
hostname from `email` or `service-token` to `public` requires:

```bash
cf-publish up --allow-public
```

Non-interactive execution must fail without this flag.

### 8.2 Email-protected web application

```yaml
access:
  mode: email
  sessionDuration: 24h
  emails:
    - user@example.com
  emailDomains: []
```

Resources:

- self-hosted Access application covering the exact hostname;
- reusable Allow policy;
- one or more exact-email and email-domain selectors;
- configured browser session duration.

At least one email or email domain is required. Exact emails should be
recommended over broad domains. Identity provider configuration remains an
account-level prerequisite and is not managed by this tool.

### 8.3 Service-token-protected API

```yaml
access:
  mode: service-token
  clients:
    - name: operator
      duration: 8760h
      secretVersion: 1
```

Resources:

- self-hosted Access application covering the exact hostname;
- one Access service token per declared client;
- a Service Auth policy with `decision: non_identity`;
- policy selectors restricted to the declared token IDs.

Generated client credentials are written to:

```text
${XDG_STATE_HOME:-~/.local/state}/cf-publish/<id>/<stage>/clients/<name>.env
```

Each file contains:

```dotenv
CF_ACCESS_CLIENT_ID=...
CF_ACCESS_CLIENT_SECRET=...
```

The CLI prints the file path, never the secret. Users move the credentials to a
password or secret manager. Incrementing `secretVersion` rotates that client's
secret without replacing unrelated clients.

## 9. Cloudflare Resource Model

### 9.1 Stack identity

Use one Alchemy stack per manifest `id` and one Alchemy stage per manifest
`stage`:

```text
stack: CfPublish-<id>
stage: <stage>
```

Alchemy state uses `Cloudflare.state()` so the infrastructure state is not tied
to one checkout. Local runtime state is separate from Alchemy state.

### 9.2 Tunnel

Create a remotely managed tunnel with a deterministic name:

```text
cf-publish-<id>-<stage>
```

Ingress contains exactly two rules:

```yaml
- hostname: <configured-hostname>
  service: <resolved-loopback-origin>
- service: http_status:404
```

The catch-all rule is mandatory. Chunked encoding remains enabled for streaming
responses. Tunnel origin settings should remain at Cloudflare defaults unless a
manifest field has a demonstrated requirement.

### 9.3 DNS

Create one proxied CNAME pointing to:

```text
<tunnel-id>.cfargotunnel.com
```

The tool must fail if a DNS record with the same name is not already owned by
the same Alchemy stack. Adoption requires a separate explicit command and a plan
showing the existing resource.

Provider normalization must be covered by an idempotency test. A second `up`
must not mutate the DNS record even if the Alchemy beta provider conservatively
labels an output-dependent record as an update during planning.

### 9.4 Access resources

Access resources are conditional on `access.mode`. Stable logical IDs are
required so policy changes update resources instead of creating duplicates.

The connector is started only after the complete Alchemy deployment succeeds.
This ensures an email- or service-token-protected deployment has its Access
application and policies before public traffic can reach the origin.

### 9.5 Resource ownership and collisions

Before planning, query Cloudflare for:

- an existing DNS record using the hostname;
- an existing tunnel using the deterministic tunnel name;
- an existing Access application covering the hostname;
- Alchemy state for the selected stack and stage.

The default behavior is to fail on unowned resources. `--adopt` must be a
separate expert workflow and must never be implied by `up`.

## 10. Local State and Secrets

### 10.1 Directory layout

```text
~/.local/state/cf-publish/<id>/<stage>/
  deployment.json
  tunnel-token
  clients/
    operator.env
  systemd/
    connector.service
    static-origin.service
  locks/
    operation.lock

~/.local/share/cf-publish/<id>/<stage>/
  site/
```

Directory mode is `0700`. Secret file mode is `0600`.

### 10.2 Deployment state

`deployment.json` contains non-secret resolved information:

- manifest ID and stage;
- absolute manifest path;
- hostname and zone;
- tunnel ID and tunnel name;
- origin type and resolved origin URL;
- static content digest when applicable;
- systemd unit names;
- access mode and non-secret client IDs;
- last successful deployment timestamp;
- tool and schema versions.

The file must never contain connector tokens or Access client secrets.

### 10.3 Atomic writes

Every secret and state update follows this sequence:

1. Create the parent directory with mode `0700`.
2. Write a unique temporary file with mode `0600`.
3. Flush and close the file.
4. Rename it atomically over the destination.
5. Verify owner and mode.

Operations use a per-deployment file lock to prevent concurrent `up`, `down`,
`destroy`, or rotation commands.

## 11. Runtime Supervision

### 11.1 Connector service

Generate a systemd user service named:

```text
cf-publish-<id>-<stage>-connector.service
```

Required behavior:

- read the token from the deployment's token file;
- use the pinned Nix `cloudflared` binary;
- use `--no-autoupdate`;
- restart on failure with bounded backoff;
- start after `network-online.target`;
- start after and require the managed static origin when applicable;
- log to the systemd journal;
- use practical systemd hardening that is tested with `cloudflared`;
- never include a token value in `ExecStart`.

### 11.2 Static origin service

Generate a systemd user service named:

```text
cf-publish-<id>-<stage>-origin.service
```

It runs pinned Caddy against a generated read-only configuration, listens on an
allocated loopback port, and serves only the staged snapshot.

### 11.3 Port allocation

Use a configurable range reserved for managed static origins, for example
`18100-18999`.

Allocation must:

- prefer a deterministic candidate derived from `id` and `stage`;
- check existing deployment state;
- check active listeners before use;
- resolve collisions by scanning the range;
- persist the selected port;
- fail rather than bind to all interfaces.

### 11.4 Service installation

`up` writes generated units to the user systemd directory, runs `daemon-reload`,
enables the units, and starts them. User lingering is not enabled automatically
because that changes host-level policy. `doctor` reports when lingering is
disabled and explains the reboot/logout consequence.

## 12. CLI Contract

### 12.1 `cf-publish init`

Interactive mode asks for:

- stable deployment ID;
- stage;
- Cloudflare profile;
- zone and hostname;
- static source or HTTP origin URL;
- access mode;
- email allow-list or service-token clients when required.

It writes `.cf-publish.yaml`, validates it, and prints the next command. It does
not contact Cloudflare or start services.

Non-interactive flags must support project generators and agent use:

```bash
cf-publish init \
  --id product-demo \
  --stage prod \
  --zone mujo.no \
  --hostname product-demo.mujo.no \
  --static ./dist \
  --access public
```

### 12.2 `cf-publish validate`

Validate schema, paths, access rules, local prerequisites, and naming. No
Cloudflare API calls and no state changes.

### 12.3 `cf-publish plan`

Perform validation and origin preflight, then show:

- deployment identity;
- hostname and exposure classification;
- resolved origin;
- static snapshot changes;
- Cloudflare resource creates, updates, replacements, and deletes;
- local unit creates, updates, restarts, and removals;
- credential creates or rotations;
- security-sensitive transitions.

Support `--json` for machine-readable output. Planning never writes secrets,
changes Cloudflare, or starts services.

### 12.4 `cf-publish up`

Execution order:

1. Acquire the deployment lock.
2. Validate the manifest and tools.
3. Verify an HTTP origin or prepare a static snapshot candidate.
4. Calculate and display the plan.
5. Require confirmation unless `--yes` is supplied.
6. Require `--allow-public` for protected-to-public transitions.
7. Apply the Alchemy stack.
8. Write connector and client credentials atomically.
9. Activate the static snapshot when applicable.
10. Install or update user systemd units.
11. Start the origin and connector.
12. Run local and public verification.
13. Persist non-secret deployment state.
14. Print URL, access mode, status, and credential file paths.

A failed verification returns non-zero and leaves diagnostic information. It
must not silently destroy successfully created Cloudflare resources, because
doing so can hide the original failure and complicate recovery.

### 12.5 `cf-publish status`

Report:

- manifest and local state agreement;
- origin status;
- connector status;
- Cloudflare tunnel status;
- DNS resolution;
- configured access mode;
- last successful verification;
- static content digest drift.

Support `--json` and return non-zero for degraded deployments.

### 12.6 `cf-publish logs`

Show connector logs by default. Flags select connector, static origin, or both:

```bash
cf-publish logs
cf-publish logs --origin
cf-publish logs --all --since 1h
```

### 12.7 `cf-publish doctor`

Run bounded checks for:

- manifest validity;
- required binaries;
- state ownership and permissions;
- systemd user manager and lingering;
- local origin health;
- connector process health;
- tunnel connectivity;
- DNS record correctness;
- unauthenticated Access behavior;
- authenticated Access behavior when local credentials exist;
- final endpoint response;
- accidental non-loopback listeners.

Doctor output must redact headers, tokens, and cookies.

### 12.8 `cf-publish down`

Stop and disable managed connector and static-origin units. Preserve Cloudflare
resources, static snapshots, connector tokens, client credentials, and Alchemy
state. The public endpoint becomes unavailable but remains reserved.

### 12.9 `cf-publish destroy`

Execution order:

1. Show a destructive plan.
2. Require the exact deployment ID as confirmation, or `--yes` in automation.
3. Stop local connector and origin services.
4. Remove DNS first.
5. Remove Access resources and service tokens.
6. Remove the tunnel.
7. Remove generated units and non-secret local state.
8. Retain secret files unless `--purge-secrets` is explicitly supplied.

The operation must be safe to retry after partial failure.

### 12.10 `cf-publish rotate-access-token`

Require service-token access mode and a declared client name:

```bash
cf-publish rotate-access-token operator
```

The command increments the desired secret version, previews the rotation, and
requires confirmation. It must support a Cloudflare grace period when the
provider exposes one. The updated secret is written atomically to the client
credential file.

## 13. Verification Behavior

### 13.1 Public mode

Verification succeeds when:

- the local origin responds;
- DNS resolves through Cloudflare;
- the connector is connected;
- the public URL returns the expected status;
- the response is not a Cloudflare tunnel error page.

### 13.2 Email mode

Automated verification cannot complete an interactive identity-provider login.
It must verify that an unauthenticated request receives the expected Access
redirect or denial and that the Access application covers the exact hostname.
The CLI then prints a URL for the operator to complete browser verification.

### 13.3 Service-token mode

Verification performs two requests:

1. An unauthenticated request must be rejected by Access.
2. A request with the selected local service-token credentials must pass Access
   and reach the origin.

Credentials are loaded from files and applied as headers without appearing in
logs or command arguments.

## 14. Output and Automation

Human output should be concise and structured around phases:

```text
VALIDATE  manifest and origin
PLAN      5 create, 0 update, 0 delete
APPLY     Cloudflare resources
START     origin and connector
VERIFY    access and endpoint
READY     https://product-demo.mujo.no
```

Every non-interactive command supports `--json`. JSON output has a versioned
schema and writes diagnostics to stderr so stdout remains machine-readable.

Suggested exit codes:

| Code | Meaning |
| --- | --- |
| 0 | Success |
| 2 | Manifest or argument error |
| 3 | Authentication or authorization failure |
| 4 | Cloudflare planning or apply failure |
| 5 | Local runtime failure |
| 6 | Verification failure |
| 7 | Resource ownership conflict |
| 8 | Operation already locked |

## 15. OpenCode Skill

Provide an optional skill named `publish-cloudflare`.

The skill should:

- detect whether the project is static or already exposes an HTTP server;
- inspect common build outputs such as `dist`, `build`, and `public`;
- ask the user to confirm the static source or application port;
- ask for profile, zone, hostname, stage, and access mode;
- recommend email access for browser-only private applications;
- recommend service tokens for APIs and automated consumers;
- generate the manifest through `cf-publish init` flags;
- run `cf-publish validate` and `cf-publish plan`;
- summarize public exposure and destructive changes clearly;
- invoke `cf-publish up` only after user approval;
- finish with `cf-publish doctor` and the resulting URL.

The skill must not:

- call Cloudflare APIs directly;
- write connector or Access secrets itself;
- invent an email allow-list;
- infer that an application should be public;
- use `--adopt`, `--allow-public`, `--yes`, or `--purge-secrets` without explicit
  user approval;
- bypass a failed CLI validation.

## 16. Security Requirements

Mandatory controls:

- strict manifest schema with unknown-field rejection;
- loopback-only managed origins;
- one connector token per deployment;
- one Access service token per declared client;
- connector token passed through a file;
- atomic secret writes with verified permissions;
- no secrets in manifest, deployment JSON, logs, plans, or process arguments;
- explicit protected-to-public confirmation;
- deny-by-default resource adoption;
- exact-hostname Access applications;
- no Access Bypass policy for public mode;
- static content copied into an isolated snapshot;
- rejection of unsafe static files and escaping symlinks;
- bounded network operations and health checks;
- no arbitrary manifest shell commands;
- dependency and Nix input pinning;
- redaction tests for every output mode.

Recommended follow-up controls:

- integration with a password manager for generated Access credentials;
- service-token expiration notifications;
- optional Cloudflare rate limiting for public APIs;
- optional geographic or IP requirements in Access policies;
- signed release artifacts and a binary cache;
- an audit record of apply, rotation, and destroy operations without secrets.

## 17. Error Handling and Recovery

Every error must identify:

- the failed phase;
- the affected deployment ID and stage;
- whether Cloudflare resources changed;
- whether local services changed;
- the exact safe retry command;
- the relevant log command;
- whether manual cleanup is required.

Recovery commands:

```bash
cf-publish status
cf-publish doctor
cf-publish logs --all
cf-publish plan
cf-publish up
```

If local secret files are lost but Alchemy state still contains redacted
resource secrets, provide a bounded `cf-publish recover-secrets` operation. If
Cloudflare no longer exposes a service-token secret, require rotation rather
than fabricating or silently replacing credentials.

If local runtime state is lost, reconstruct only non-secret state by observing
resources owned by the exact Alchemy stack. Do not adopt resources discovered
only by hostname.

## 18. Testing Strategy

### 18.1 Unit tests

Cover:

- valid manifests for every origin and access mode;
- rejection of unknown and incompatible fields;
- hostname and zone validation;
- deterministic resource names;
- deterministic port allocation and collision handling;
- static path canonicalization;
- unsafe symlink and secret-file rejection;
- state and secret permission handling;
- access transition classification;
- public exposure confirmation requirements;
- output redaction;
- JSON output schemas;
- error-to-exit-code mapping.

### 18.2 Alchemy component tests

Use provider mocks to assert the exact resource graph for:

- public HTTP application;
- public static site;
- email-protected site;
- service-token-protected API with one client;
- service-token-protected API with multiple clients;
- adding and removing an Access client;
- rotating one client without rotating others;
- switching from public to protected;
- attempted protected-to-public transition without approval;
- hostname collision and explicit adoption behavior;
- resource deletion ordering.

### 18.3 Runtime integration tests

Run isolated systemd user-manager tests that verify:

- generated unit validity through `systemd-analyze verify`;
- connector token is not present in the unit or process arguments;
- static Caddy binds only to loopback;
- connector restart behavior;
- origin dependency ordering;
- `up`, `down`, and repeated `up` behavior;
- stale PID or stale unit recovery;
- operation locking;
- logs and status output;
- static snapshot atomic replacement.

### 18.4 Live Cloudflare tests

Use a dedicated test zone or delegated subdomain. Live tests create unique
hostnames and always clean them up.

Required live scenarios:

- public static file returns expected content;
- public HTTP proxy returns expected content;
- email mode rejects unauthenticated automation;
- service-token mode rejects unauthenticated requests;
- service-token mode accepts valid client headers;
- wrong service token is rejected;
- tunnel restart reconnects;
- second deployment is idempotent;
- destroy removes DNS, Access, service tokens, and tunnel;
- interrupted deployment can be retried safely.

Live tests must never run from ordinary unit-test commands without an explicit
environment flag and dedicated Cloudflare profile.

### 18.5 CI checks

CI should run:

```bash
nix flake check
pnpm install --frozen-lockfile
pnpm check
pnpm test
pnpm lint
pnpm format --check
```

At minimum, build and test on `x86_64-linux` and `aarch64-linux`.

## 19. Implementation Phases

### Phase 1: Architecture and repository skeleton

Deliverables:

- repository and Nix flake;
- pinned Node.js, Alchemy, Caddy, and cloudflared;
- TypeScript build, lint, format, and test setup;
- error model and output abstraction;
- architecture decision records for tunnel ownership, state, and supervision.

Completion criteria:

- `nix flake check` passes on both Linux architectures;
- `cf-publish --help` and `cf-publish --version` work through `nix run`.

### Phase 2: Manifest and local state

Deliverables:

- strict versioned manifest schema;
- global configuration loader and precedence rules;
- `init` and `validate` commands;
- XDG state paths and operation locking;
- atomic non-secret and secret file utilities;
- human and JSON output modes.

Completion criteria:

- all manifest variants have fixtures;
- malformed and security-sensitive configurations fail with stable errors;
- no test output leaks fixture secrets.

### Phase 3: Cloudflare public publishing

Deliverables:

- reusable Alchemy `PublishedApp` component;
- tunnel and DNS resources;
- remote Alchemy state;
- connector-token writer;
- collision and ownership preflight;
- `plan` command;
- public-mode apply logic.

Completion criteria:

- a live test can create and destroy a public tunnel and hostname;
- a repeated apply causes no Cloudflare API mutation;
- unowned DNS and tunnel resources fail closed.

### Phase 4: Origin and connector runtime

Deliverables:

- existing HTTP origin preflight;
- static content staging and scanning;
- generated Caddy configuration;
- port allocation;
- generated systemd user units;
- `up`, `down`, `status`, and `logs` commands.

Completion criteria:

- static and HTTP origins work through a live tunnel;
- managed listeners are loopback-only;
- services recover after user-manager restart when lingering is enabled;
- repeated `up` is idempotent.

### Phase 5: Cloudflare Access

Deliverables:

- email access mode;
- service-token access mode;
- multiple named API clients;
- protected-to-public safety gate;
- service-token rotation;
- credential recovery behavior.

Completion criteria:

- unauthenticated and authenticated live tests pass for each mode;
- client credentials are mode `0600` and absent from all logs and plans;
- rotating one client leaves other clients unchanged.

### Phase 6: Verification and lifecycle hardening

Deliverables:

- `doctor` command;
- bounded retries and timeouts;
- partial-failure recovery;
- destructive plan and `destroy` command;
- JSON schemas and documented exit codes;
- complete operations and troubleshooting documentation.

Completion criteria:

- failure-injection tests cover each deployment phase;
- interrupted `up` and `destroy` operations are safely repeatable;
- live create, stop, resume, rotate, and destroy lifecycle passes.

### Phase 7: OpenCode skill

Deliverables:

- thin `publish-cloudflare` skill;
- project inspection and manifest recommendation workflow;
- required confirmation points;
- CLI error interpretation and recovery guidance;
- skill tests using fixture projects.

Completion criteria:

- the skill invokes only documented CLI commands;
- public exposure and destructive operations always require explicit approval;
- the same generated manifest works without the skill.

## 20. Acceptance Criteria

The first stable release is complete when a user can enter a directory
containing either a static build or an already-running web application and:

1. Generate a valid manifest interactively or with flags.
2. Preview every Cloudflare and local runtime change.
3. Publish through a chosen hostname with one command.
4. Choose public, email, or service-token access explicitly.
5. Re-run the command without creating duplicate resources or changing secrets.
6. Verify access behavior and origin health with `doctor`.
7. Stop local serving without releasing the hostname.
8. Resume serving without recreating Cloudflare resources.
9. Rotate one API client's Access secret safely.
10. Destroy the deployment without affecting any other project.

All of these operations must work without placing a secret in the project,
Alchemy arguments, systemd unit, process list, plan output, or normal logs.

## 21. Recommended Initial Decisions

Use these defaults unless implementation work reveals a concrete blocker:

| Decision | Default |
| --- | --- |
| Tool name | `cf-publish` |
| Implementation | TypeScript and Effect |
| Infrastructure engine | Pinned Alchemy 2.x |
| Packaging | Nix flake and profile package |
| State backend | `Cloudflare.state()` |
| Tunnel ownership | One tunnel per project and stage |
| Linux supervision | systemd user services |
| Static origin | Pinned Caddy serving an isolated snapshot |
| Managed bind address | `127.0.0.1` |
| Default access mode | No implicit default; user must choose |
| API authentication | Cloudflare Access service tokens |
| Browser authentication | Cloudflare Access email policy |
| Public transition | Requires `--allow-public` |
| Resource adoption | Disabled unless explicitly requested |
| Secret location | XDG state directory, mode `0600` |
| Project file | `.cf-publish.yaml`, safe to commit |
| Agent automation | Optional skill wrapping the CLI |

These decisions keep the first release narrow enough to implement and test,
while leaving clear extension points for additional platforms, secret managers,
Cloudflare policy selectors, and runtime adapters later.
