# Mujo Publish: Simple Agent-Driven Plan

## 1. Objective

Make an existing local web application available at a hostname under `mujo.no`
with one explicit access choice:

- `public`: anyone can open the application;
- `zero-trust`: Cloudflare Access requires an approved email address.

The expected operator request is deliberately simple:

> Publish the application on `demo.mujo.no` and protect it with Zero Trust.

A coding agent should be able to inspect the project, ask for the few missing
values, apply a small project template, show the Cloudflare plan, and complete
the deployment after approval.

This is not a plan for a standalone deployment product. There will be no custom
`cf-publish` CLI, generic manifest language, runtime manager, or local state
machine.

## 2. Core Decision

Use a small project-local Alchemy template based on the working patterns in:

- `/home/psoland/workspace/github/knowit/ai_benchmarking/main`
- `/home/psoland/workspace/github/knowit/aiservices_spark_dotfiles`;

Each published application owns a small, explicit set of resources:

- one remotely managed Cloudflare Tunnel;
- one proxied DNS hostname under `mujo.no`;
- zero or one Cloudflare Access application and email policy;
- one connector token stored outside Git;
- one minimal `cloudflared` systemd user service.

Alchemy owns the Cloudflare resources and stores its state through
`Cloudflare.state()`. The application's existing tooling remains responsible
for building, starting, stopping, and monitoring the application itself.

## 3. Scope

### 3.1 Version 1

Version 1 supports:

- one application per template instance;
- one production hostname below `mujo.no`;
- an existing HTTP application listening on loopback;
- explicit `public` or `zero-trust` exposure;
- one exact allowed email address in Zero Trust mode;
- Cloudflare Tunnel, DNS, and Access provisioning through Alchemy;
- connector supervision through a systemd user service;
- agent-guided setup, planning, deployment, verification, and removal;
- Linux hosts on which `cloudflared` can reach the local application.

### 3.2 Non-goals

Version 1 does not include:

- a standalone publishing CLI;
- a `.cf-publish.yaml` schema or global configuration system;
- application build or process supervision;
- framework detection beyond finding and confirming the local HTTP endpoint;
- static file copying, scanning, snapshots, or managed Caddy instances;
- automatic port allocation;
- multiple stages or multiple machines for one template instance;
- service-token authentication for machine clients;
- multiple Zero Trust users, groups, or identity-provider management;
- arbitrary Cloudflare zones or domain registration;
- resource adoption or migration;
- custom status, logging, doctor, or secret-rotation commands;
- stable JSON output for automation;
- a hosted control plane or dashboard.

A plain static site must first be exposed through an HTTP server chosen by the
project. Static hosting on Cloudflare Workers can be considered separately; it
should not add a second deployment architecture to this template.

## 4. Architecture

### 4.1 Request path

Public mode:

```text
browser -> Cloudflare DNS -> Cloudflare Tunnel -> cloudflared
        -> local application on 127.0.0.1:<port>
```

Zero Trust mode:

```text
browser -> Cloudflare Access -> Cloudflare Tunnel -> cloudflared
        -> local application on 127.0.0.1:<port>
```

The tunnel ingress has exactly two rules:

```yaml
- hostname: <name>.mujo.no
  service: http://127.0.0.1:<port>
- service: http_status:404
```

### 4.2 Ownership

The project-local Alchemy stack owns all remote resources for the hostname.
Resource names and logical IDs are fixed in the generated template so repeated
deployments update the same resources.

The project does not maintain a second infrastructure state file. Alchemy's
Cloudflare state is authoritative for remote resources, while systemd is
authoritative for the local connector process.

### 4.3 Runtime boundary

The application must already:

- start successfully using its normal project workflow;
- listen on a confirmed loopback URL;
- remain running independently of the publishing setup;
- provide a URL that can be checked locally, preferably a health endpoint.

Publishing must not modify application source code or invent a new runtime
unless the user asks for that separately.

## 5. Template

Create one reusable template in the dotfiles repository:

```text
templates/mujo-publish/
  infrastructure/
    cloudflare/
      alchemy.run.ts
      package.json
      pnpm-lock.yaml
      tsconfig.json
      infrastructure.env.example
      README.md
  systemd/
    mujo-cloudflared.service.template
  gitignore.snippet
```

The infrastructure directory is self-contained so it does not add Alchemy or
Effect dependencies to the application's own package manifest.

The template is copied into a project only when that project needs publishing.
After copying, the agent replaces explicit placeholders such as the stack name,
logical resource prefix, and systemd unit name. Generated infrastructure should
remain readable project code, not hidden behind a generic abstraction.

Do not create a shared package or component until a third real deployment shows
that maintaining these small resource declarations separately is a problem.

## 6. Configuration

The ignored `infrastructure.env` contains the deployment-specific values:

