import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

function run(request) {
  return spawnSync(process.execPath, ["dist/render.mjs"], {
    input: JSON.stringify(request),
    encoding: "utf8",
    timeout: 10000,
  });
}
const fixtures = {
  flowchart: "flowchart LR\n A[Hello] --> B[World]",
  sequence: "sequenceDiagram\n Alice->>Bob: Hello",
  state: "stateDiagram-v2\n [*] --> Ready\n Ready --> [*]",
  gantt: "gantt\n dateFormat YYYY-MM-DD\n section Work\n Task :2026-10-13, 1d",
  gitGraph: "gitGraph\n commit\n branch feature\n checkout feature\n commit",
  timeline: "timeline\n title Release\n 2026 : Preview",
};
for (const [kind, source] of Object.entries(fixtures)) {
  const result = run({ source, width: 100 });
  assert.equal(result.status, 0, result.stderr);
  const diagram = JSON.parse(result.stdout);
  assert.equal(diagram.kind, kind);
  assert(
    diagram.lines.some((line) => line.trim()),
    kind,
  );
  assert(diagram.highlights.length > 0, kind);
  for (const span of diagram.highlights) {
    const line = diagram.lines[span.line];
    assert(
      span.start >= 0 &&
        span.end <= Buffer.byteLength(line) &&
        span.start < span.end,
    );
  }
}
const unicode = run({
  source: 'flowchart LR\n A["日本語 👋"] --> B["<i>Italic</i>"]',
  width: 80,
});
assert.equal(unicode.status, 0, unicode.stderr);
const diagram = JSON.parse(unicode.stdout);
assert(diagram.lines.join("\n").includes("日本語 👋"));
assert(diagram.highlights.some((span) => span.italic));
for (const request of [
  { source: "pie\n title Unsupported" },
  { source: "flowchart LR\n A[Broken" },
  { source: "" },
  { source: fixtures.flowchart, width: 0 },
  { source: fixtures.flowchart, width: 1.5 },
  { source: "x".repeat(128 * 1024 + 1) },
]) {
  const result = run(request);
  assert.equal(result.status, 1, JSON.stringify(request).slice(0, 100));
  assert(result.stderr.trim());
  assert.equal(result.stdout, "");
}
console.log("merman-nvim: all renderer tests passed");
