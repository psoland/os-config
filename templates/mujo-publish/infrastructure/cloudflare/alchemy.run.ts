import { existsSync, realpathSync } from "node:fs";
import { randomUUID } from "node:crypto";
import {
	chmod,
	lstat,
	mkdir,
	readFile,
	rename,
	stat,
	unlink,
	writeFile,
} from "node:fs/promises";
import { isIP } from "node:net";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import * as Alchemy from "alchemy";
import * as Cloudflare from "alchemy/Cloudflare";
import * as Output from "alchemy/Output";
import * as Provider from "alchemy/Provider";
import {
	Resource as createResource,
	type Resource as ResourceDefinition,
} from "alchemy/Resource";
import * as Config from "effect/Config";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import * as Redacted from "effect/Redacted";

const zoneName = "mujo.no";
const stackName = "__ALCHEMY_STACK_NAME__";
const tunnelName = "__TUNNEL_NAME__";
const displayName = "__DISPLAY_NAME__";
const accessSessionDuration = "24h";
const projectRoot = resolve(import.meta.dirname, "../..");

type AccessMode = "public" | "zero-trust";

interface RawConfiguration {
	hostname: string;
	originUrl: string;
	accessMode: string;
	accessEmail?: string;
	tokenFile: string;
}

interface CommonConfiguration {
	hostname: string;
	originUrl: string;
	tokenFile: string;
}

export type PublishConfiguration =
	| (CommonConfiguration & { accessMode: "public" })
	| (CommonConfiguration & {
			accessMode: "zero-trust";
			accessEmail: string;
	  });

// The zone's standard Universal SSL coverage is for direct subdomains only.
const hostnamePattern = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.mujo\.no$/;
const emailPattern = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

function fail(message: string): never {
	throw new Error(message);
}

export function validateConfiguration(
	raw: RawConfiguration,
	repositoryRoot = projectRoot,
): PublishConfiguration {
	if (!hostnamePattern.test(raw.hostname)) {
		fail(
			"MUJO_HOSTNAME must be one lowercase direct subdomain of mujo.no (for example, demo.mujo.no)",
		);
	}

	if (raw.originUrl.trim() !== raw.originUrl) {
		fail("MUJO_ORIGIN_URL must not contain leading or trailing whitespace");
	}

	let origin: URL;
	try {
		origin = new URL(raw.originUrl);
	} catch {
		fail("MUJO_ORIGIN_URL must be a valid URL");
	}

	const originHost = origin.hostname.replace(/^\[|\]$/g, "");
	const hasExplicitPort =
		/^http:\/\/(?:\[[^\]]+\]|[^/:]+):\d+\/?$/.test(raw.originUrl);
	const loopback =
		(isIP(originHost) === 4 && originHost.split(".")[0] === "127") ||
		(isIP(originHost) === 6 && originHost === "::1");
	if (
		origin.protocol !== "http:" ||
		!loopback ||
		!hasExplicitPort ||
		origin.username ||
		origin.password ||
		origin.pathname !== "/" ||
		origin.search ||
		origin.hash
	) {
		fail(
			"MUJO_ORIGIN_URL must be HTTP on a literal loopback address with an explicit port and no path (for example, http://127.0.0.1:3000)",
		);
	}

	if (raw.accessMode !== "public" && raw.accessMode !== "zero-trust") {
		fail("MUJO_ACCESS_MODE must be exactly public or zero-trust");
	}
	const accessMode: AccessMode = raw.accessMode;

	if (accessMode === "zero-trust") {
		if (
			!raw.accessEmail ||
			raw.accessEmail.trim() !== raw.accessEmail ||
			!emailPattern.test(raw.accessEmail)
		) {
			fail(
				"MUJO_ACCESS_EMAIL must contain one exact email address in zero-trust mode",
			);
		}
	} else if (raw.accessEmail) {
		fail("MUJO_ACCESS_EMAIL must be unset in public mode");
	}

	if (!isAbsolute(raw.tokenFile)) {
		fail("CLOUDFLARED_TOKEN_FILE must be an absolute path");
	}
	const tokenFile = resolve(raw.tokenFile);
	let existingTokenAncestor = dirname(tokenFile);
	while (!existsSync(existingTokenAncestor)) {
		const parent = dirname(existingTokenAncestor);
		if (parent === existingTokenAncestor) break;
		existingTokenAncestor = parent;
	}
	const physicalTokenFile = resolve(
		realpathSync(existingTokenAncestor),
		relative(existingTokenAncestor, tokenFile),
	);
	const resolvedRepositoryRoot = resolve(repositoryRoot);
	const tokenRelativeToRepository = relative(
		existsSync(resolvedRepositoryRoot)
			? realpathSync(resolvedRepositoryRoot)
			: resolvedRepositoryRoot,
		physicalTokenFile,
	);
	if (
		tokenRelativeToRepository === "" ||
		(!tokenRelativeToRepository.startsWith(`..${sep}`) &&
			tokenRelativeToRepository !== "..")
	) {
		fail("CLOUDFLARED_TOKEN_FILE must be outside the repository");
	}

	const common = {
		hostname: raw.hostname,
		originUrl: raw.originUrl.endsWith("/")
			? raw.originUrl.slice(0, -1)
			: raw.originUrl,
		tokenFile,
	};
	return accessMode === "zero-trust"
		? { ...common, accessMode, accessEmail: raw.accessEmail as string }
		: { ...common, accessMode };
}