```dotenv
MUJO_HOSTNAME=demo.mujo.no
MUJO_ORIGIN_URL=http://127.0.0.1:3000
MUJO_ACCESS_MODE=zero-trust
MUJO_ACCESS_EMAIL=operator@example.com
CLOUDFLARED_TOKEN_FILE=/home/user/.local/state/mujo-publish/demo/tunnel-token
```

Rules:

- `MUJO_HOSTNAME` is required and must be below `mujo.no`;
- `MUJO_ORIGIN_URL` is required and must use HTTP on a literal loopback address;
- `MUJO_ACCESS_MODE` is required and has no default;
- `MUJO_ACCESS_MODE` must be `public` or `zero-trust`;
- `MUJO_ACCESS_EMAIL` is required only for `zero-trust`;
- the connector token path must be absolute and outside the repository;
- the environment file and token path must be ignored by Git;
- no Cloudflare credential or connector token is accepted as a configuration
  value in a checked-in file.

The template should fail during configuration evaluation if these rules are not
met. Unknown configuration is not interpreted.

## 7. Cloudflare Resources

### 7.1 Tunnel

Create one remotely managed tunnel with a deterministic, project-specific name.
Its ingress points only from the exact configured hostname to the exact
loopback origin and ends with `http_status:404`.

The tunnel token is a redacted Alchemy output. A small Alchemy action writes it
atomically to `CLOUDFLARED_TOKEN_FILE` with:

- parent directory mode `0700`;
- file mode `0600`;
- a temporary file followed by rename;
- no token in normal output or logs.

### 7.2 DNS

Resolve the existing `mujo.no` zone in the authenticated Cloudflare account and
create one proxied CNAME:

```text
<hostname> -> <tunnel-id>.cfargotunnel.com
```

The template must not create or modify the zone itself. If the hostname already
belongs to an unrelated resource, deployment stops; the agent must not adopt,
replace, or delete it automatically.

### 7.3 Public access

For `MUJO_ACCESS_MODE=public`, create no Access application or policy.

The agent must clearly state that the hostname will be reachable by anyone and
request explicit approval before the first deployment. Changing an existing
Zero Trust deployment to public requires a separate warning and confirmation
after showing the Alchemy plan.

### 7.4 Zero Trust access

For `MUJO_ACCESS_MODE=zero-trust`, create:

- one self-hosted Access application for the exact hostname;
- one Allow policy;
- one exact-email selector for `MUJO_ACCESS_EMAIL`;
- a documented browser session duration with a conservative default.

Cloudflare Zero Trust and a usable login method are account-level prerequisites
and are not managed by the template.

The Access resources must be deployed before the connector is started. A
protected deployment must never fall back to public access if Access
provisioning fails.

## 8. Connector Service

Install one project-specific systemd user service, for example:

```text
mujo-demo-cloudflared.service
```

The template unit must:

- use the Nix-provided or otherwise explicitly resolved `cloudflared` binary;
- run `cloudflared tunnel --no-autoupdate run --token-file <path>`;
- never contain the token value;
- start after `network-online.target`;
- restart on failure with a short delay;
- use practical hardening supported by the host;
- log through the systemd journal;
- be enabled only after successful Cloudflare provisioning.

The agent may adapt the unit to an existing Home Manager module when the project
or host already manages user services declaratively. It must not create a
second connector when an existing project-specific service already runs the
same tunnel.

User lingering is a host policy decision. The agent should report whether the
connector stops after logout, but must not enable lingering without approval.

## 9. Agent Workflow

Provide an optional `publish-mujo` coding-agent skill. The template remains
usable without the skill.

### 9.1 Discovery

The agent inspects the project and determines:

- how the application is started;
- the local HTTP URL and health path;
- whether publishing infrastructure already exists;
- whether a systemd or Home Manager service convention already exists;
- whether the chosen hostname appears in project configuration.

The agent verifies the local URL before contacting Cloudflare.

### 9.2 Required questions

Ask only for information that cannot be safely inferred:

1. Which hostname below `mujo.no` should be used?
2. Should it be `public` or protected by `zero-trust`?
3. If protected, which exact email address should be allowed?
4. Should the connector persist after logout if lingering is currently disabled?

Never infer that an application should be public.

### 9.3 Preparation

The agent:

1. Copies the template when no publishing infrastructure exists.
2. Chooses stable project-specific Alchemy and systemd names.
3. Creates `infrastructure.env` outside Git tracking.
4. Adds only secret and local-state paths to `.gitignore`.
5. Installs the pinned infrastructure dependencies.
6. Validates TypeScript and confirms that the origin is loopback-only.
7. Configures the named Alchemy profile if one is not already usable.

### 9.4 Plan and approval

Run Alchemy directly:

```bash
pnpm exec alchemy plan --stage prod --profile mujo --env-file infrastructure.env
```

The agent summarizes:

- hostname;
- local origin;
- public or Zero Trust exposure;
- resources to create, update, or delete;
- whether Access protection will be removed;
- connector token destination.

