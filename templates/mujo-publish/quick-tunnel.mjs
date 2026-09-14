#!/usr/bin/env node
import { spawn } from "node:child_process";
import { createReadStream } from "node:fs";
import { lstat, realpath } from "node:fs/promises";
import http from "node:http";
import { homedir } from "node:os";
import { basename, dirname, extname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const sensitiveName = /(^|[-_.])(secrets?|tokens?|passwords?|credentials?|private|keys?)([-_.]|$)|\.env(?:\.|$)|\.(?:key|pem|p12|pfx)$/i;
const contentTypes = {
  ".css": "text/css; charset=utf-8",
  ".gif": "image/gif",
  ".html": "text/html; charset=utf-8",
  ".ico": "image/x-icon",
  ".jpeg": "image/jpeg",
  ".jpg": "image/jpeg",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".svg": "image/svg+xml",
  ".txt": "text/plain; charset=utf-8",
  ".webp": "image/webp",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
};

function fail(message) {
  throw new Error(message);
}

function isLoopback(hostname) {
  return hostname === "::1" || /^127(?:\.\d{1,3}){3}$/.test(hostname);
}

export function validateOrigin(value) {
  if (value.trim() !== value) fail("--url must not contain surrounding whitespace");
  let origin;
  try {
    origin = new URL(value);
  } catch {
    fail("--url must be a valid URL");
  }
  const hostname = origin.hostname.replace(/^\[|\]$/g, "");
  const explicitPort = /^http:\/\/(?:\[[^\]]+\]|[^/:]+):(\d+)\/?$/.exec(value)?.[1];
  if (
    origin.protocol !== "http:" ||
    !isLoopback(hostname) ||
    !explicitPort ||
    origin.username ||
    origin.password ||
    origin.pathname !== "/" ||
    origin.search ||
    origin.hash
  ) {
    fail("--url must be HTTP on literal loopback with an explicit port and no path");
  }
  const normalizedPort = String(Number(explicitPort));
  const normalizedHost = hostname.includes(":") ? `[${hostname}]` : hostname;
  return `http://${normalizedHost}:${normalizedPort}`;
}

function isSensitive(path) {
  return path.split("/").some((part) => part.startsWith(".") || sensitiveName.test(part));
}

async function isGitRoot(path) {
  try {
    await lstat(join(path, ".git"));
    return true;
  } catch {
    return false;
  }
}

export async function selectContent(value) {
  if (!isAbsolute(value)) fail("--path must be an absolute path");
  const selected = resolve(value);
  const status = await lstat(selected).catch(() => fail("--path does not exist"));
  if (status.isSymbolicLink()) fail("--path must not be a symbolic link");
  if ((await realpath(selected)) !== selected) {
    fail("--path must not contain symbolic links");
  }
  if (!status.isFile() && !status.isDirectory()) {
    fail("--path must select one regular file or directory");
  }
  if (isSensitive(selected)) fail("--path appears to be inside a sensitive path");
  if (status.isDirectory()) {
    const home = await realpath(homedir()).catch(() => homedir());
    if (selected === dirname(selected) || selected === home || (await isGitRoot(selected))) {
      fail("--path must not select a repository root, home, or filesystem root");
    }
  }
  return { path: selected, directory: status.isDirectory() };
}

async function safeFile(root, requestPath) {
  const parts = requestPath.split("/").filter(Boolean);
  if (parts.some((part) => part === "." || part === ".." || isSensitive(part))) return;
  const rootStatus = await lstat(root).catch(() => undefined);
  if (!rootStatus?.isDirectory() || rootStatus.isSymbolicLink()) return;
  let candidate = root;
  for (const part of parts) {
    candidate = join(candidate, part);
    const status = await lstat(candidate).catch(() => undefined);
    if (!status || status.isSymbolicLink()) return;
  }
  const path = resolve(candidate);
  if (relative(root, path).startsWith("..")) return;
  const status = await lstat(path).catch(() => undefined);
  return status?.isFile() ? path : undefined;
}

function respondFile(request, response, path) {
  response.writeHead(200, {
    "Cache-Control": "no-store",
    "Content-Type": contentTypes[extname(path).toLowerCase()] ?? "application/octet-stream",
    "X-Content-Type-Options": "nosniff",
  });
  if (request.method === "HEAD") return response.end();
  createReadStream(path).on("error", () => response.destroy()).pipe(response);
}