export function buildResourceGraph(configuration: PublishConfiguration) {
	const tunnel = {
		name: tunnelName,
		configSrc: "cloudflare" as const,
		ingress: [
			{
				hostname: configuration.hostname,
				service: configuration.originUrl,
			},
			{ service: "http_status:404" },
		],
	};
	const dns = {
		name: configuration.hostname,
		type: "CNAME" as const,
		proxied: true,
	};

	if (configuration.accessMode === "public") {
		return { tunnel, dns, access: null };
	}

	return {
		tunnel,
		dns,
		access: {
			policy: {
				name: `${displayName} operator`,
				decision: "allow" as const,
				include: [{ email: { email: configuration.accessEmail } }],
			},
			application: {
				type: "self_hosted" as const,
				name: displayName,
				domain: configuration.hostname,
				sessionDuration: accessSessionDuration,
			},
		},
	};
}

export async function writeConnectorToken(
	path: string,
	token: Redacted.Redacted<string>,
): Promise<{ path: string }> {
	const parent = dirname(path);
	const temporaryPath = `${path}.${process.pid}.${randomUUID()}.tmp`;
	await mkdir(parent, { recursive: true, mode: 0o700 });
	if ((await lstat(parent)).isSymbolicLink()) {
		throw new Error(`Connector token directory must not be a symlink: ${parent}`);
	}
	await chmod(parent, 0o700);

	try {
		await writeFile(temporaryPath, Redacted.value(token), {
			encoding: "utf8",
			mode: 0o600,
			flag: "wx",
		});
		await chmod(temporaryPath, 0o600);
		await rename(temporaryPath, path);
	} catch (error) {
		await unlink(temporaryPath).catch(() => undefined);
		throw new Error(`Could not write the cloudflared token to ${path}`, {
			cause: error,
		});
	}

	return { path };
}

export async function connectorTokenFileIsCurrent(
	path: string,
	token: Redacted.Redacted<string>,
): Promise<boolean> {
	try {
		const parent = dirname(path);
		const [parentStatus, tokenStatus, currentToken] = await Promise.all([
			lstat(parent),
			stat(path),
			readFile(path, "utf8"),
		]);
		return (
			parentStatus.isDirectory() &&
			!parentStatus.isSymbolicLink() &&
			(parentStatus.mode & 0o777) === 0o700 &&
			tokenStatus.isFile() &&
			(tokenStatus.mode & 0o777) === 0o600 &&
			currentToken === Redacted.value(token)
		);
	} catch {
		return false;
	}
}

interface ConnectorTokenFileProps {
	path: string;
	token: Redacted.Redacted<string>;
}