The agent deploys only after explicit approval. It must stop on an unexpected
delete, replacement, ownership conflict, authentication error, or origin
failure.

### 9.5 Deploy

Run:

```bash
pnpm exec alchemy deploy --stage prod --profile mujo --env-file infrastructure.env
```

After successful provisioning, install or activate the connector unit and wait
for it to become active.

### 9.6 Verify

For both modes, verify:

- the local origin responds;
- the connector service is active;
- DNS resolves;
- the public hostname does not return a tunnel error.

For public mode, verify that an unauthenticated request reaches the application.

For Zero Trust mode, verify that an unauthenticated request receives a
Cloudflare Access login redirect. The agent then gives the user the URL for a
browser login test; it must not claim that interactive authentication was
automatically verified.

## 10. Routine Operations

Cloudflare infrastructure is not redeployed for normal application restarts or
code changes. Use the application's existing commands for those operations.

Connector operations use standard systemd commands:

```bash
systemctl --user status mujo-<app>-cloudflared.service
journalctl --user -u mujo-<app>-cloudflared.service
systemctl --user restart mujo-<app>-cloudflared.service
systemctl --user stop mujo-<app>-cloudflared.service
```

Changes to hostname, origin URL, or access mode require a new Alchemy plan and
explicit approval before deployment.

To remove a publication:

1. Show `alchemy destroy` planning output.
2. Confirm the exact hostname being removed.
3. Stop and disable the connector service.
4. Destroy the project-owned Alchemy stack.
5. Remove the generated unit and non-secret local state.
6. Retain the connector token unless the user explicitly approves deleting it.

Do not alter the application runtime or its data during Cloudflare teardown.

## 11. Security Requirements

Mandatory controls:

- access mode has no implicit default;
- public exposure always requires explicit approval;
- protected-to-public changes receive a separate warning;
- only hostnames below `mujo.no` are accepted;
- only literal loopback HTTP origins are accepted;
- tunnel ingress ends with `http_status:404`;
- Zero Trust covers the exact hostname before connector startup;
- connector tokens remain outside Git and use mode `0600`;
- connector tokens are read from files, not command-line values;
- plans, logs, agent messages, and checked-in files contain no secrets;
- existing unrelated DNS, tunnel, or Access resources are never adopted;
- failed Zero Trust provisioning never falls back to public access.

## 12. Testing

Keep template testing focused on the small contract:

- TypeScript type checking passes;
- both access modes produce the expected Alchemy resource graph;
- public mode contains no Access resources;
- Zero Trust mode contains the exact-hostname application and email policy;
- tunnel ingress contains the hostname rule and final 404 rule;
- invalid hostnames and non-loopback origins fail;
- connector tokens are redacted and written with mode `0600`;
- the systemd unit passes `systemd-analyze verify`;
- the token value is absent from the unit and process arguments.

Perform one explicit live test for each access mode against disposable hostnames
before treating the template as stable. Live tests must not run as part of
ordinary checks.

## 13. Implementation Steps

### Step 1: Extract the proven template

- Start from the small Alchemy stacks in the two existing repositories.
- Keep only tunnel, zone lookup, DNS, optional email Access, and token writing.
- Add strict validation for the hostname, origin, and required access mode.
- Add the minimal connector unit template.

### Step 2: Add focused checks

- Test the two resource graphs and secret writer.
- Validate the systemd unit.
- Confirm that the template can be copied without changing an application's
  existing dependencies or runtime.

### Step 3: Add the coding-agent skill

- Document project discovery and the four required questions.
- Require local-origin verification and Alchemy plan review.
- Require explicit approval for deployment, public exposure, and teardown.
- Document standard systemd diagnostics and browser verification.

### Step 4: Prove the workflow

- Publish one disposable public application.
- Publish one disposable Zero Trust application.
- Reapply each deployment and confirm no unexpected changes.
- Change Zero Trust configuration and inspect the plan.
- Destroy both deployments and confirm that unrelated resources remain intact.

## 14. Acceptance Criteria

The first version is complete when a user can ask a coding agent to publish an
already-running local application and the agent can:

1. Identify and verify its loopback URL.
2. Ask for a `mujo.no` hostname and access mode.
3. Require one allowed email for Zero Trust mode.
4. Add the small project-local infrastructure template.
5. Show and explain the Alchemy plan.
6. Deploy only after approval.
7. Start a persistent connector without exposing its token.
8. Verify public access or the Zero Trust login redirect.
9. Reapply the infrastructure without duplicate resources.
10. Remove the publication without affecting the application or another project.

The workflow should remain understandable by reading the generated
`alchemy.run.ts`, environment example, and systemd unit. If implementing a
requirement needs a generic framework, local database, custom state machine, or
new CLI command, it is outside version 1 unless a real deployment demonstrates
the need.