export function createContentServer(selection) {
  return http.createServer(async (request, response) => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.writeHead(405, { Allow: "GET, HEAD" });
      return response.end();
    }
    let pathname;
    try {
      pathname = decodeURIComponent(new URL(request.url, "http://localhost").pathname);
    } catch {
      response.writeHead(400);
      return response.end();
    }
    const path = selection.directory
      ? await safeFile(selection.path, pathname === "/" ? "/index.html" : pathname)
      : pathname === "/"
        ? await safeFile(dirname(selection.path), `/${basename(selection.path)}`)
        : undefined;
    if (!path) {
      response.writeHead(404);
      return response.end();
    }
    respondFile(request, response, path);
  });
}

export async function startContentServer(selection, port) {
  const server = createContentServer(selection);
  await new Promise((resolveListen, rejectListen) => {
    const reject = (error) => {
      server.off("listening", listen);
      rejectListen(error);
    };
    const listen = () => {
      server.off("error", reject);
      resolveListen();
    };
    server.once("error", reject);
    server.once("listening", listen);
    server.listen(port, "127.0.0.1");
  });
  const address = server.address();
  if (!address || typeof address === "string") {
    server.close();
    fail("could not determine the loopback file server port");
  }
  return { server, origin: `http://127.0.0.1:${address.port}` };
}

function closeServer(server) {
  server?.closeAllConnections?.();
  server?.close();
}

export const helpText = `Usage:
  node quick-tunnel.mjs --url http://127.0.0.1:3000 [--cloudflared /path/to/cloudflared]
  node quick-tunnel.mjs --path /absolute/path/to/content [--cloudflared /path/to/cloudflared]
  node quick-tunnel.mjs --serve-only --path /absolute/path/to/content --port 8787

Quick Tunnel mode is public and stops with Ctrl-C. --serve-only starts only the
selected-content server on 127.0.0.1 for a named tunnel; it never starts Cloudflare.
Requires Node.js 20+ and cloudflared for Quick Tunnel mode.`;

function parseArguments(arguments_) {
  const options = { cloudflared: process.env.CLOUDFLARED_BINARY ?? "cloudflared" };
  for (let index = 0; index < arguments_.length; index += 1) {
    const option = arguments_[index];
    if (option === "--help") {
      if (arguments_.length !== 1) fail("--help cannot be combined with other options");
      return { help: true };
    }
    if (option === "--serve-only") {
      options.serveOnly = true;
    } else if (option === "--url" || option === "--path" || option === "--cloudflared" || option === "--port") {
      const value = arguments_[index + 1];
      if (!value || value.startsWith("--")) fail(`${option} needs a value`);
      options[option.slice(2)] = value;
      index += 1;
    } else {
      fail(`unknown option: ${option}`);
    }
  }
  if (options.serveOnly) {
    if (options.url || !options.path || !options.port || !/^([1-9]\d{0,4})$/.test(options.port) || Number(options.port) > 65535) {
      fail("--serve-only requires --path and a port from 1 through 65535");
    }
  } else if (options.port) {
    fail("--port is only valid with --serve-only");
  } else if (Boolean(options.url) === Boolean(options.path)) {
    fail("provide exactly one of --url or --path");
  }
  return options;
}

export async function run(arguments_ = process.argv.slice(2)) {
  const options = parseArguments(arguments_);
  if (options.help) {
    process.stdout.write(`${helpText}\n`);
    return;
  }
  let server;
  let origin;
  if (options.path) {
    const selection = await selectContent(options.path);
    const started = await startContentServer(selection, options.serveOnly ? Number(options.port) : 0);
    server = started.server;
    origin = started.origin;
    process.stderr.write(`Serving only ${selection.directory ? "selected directory" : "selected file"} on ${origin}\n`);
  } else {
    origin = validateOrigin(options.url);
  }
  if (options.serveOnly) {
    const stop = () => {
      closeServer(server);
      process.exitCode = 0;
    };
    process.once("SIGINT", stop);
    process.once("SIGTERM", stop);
    return;
  }
  const tunnel = spawn(options.cloudflared, ["tunnel", "--no-autoupdate", "--url", origin], {
    stdio: "inherit",
  });
  let stopping = false;
  const stop = () => {
    stopping = true;
    tunnel.kill("SIGTERM");
  };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);
  tunnel.once("error", (error) => {
    process.stderr.write(`Could not start cloudflared: ${error.message}\n`);
    closeServer(server);
    process.exitCode = 1;
  });
  tunnel.once("exit", (code) => {
    closeServer(server);
    process.exitCode = stopping ? 0 : code ?? 1;
  });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run().catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = 1;
  });
}
