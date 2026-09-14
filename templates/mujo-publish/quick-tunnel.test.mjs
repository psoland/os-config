import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { access, chmod, mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { createContentServer, selectContent, validateOrigin } from "./quick-tunnel.mjs";

async function temporaryDirectory() {
  return mkdtemp(join(tmpdir(), "mujo-quick-tunnel-test-"));
}

test("accepts only literal loopback HTTP origins with explicit ports", () => {
  assert.equal(validateOrigin("http://127.0.0.1:3000"), "http://127.0.0.1:3000");
  assert.equal(validateOrigin("http://127.0.0.1:80"), "http://127.0.0.1:80");
  assert.throws(() => validateOrigin("http://localhost:3000"));
  assert.throws(() => validateOrigin("https://127.0.0.1:3000"));
  assert.throws(() => validateOrigin("http://127.0.0.1:3000/admin"));
});

test("serves a selected directory without dotfiles, secrets, or symlinks", async (context) => {
  const root = await temporaryDirectory();
  context.after(() => rm(root, { recursive: true, force: true }));
  const published = join(root, "public");
  await mkdir(published);
  await writeFile(join(published, "index.html"), "safe page");
  await writeFile(join(published, ".env"), "not public");
  await writeFile(join(root, "secret.txt"), "not public");
  await symlink(join(root, "secret.txt"), join(published, "linked.txt"));
  await symlink(published, join(root, "public-link"));
  await assert.rejects(selectContent(join(root, "public-link")));
  const server = createContentServer(await selectContent(published));
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  context.after(() => server.close());
  const origin = `http://127.0.0.1:${server.address().port}`;
  assert.equal((await fetch(`${origin}/`)).status, 200);
  assert.equal(await (await fetch(`${origin}/`)).text(), "safe page");
  assert.equal((await fetch(`${origin}/.env`)).status, 404);
  assert.equal((await fetch(`${origin}/linked.txt`)).status, 404);
});

test("serves one selected regular file and rejects repository roots", async (context) => {
  const root = await temporaryDirectory();
  context.after(() => rm(root, { recursive: true, force: true }));
  const file = join(root, "report.txt");
  await writeFile(file, "single file");
  await mkdir(join(root, ".git"));
  await mkdir(join(root, ".ssh"));
  await writeFile(join(root, ".ssh", "id_rsa"), "not public");
  await mkdir(join(root, "credentials"));
  await writeFile(join(root, "credentials", "report.txt"), "not public");
  await assert.rejects(selectContent(root));
  await assert.rejects(selectContent(join(root, ".ssh", "id_rsa")));
  await assert.rejects(selectContent(join(root, "credentials", "report.txt")));
  const server = createContentServer(await selectContent(file));
  await new Promise((resolveListen) => server.listen(0, "127.0.0.1", resolveListen));
  context.after(() => server.close());
  const origin = `http://127.0.0.1:${server.address().port}`;
  assert.equal(await (await fetch(`${origin}/`)).text(), "single file");
  assert.equal((await fetch(`${origin}/report.txt`)).status, 404);
});

function startHelper(arguments_, environment = {}) {
  return spawn(process.execPath, [join(import.meta.dirname, "quick-tunnel.mjs"), ...arguments_], {
    env: { ...process.env, ...environment },
    stdio: ["ignore", "pipe", "pipe"],
  });
}

function waitForOrigin(child) {
  return new Promise((resolveOrigin, rejectOrigin) => {
    let output = "";
    child.stderr.on("data", (chunk) => {
      output += chunk;
      const origin = /on (http:\/\/127\.0\.0\.1:\d+)/.exec(output)?.[1];
      if (origin) resolveOrigin(origin);
    });
    child.once("error", rejectOrigin);
    child.once("close", (code) => rejectOrigin(new Error(`helper exited before listening: ${code}`)));
  });
}

async function stop(child) {
  const closed = once(child, "close");
  child.kill("SIGINT");
  const [code] = await closed;
  assert.equal(code, 0);
}

async function waitForFile(path) {
  for (let attempt = 0; attempt < 50; attempt += 1) {
    try {
      await access(path);
      return;
    } catch {
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 10));
    }
  }
  throw new Error(`fixture did not create ${path}`);
}

test("serve-only binds a fixed loopback port and closes active connections on Ctrl-C", async (context) => {
  const root = await temporaryDirectory();
  context.after(() => rm(root, { recursive: true, force: true }));
  const published = join(root, "public");
  await mkdir(published);
  await writeFile(join(published, "index.html"), "persistent page");
  const child = startHelper(["--serve-only", "--path", published, "--port", "18787"]);
  const origin = await waitForOrigin(child);
  assert.equal(origin, "http://127.0.0.1:18787");
  assert.equal(await (await fetch(`${origin}/`)).text(), "persistent page");
  await stop(child);
  await assert.rejects(fetch(`${origin}/`, { signal: AbortSignal.timeout(500) }));
});

test("Quick Tunnel starts a child without Cloudflare and shuts its file server down", async (context) => {
  const root = await temporaryDirectory();
  context.after(() => rm(root, { recursive: true, force: true }));
  const published = join(root, "public");
  const fixture = join(root, "fake-cloudflared.mjs");
  const argumentsFile = join(root, "cloudflared-arguments.json");
  await mkdir(published);
  await writeFile(join(published, "index.html"), "temporary page");
  await writeFile(
    fixture,
    "#!/usr/bin/env node\nimport { writeFileSync } from 'node:fs';\nwriteFileSync(process.env.FAKE_CLOUDFLARED_ARGS, JSON.stringify(process.argv.slice(2)));\nprocess.on('SIGTERM', () => process.exit(0));\nsetInterval(() => {}, 1000);\n",
  );
  await chmod(fixture, 0o755);
  const child = startHelper(["--path", published, "--cloudflared", fixture], {
    FAKE_CLOUDFLARED_ARGS: argumentsFile,
  });
  const origin = await waitForOrigin(child);
  assert.equal(await (await fetch(`${origin}/`)).text(), "temporary page");
  await waitForFile(argumentsFile);
  await stop(child);
  assert.deepEqual(JSON.parse(await readFile(argumentsFile, "utf8")), [
    "tunnel",
    "--no-autoupdate",
    "--url",
    origin,
  ]);
  await assert.rejects(fetch(`${origin}/`, { signal: AbortSignal.timeout(500) }));
});
