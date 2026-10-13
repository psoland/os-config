import { detectMermaidDiagram } from "./upstream/detect.js";
import { parseMermaidFlowchartDiagram } from "./upstream/flowchart/parser.js";
import { drawFlowchartDiagramGrid } from "./upstream/flowchart/drawing.js";
import { parseMermaidSequenceDiagram } from "./upstream/sequence/parser.js";
import { drawSequenceDiagramGrid } from "./upstream/sequence/drawing.js";
import { parseMermaidStateDiagram } from "./upstream/state/parser.js";
import { drawStateDiagramGrid } from "./upstream/state/drawing.js";
import { parseMermaidGanttDiagram } from "./upstream/gantt/parser.js";
import { drawGanttDiagramGrid } from "./upstream/gantt/drawing.js";
import { parseMermaidGitGraphDiagram } from "./upstream/gitgraph/parser.js";
import { drawGitGraphDiagramGrid } from "./upstream/gitgraph/drawing.js";
import { parseMermaidTimelineDiagram } from "./upstream/timeline/parser.js";
import { drawTimelineDiagramGrid } from "./upstream/timeline/drawing.js";

async function main() {
  const chunks: Buffer[] = [];
  let bytes = 0;
  for await (const chunk of process.stdin) {
    bytes += chunk.length;
    if (bytes > 1024 * 1024) throw new Error("Mermaid request exceeds 1 MiB");
    chunks.push(chunk);
  }
  const request = JSON.parse(Buffer.concat(chunks).toString("utf8"));
  if (typeof request.source !== "string" || !request.source.trim()) {
    throw new Error("A non-empty Mermaid source string is required");
  }
  if (Buffer.byteLength(request.source) > 128 * 1024)
    throw new Error("Mermaid source exceeds 128 KiB");
  const width = request.width ?? 120;
  if (!Number.isSafeInteger(width) || width < 1 || width > 512) {
    throw new Error("Layout width must be an integer between 1 and 512");
  }
  const kind = detectMermaidDiagram(request.source);
  let grid;
  switch (kind) {
    case "flowchart":
      grid = drawFlowchartDiagramGrid(
        parseMermaidFlowchartDiagram(request.source),
        { compact: true, layoutMaxWidth: width },
      );
      break;
    case "sequence":
      grid = drawSequenceDiagramGrid(
        parseMermaidSequenceDiagram(request.source),
        { compact: true },
      );
      break;
    case "state":
      grid = drawStateDiagramGrid(parseMermaidStateDiagram(request.source), {
        layoutMaxWidth: width,
      });
      break;
    case "gantt":
      grid = drawGanttDiagramGrid(parseMermaidGanttDiagram(request.source), {
        layoutMaxWidth: width,
      });
      break;
    case "gitGraph":
      grid = drawGitGraphDiagramGrid(
        parseMermaidGitGraphDiagram(request.source),
      );
      break;
    case "timeline":
      grid = drawTimelineDiagramGrid(
        parseMermaidTimelineDiagram(request.source),
      );
      break;
    default:
      throw new Error(
        "Unsupported diagram. Merman supports flowchart, sequenceDiagram, stateDiagram, gantt, gitGraph and timeline",
      );
  }
  const lines = [""];
  const highlights: {
    line: number;
    start: number;
    end: number;
    style: string;
    italic: boolean;
  }[] = [];
  grid.forEachRun(
    (run) => {
      const line = lines.length - 1;
      const start = Buffer.byteLength(lines[line]);
      lines[line] += run.text;
      if (run.style) {
        highlights.push({
          line,
          start,
          end: Buffer.byteLength(lines[line]),
          style: run.style,
          italic: Boolean(run.cell.attributes & 4),
        });
      }
    },
    () => lines.push(""),
    {
      trimTop: true,
      trimBottom: true,
      key: (cell) => [cell.style, cell.attributes],
    },
  );
  process.stdout.write(JSON.stringify({ kind, lines, highlights }) + "\n");
}

main().catch((error) => {
  process.stderr.write(
    (error instanceof Error ? error.message : String(error)) + "\n",
  );
  process.exitCode = 1;
});
