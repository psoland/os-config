import {
	chmod,
	mkdtemp,
	mkdir,
	readFile,
	rm,
	stat,
	symlink,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import * as Redacted from "effect/Redacted";
import { afterEach, describe, expect, it } from "vitest";
import {
	buildResourceGraph,
	connectorTokenFileIsCurrent,
	validateConfiguration,
	writeConnectorToken,
} from "./alchemy.run.ts";

const temporaryDirectories: string[] = [];

async function temporaryDirectory() {
	const path = await mkdtemp(join(tmpdir(), "mujo-publish-test-"));
	temporaryDirectories.push(path);
	return path;
}

afterEach(async () => {
	await Promise.all(
		temporaryDirectories.splice(0).map((path) =>
			rm(path, { recursive: true, force: true }),
		),
	);
});

function rawConfiguration(overrides: Record<string, string | undefined> = {}) {
	return {
		hostname: "demo.mujo.no",
		originUrl: "http://127.0.0.1:3000",
		accessMode: "zero-trust",
		accessEmail: "operator@example.com",
		tokenFile: "/var/lib/mujo-publish/demo/tunnel-token",
		...overrides,
	};
}

describe("publishing configuration", () => {
	it("builds a public graph without Access resources", () => {
		const configuration = validateConfiguration(
			rawConfiguration({ accessMode: "public", accessEmail: undefined }),
			"/work/project",
		);
		const graph = buildResourceGraph(configuration);

		expect(graph.access).toBeNull();
		expect(graph.tunnel.ingress).toEqual([
			{
				hostname: "demo.mujo.no",
				service: "http://127.0.0.1:3000",
			},
			{ service: "http_status:404" },
		]);
		expect(graph.dns).toMatchObject({
			name: "demo.mujo.no",
			type: "CNAME",
			proxied: true,
		});
	});

	it("builds exact-hostname and exact-email Zero Trust resources", () => {
		const graph = buildResourceGraph(
			validateConfiguration(rawConfiguration(), "/work/project"),
		);

		expect(graph.access).toMatchObject({
			policy: {
				decision: "allow",
				include: [{ email: { email: "operator@example.com" } }],
			},
			application: {
				type: "self_hosted",
				domain: "demo.mujo.no",
				sessionDuration: "24h",
			},
		});
	});

	it("preserves an explicitly configured default HTTP port", () => {
		const configuration = validateConfiguration(
			rawConfiguration({ originUrl: "http://127.0.0.1:80" }),
			"/work/project",
		);

		expect(configuration.originUrl).toBe("http://127.0.0.1:80");
	});

	it.each([
		["zone apex", { hostname: "mujo.no" }],
		["nested subdomain without Universal SSL coverage", { hostname: "api.demo.mujo.no" }],
		["unrelated domain", { hostname: "demo.example.com" }],
		["uppercase hostname", { hostname: "Demo.mujo.no" }],
		["non-loopback origin", { originUrl: "http://192.0.2.1:3000" }],
		["HTTPS origin", { originUrl: "https://127.0.0.1:3000" }],
		["origin path", { originUrl: "http://127.0.0.1:3000/health" }],
		["missing port", { originUrl: "http://127.0.0.1" }],
		["unknown access mode", { accessMode: "private" }],
		["missing access email", { accessEmail: undefined }],
		["relative token path", { tokenFile: ".state/tunnel-token" }],
		[
			"token path in repository",
			{ tokenFile: "/work/project/.state/tunnel-token" },
		],
	])("rejects %s", (_name, overrides) => {
		expect(() =>
			validateConfiguration(rawConfiguration(overrides), "/work/project"),
		).toThrow();
	});

	it("rejects an outside path that resolves through a symlink into the repository", async () => {
		const root = await temporaryDirectory();
		const repository = join(root, "repository");
		const apparentExternalDirectory = join(root, "token-directory");
		await mkdir(repository);
		await symlink(repository, apparentExternalDirectory);

		expect(() =>
			validateConfiguration(
				rawConfiguration({
					tokenFile: join(apparentExternalDirectory, "tunnel-token"),
				}),
				repository,
			),
		).toThrow("outside the repository");
	});
});

describe("Alchemy ownership compatibility patch", () => {
	async function installedPredicate(
		path: string,
		pattern: RegExp,
		parameters: string[],
	) {
		const source = await readFile(join(import.meta.dirname, "node_modules", path), "utf8");
		const expression = source.match(pattern)?.[1];
		if (!expression) throw new Error(`Could not locate ownership predicate in ${path}`);
		return Function(...parameters, `return Boolean(${expression});`) as (
			...values: unknown[]
		) => boolean;
	}

	it("guards all four remote resource types against implicit adoption", async () => {
		const patch = await readFile(
			join(import.meta.dirname, "patches", "alchemy@2.0.0-beta.72.patch"),
			"utf8",
		);

		expect(patch).toContain("return Unowned(attrs)");
		expect(patch).toContain("Tunnel name ${name} is already owned");
		expect(patch).toContain("DNS record (${news.name}, ${news.type}) is already owned");
		expect(patch).toContain(
			"Access application domain ${body.domain} is already owned",
		);
		expect(patch).toContain("Access policy name ${name} is already owned");
		expect(patch).toContain("existingAtDomain.id !== output?.applicationId");
		expect(patch).toContain(
			"existing.id === output?.policyId || news.adopt",
		);
		expect(patch).toContain("output?.recordId && existing?.id === output.recordId");
		expect(patch).toContain("was created concurrently by another resource");
	});

	it("keeps an application owned when its id lookup transiently fails", async () => {
		const conflicts = await installedPredicate(
			"alchemy/lib/Cloudflare/Access/Application.js",
			/if \((existingAtDomain\?\.id\s*&&\s*existingAtDomain\.id !== output\?\.applicationId\s*&&\s*!news\.adopt)\) \{/s,
			["existingAtDomain", "output", "news"],
		);

		expect(conflicts({ id: "ours" }, { applicationId: "ours" }, { adopt: false })).toBe(false);
		expect(conflicts({ id: "another" }, { applicationId: "ours" }, { adopt: false })).toBe(true);
	});

	it("does not accept a DNS create race without a persisted matching id", async () => {
		const ownsRacedRecord = await installedPredicate(
			"alchemy/lib/Cloudflare/DNS/Record.js",
			/Effect\.flatMap\(\(existing\) =>\s*(output\?\.recordId\s*&&\s*existing\?\.id === output\.recordId)\s*\?/s,
			["existing", "output"],
		);

		expect(ownsRacedRecord({ id: "record" }, undefined)).toBe(false);
		expect(ownsRacedRecord({ id: "record" }, { recordId: "other" })).toBe(false);
		expect(ownsRacedRecord({ id: "record" }, { recordId: "record" })).toBe(true);
	});
});

describe("connector token writer", () => {
	it("writes atomically with private directory and file modes", async () => {
		const root = await temporaryDirectory();
		const tokenFile = join(root, "state", "demo", "tunnel-token");
		const secret = "connector-token-must-not-leak";

		const result = await writeConnectorToken(tokenFile, Redacted.make(secret));

		expect(await readFile(tokenFile, "utf8")).toBe(secret);
		expect((await stat(join(root, "state", "demo"))).mode & 0o777).toBe(0o700);
		expect((await stat(tokenFile)).mode & 0o777).toBe(0o600);
		expect(JSON.stringify(result)).not.toContain(secret);
		expect(
			await connectorTokenFileIsCurrent(tokenFile, Redacted.make(secret)),
		).toBe(true);
	});

	it("atomically replaces an existing token", async () => {
		const root = await temporaryDirectory();
		const parent = join(root, "state", "demo");
		const tokenFile = join(parent, "tunnel-token");
		await mkdir(parent, { recursive: true });
		await writeConnectorToken(tokenFile, Redacted.make("first-token"));

		await writeConnectorToken(tokenFile, Redacted.make("second-token"));

		expect(await readFile(tokenFile, "utf8")).toBe("second-token");
		expect((await stat(tokenFile)).mode & 0o777).toBe(0o600);
	});

	it("detects and repairs unsafe token permissions", async () => {
		const root = await temporaryDirectory();
		const tokenFile = join(root, "state", "demo", "tunnel-token");
		const token = Redacted.make("connector-token");
		await writeConnectorToken(tokenFile, token);
		await chmod(tokenFile, 0o644);

		expect(await connectorTokenFileIsCurrent(tokenFile, token)).toBe(false);

		await writeConnectorToken(tokenFile, token);
		expect(await connectorTokenFileIsCurrent(tokenFile, token)).toBe(true);
	});
});