type ConnectorTokenFileResource = ResourceDefinition<
	"Mujo.ConnectorTokenFile",
	ConnectorTokenFileProps,
	{ path: string }
>;

const ConnectorTokenFile = createResource<ConnectorTokenFileResource>(
	"Mujo.ConnectorTokenFile",
);

const ConnectorTokenFileProvider = () =>
	Provider.succeed(ConnectorTokenFile, {
		read: ({ olds, output }) =>
			Effect.promise(() => connectorTokenFileIsCurrent(olds.path, olds.token)).pipe(
				Effect.map((current) => (current ? output : undefined)),
			),
		reconcile: ({ news }) =>
			Effect.tryPromise({
				try: () => writeConnectorToken(news.path, news.token),
				catch: (error) =>
					error instanceof Error
						? error
						: new Error(`Could not write the cloudflared token to ${news.path}`),
			}),
		// Local secret files are deliberately retained during Cloudflare teardown.
		delete: () => Effect.void,
		list: () => Effect.succeed([]),
	});

const ResolveZone = Alchemy.Action(
	"ResolveZone",
	Effect.fn(function* (input: { accountId: string; name: string }) {
		const zone = yield* Cloudflare.Zone.findZoneByName({
			accountId: input.accountId,
			name: input.name,
		});
		if (!zone) {
			return yield* Effect.fail(
				new Error(`Cloudflare zone ${input.name} was not found`),
			);
		}

		return { zoneId: zone.id };
	}),
);

export default Alchemy.Stack(
	stackName,
	{
		providers: Layer.merge(
			Cloudflare.providers(),
			ConnectorTokenFileProvider(),
		),
		state: Cloudflare.state(),
	},
	Effect.gen(function* () {
		const accessMode = yield* Config.string("MUJO_ACCESS_MODE");
		const rawConfiguration: RawConfiguration = {
			hostname: yield* Config.string("MUJO_HOSTNAME"),
			originUrl: yield* Config.string("MUJO_ORIGIN_URL"),
			accessMode,
			accessEmail:
				accessMode === "zero-trust"
					? yield* Config.string("MUJO_ACCESS_EMAIL")
					: undefined,
			tokenFile: yield* Config.string("CLOUDFLARED_TOKEN_FILE"),
		};
		const configuration = yield* Effect.sync(() =>
			validateConfiguration(rawConfiguration),
		);
		const graph = buildResourceGraph(configuration);

		const tunnel = yield* Cloudflare.Tunnel.Tunnel(
			"__RESOURCE_PREFIX__Tunnel",
			{
				...graph.tunnel,
				adopt: false,
			},
		);
		const zone = yield* ResolveZone("__RESOURCE_PREFIX__ZoneLookup", {
			accountId: tunnel.accountId,
			name: zoneName,
		});
		yield* Cloudflare.DNS.Record("__RESOURCE_PREFIX__Dns", {
			zoneId: zone.zoneId,
			...graph.dns,
			content: Output.interpolate`${tunnel.tunnelId}.cfargotunnel.com`,
			comment: `${displayName} Cloudflare Tunnel`,
		});

		if (graph.access) {
			const accessPolicy = yield* Cloudflare.Access.Policy(
				"__RESOURCE_PREFIX__AccessPolicy",
				{
					...graph.access.policy,
					adopt: false,
				},
			);

			yield* Cloudflare.Access.Application(
				"__RESOURCE_PREFIX__AccessApplication",
				{
					...graph.access.application,
					policies: [accessPolicy.policyId],
					adopt: false,
				},
			);
		}

		const connectorToken = yield* ConnectorTokenFile(
			"__RESOURCE_PREFIX__ConnectorTokenFile",
			{
				path: configuration.tokenFile,
				token: tunnel.token,
			},
		);

		return {
			url: `https://${configuration.hostname}`,
			accessMode: configuration.accessMode,
			tunnelId: tunnel.tunnelId,
			tunnelName: tunnel.tunnelName,
			tokenPath: connectorToken.path,
		};
	}),
);
