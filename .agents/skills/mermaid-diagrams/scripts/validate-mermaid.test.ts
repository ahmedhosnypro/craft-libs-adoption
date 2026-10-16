import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  extractMermaidBlocks,
  isKnownDiagramKeyword,
  KNOWN_DIAGRAM_KEYWORDS,
  validateDiagramSource,
} from "./validate-mermaid";

const FENCE = "```mermaid";
const CLOSE = "```";

/** Join markdown lines LF-style (common committed shape). */
function mdOf(lines: readonly string[]): string {
  return lines.join("\n");
}

let scratchBase: string | null = null;

/** Lazily create one shared temp workspace; every caller gets its absolute directory. */
async function openScratch(): Promise<string> {
  scratchBase ??= await mkdtemp(join(tmpdir(), "validate-mermaid-test-"));
  return scratchBase;
}

async function scratchFile(name: string, content: string): Promise<string> {
  const dir = await openScratch();
  const target = join(dir, name);
  await writeFile(target, content);
  return target;
}

afterAll(async () => {
  if (scratchBase !== null) await rm(scratchBase, { recursive: true, force: true });
});

/** Spawn helper targeting the real validator script (array argv only). */
function runValidator(args: readonly string[], cwd?: string): Promise<{ code: number; out: string; err: string }> {
  const proc = Bun.spawn([process.execPath, join(import.meta.dir, "validate-mermaid.ts"), ...args], {
    cwd: cwd ?? skillRoot(),
    stdout: "pipe",
    stderr: "pipe",
  });
  const outPromise = new Response(proc.stdout).text();
  const errPromise = new Response(proc.stderr).text();
  return proc.exited.then(async code => ({ code, out: await outPromise, err: await errPromise }));
}

/** Skill root = parent of the scripts directory. */
function skillRoot(): string {
  return join(import.meta.dir, "..");
}

describe("KNOWN_DIAGRAM_KEYWORDS — curated list contract", () => {
  test("contains every required keyword family plus tolerant variants", () => {
    for (const required of [
      "flowchart",
      "graph",
      "sequencediagram",
      "classdiagram",
      "statediagram",
      "statediagram-v2",
      "erdiagram",
      "journey",
      "gantt",
      "pie",
      "mindmap",
      "timeline",
      "quadrantchart",
      "gitgraph",
      "c4context",
      "c4container",
      "c4component",
      "c4dynamic",
      "c4deployment",
      "requirementdiagram",
      "sankey-beta",
      "xychart-beta",
      "architecture-beta",
      "block-beta",
      "kanban",
      "radar",
      "radar-beta",
    ]) {
      expect(KNOWN_DIAGRAM_KEYWORDS).toContain(required);
    }
  });

  test("membership check is case-insensitive whole-token equality", () => {
    expect(isKnownDiagramKeyword("SequenceDiagram")).toBe(true);
    expect(isKnownDiagramKeyword("STATEDIAGRAM-V2")).toBe(true);
    expect(isKnownDiagramKeyword("pie")).toBe(true);
    expect(isKnownDiagramKeyword("diagram")).toBe(false);
    expect(isKnownDiagramKeyword("sequencediagrams")).toBe(false); // no prefix fuzzing
  });
});

describe("extractMermaidBlocks — fence parsing", () => {
  test("single well-formed block captures start/end/body", () => {
    const blocks = extractMermaidBlocks(mdOf(["# Doc", "", FENCE, "flowchart TD", "A --> B", CLOSE, "done"]));
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.startLine).toBe(3);
    expect(blocks[0]?.endLine).toBe(6);
    expect(blocks[0]?.source).toBe(mdOf(["flowchart TD", "A --> B"]));
    expect(blocks[0]?.infoString).toBeNull();
  });

  test("multiple blocks appear in order with independent positions", () => {
    const blocks = extractMermaidBlocks(mdOf([FENCE, "gantt", CLOSE, "prose", FENCE, "pie", "size 42", CLOSE]));
    expect(blocks.map(block => block.startLine)).toStrictEqual([1, 5]);
    expect(blocks[1]?.source).toBe(mdOf(["pie", "size 42"]));
  });

  test("unterminated fence reports null endLine attributed to the opening line", () => {
    const blocks = extractMermaidBlocks(mdOf(["# Doc", FENCE, "flowchart TD", "A --> B"]));
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.startLine).toBe(2);
    expect(blocks[0]?.endLine).toBeNull();
  });

  test("plain non-mermaid fences do not disturb pairing across the file", () => {
    const blocks = extractMermaidBlocks(mdOf(["```ts", "const x = 1;", CLOSE, "", FENCE, "erDiagram", CLOSE, "tail"]));
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.startLine).toBe(5);
  });

  test("fence-less markdown yields zero blocks", () => {
    expect(extractMermaidBlocks("# prose only\n\ntext")).toStrictEqual([]);
  });
});

describe("extractMermaidBlocks — DEFINED BEHAVIOR tolerance choices", () => {
  test("opening fence with an info-string suffix opens a block and keeps it inert", () => {
    const blocks = extractMermaidBlocks(mdOf([`${FENCE} title="Pipeline stages"`, "flowchart LR", "A --> B", CLOSE]));
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.infoString).toBe('title="Pipeline stages"');
  });

  test("misspelled words after backticks do NOT open a block", () => {
    expect(extractMermaidBlocks(mdOf(["```mermaidx", CLOSE]))).toStrictEqual([]);
    expect(extractMermaidBlocks(mdOf(["``` mermaid", "flowchart TD", CLOSE]))).toStrictEqual([]);
  });

  test("inline-code prose containing the fence substring mid-line does not open a block", () => {
    expect(extractMermaidBlocks(mdOf([`Use ${FENCE} to open a diagram.`]))).toStrictEqual([]);
  });

  test("indented opener up to 3 spaces opens; deeper indentation does not", () => {
    expect(extractMermaidBlocks(mdOf(["   " + FENCE, "graph LR", CLOSE]))).toHaveLength(1);
    expect(extractMermaidBlocks(mdOf(["    " + FENCE, "graph LR", CLOSE]))).toStrictEqual([]);
  });

  test("four-backtick outer wrappers stay transparent around an inner block", () => {
    const blocks = extractMermaidBlocks(mdOf(["````md", FENCE, "flowchart LR", "A --> B", CLOSE, "````"]));
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.startLine).toBe(2);
    expect(blocks[0]?.endLine).toBe(5);
  });

  test("CRLF payloads parse identically to LF", () => {
    const crlf = `${FENCE}\r\nstateDiagram-v2\r\n[*] --> s1\r\n${CLOSE}\r\n`;
    const blocks = extractMermaidBlocks(crlf);
    expect(blocks).toHaveLength(1);
    expect(validateDiagramSource(blocks[0]?.source ?? "")).toStrictEqual([]);
  });
});

describe("validateDiagramSource — Tier 1 core rules", () => {
  test("valid flowchart passes clean", () => {
    expect(
      validateDiagramSource(mdOf(["flowchart TD", "A[Start] --> B{Choice}", "B -- yes --> C[End]"]))
    ).toStrictEqual([]);
  });

  test("valid sequenceDiagram passes clean", () => {
    expect(
      validateDiagramSource(mdOf(["sequenceDiagram", "participant U as User", "U->>S: request", "S-->>U: reply"]))
    ).toStrictEqual([]);
  });

  test("valid stateDiagram-v2 passes clean", () => {
    expect(validateDiagramSource(mdOf(["stateDiagram-v2", "[*] --> Draft", "Draft --> Sent"]))).toStrictEqual([]);
  });

  test("case-insensitive declaration (GRAPH uppercase) accepted", () => {
    expect(validateDiagramSource(mdOf(["GRAPH LR", "A --> B"]))).toStrictEqual([]);
  });

  test("beta-suffix tolerance: radar and radar-beta both pass", () => {
    expect(validateDiagramSource("radar-beta")[0]).toBeUndefined();
    expect(validateDiagramSource("radar")).toHaveLength(0);
  });

  test("empty / whitespace / comment-only sources fail emptiness at relative line 1", () => {
    for (const source of ["", "   \n\t ", "%% just a note\n%%another"]) {
      const issues = validateDiagramSource(source);
      expect(issues).toHaveLength(1);
      expect(issues[0]?.line).toBe(1);
      expect(issues[0]?.message).toContain("empty diagram");
    }
  });

  test("unknown first-line keyword fails naming the offending token", () => {
    const issues = validateDiagramSource(mdOf(["%% preamble", "", "worrisome TD", "A --> B"]));
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(3); // skipped blank+comment lines while locating
    expect(issues[0]?.message).toContain('unknown diagram type "worrisome"');
  });
});

describe("validateDiagramSource — Tier 2 boundaries", () => {
  test("declaration with direction argument validates the first token only", () => {
    expect(validateDiagramSource("flowchart LR\nA --> B")).toStrictEqual([]);
    expect(validateDiagramSource("graph TB\nA --> B")).toStrictEqual([]);
  });

  test("bare-arrow line inside graph family is flagged at its own line", () => {
    const issues = validateDiagramSource(mdOf(["graph TD", "A --> B", "--> C"]));
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(3);
    expect(issues[0]?.message).toContain("malformed edge");
    expect(issues[0]?.message).toContain('"-->"');
  });

  test("same bare-arrow inside non-graph families stays unchecked (under-flagging)", () => {
    expect(validateDiagramSource(mdOf(["sequenceDiagram", "--> nowhere"]))).toStrictEqual([]);
    expect(validateDiagramSource(mdOf(["stateDiagram-v2", "--> somewhere"]))).toStrictEqual([]);
  });

  test("legitimate arrows/labels/subgraphs produce no false positives", () => {
    const body = [
      "flowchart TD",
      "subgraph cluster",
      "A -->|label text| B",
      "B -.-> C",
      "C ==> D",
      "D --x E",
      "E --- F",
      "end",
      "style A fill:#f96",
    ];
    expect(validateDiagramSource(mdOf(body))).toStrictEqual([]);
  });

  test("every curated keyword accepts a minimal two-line fixture", () => {
    for (const keyword of KNOWN_DIAGRAM_KEYWORDS) {
      const issues = validateDiagramSource(`${keyword.toUpperCase()}\nX`);
      expect(issues.map(issue => issue.message)).toStrictEqual([]);
    }
  });
});

describe("markdown→absolute-line mapping contract", () => {
  test("failures attribute the exact FILE line including prologue offsets", () => {
    const doc = mdOf([
      "# Overview", // 1
      "", // 2
      FENCE, // 3
      "not-a-diagram", // 4
      CLOSE, // 5
    ]);
    const blocks = extractMermaidBlocks(doc);
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.startLine).toBe(3);
    const issues = validateDiagramSource(blocks[0]?.source ?? "");
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(1); // relative
    const absoluteLine = (blocks[0]?.startLine ?? Number.NaN) + (issues[0]?.line ?? 0);
    expect(absoluteLine).toBe(4); // absolute
  });

  test("unterminated fence surfaces the OPENING line as absolute reference", () => {
    const doc = mdOf(["intro", FENCE, "flowchart TD"]);
    const blocks = extractMermaidBlocks(doc);
    expect(blocks[0]?.endLine).toBeNull();
    expect(blocks[0]?.startLine).toBe(2);
  });
});

describe("Tier 3 — chaos inputs", () => {
  test("long synthetic graph remains green", () => {
    const lines = ["flowchart TD"];
    for (let index = 0; index < 400; index += 1) lines.push(`N${index} --> N${index + 1}`);
    expect(validateDiagramSource(mdOf(lines))).toStrictEqual([]);
  });

  test("mixed prose/backtick soup extracts exactly the two real blocks", () => {
    const soup = mdOf([
      "text with stray ``` triple ticks inline",
      "````",
      FENCE,
      "graph LR",
      "Q --> R",
      CLOSE,
      "closing outer above is four ticks; ignored",
      "````",
      "",
      FENCE,
      "sequenceDiagram",
      "A->>B: hi",
      CLOSE,
    ]);
    const blocks = extractMermaidBlocks(soup);
    expect(blocks).toHaveLength(2);
    expect(blocks[0]?.source.startsWith("graph LR")).toBe(true);
    expect(blocks[1]?.source.startsWith("sequenceDiagram")).toBe(true);
  });

  test("backslash-escaped fence marker is inert prose", () => {
    expect(extractMermaidBlocks("\\```mermaid\nhidden\n```")).toStrictEqual([]);
  });
});

describe("Tier 4 — security: hostile info-strings stay inert text", () => {
  test("semicolon-glued command suffix does NOT open a block (strict prefix rule)", () => {
    // Strict opener contract: an info string must be whitespace-separated.
    // A hostile glued suffix therefore yields ZERO extracted blocks — and
    // zero blocks mean the payload characters are never interpreted further.
    const doc = mdOf(["```mermaid; rm -rf ~", "flowchart LR", "safe --> output", CLOSE]);
    expect(extractMermaidBlocks(doc)).toStrictEqual([]);
  });

  test("whitespace-separated hostile-looking suffix opens but is stored as inert characters only", async () => {
    const doc = mdOf([`${FENCE} ; rm -rf ~`, "flowchart LR", "safe --> output", CLOSE]);
    const blocks = extractMermaidBlocks(doc);
    expect(blocks).toHaveLength(1);
    expect(blocks[0]?.infoString).toBe("; rm -rf ~");
    expect(validateDiagramSource(blocks[0]?.source ?? "")).toHaveLength(0); // body still validated as text

    const file = await scratchFile("hostile-info.md", doc);
    const result = await runValidator([file]);
    expect(result.code).toBe(0); // real process: inert text, diagram green, nothing executed
  });

  test("script never constructs shells — spawns git through strict array argv only", async () => {
    const text = await Bun.file(join(import.meta.dir, "validate-mermaid.ts")).text();
    expect(text).toContain('["git", "ls-files", "--", "docs"]');
    expect(text).not.toContain("execSync");
    expect(text).not.toContain("spawnSync");
    expect(text).not.toContain("shell:true");
    expect(text).not.toContain("shell: true");
  });
});

describe("CLI integration — explicit mode over real processes", () => {
  test("exit 0 for a good .mmd and a fenced .md passed together (mixed batch)", async () => {
    const goodMmd = await scratchFile("good-diagram.mmd", mdOf(["graph TB", "Root --> Leaf"]));
    const goodMd = await scratchFile("good-doc.md", mdOf(["# T", FENCE, "sequenceDiagram", "A->>B: ping", CLOSE]));
    const result = await runValidator([goodMmd, goodMd]);
    expect(result.code).toBe(0);
    expect(result.out).toContain("good-diagram.mmd — 1 mermaid diagram(s)");
    expect(result.out).toContain("good-doc.md — 1 mermaid diagram(s)");
    expect(result.out).toContain("2 file(s), 2 diagram(s)");
  });

  test("broken mermaid exits nonzero with file:line attribution", async () => {
    const dir = await openScratch();
    await scratchFile("broken.md", mdOf(["# T", "", FENCE, "badtype x", CLOSE]));
    const result = await runValidator([join(dir, "broken.md")]);
    expect(result.code).toBe(1);
    expect(result.err).toContain(`${join(dir, "broken.md")}:4`);
    expect(result.err).toContain('unknown diagram type "badtype"');
  });

  test("batch with one invalid member propagates failure while others still validate", async () => {
    const brokenMmd = await scratchFile("broken-diagram.mmd", "%% comment-only diagram");
    const goodMmd = await scratchFile("second-good.mmd", "gantt\nsection One");
    const result = await runValidator([brokenMmd, goodMmd]);
    expect(result.code).toBe(1);
    expect(result.out).toContain("second-good.mmd — 1 mermaid diagram(s)");
    expect(result.err).toContain("broken-diagram.mmd:1");
    expect(result.err).toContain("empty diagram");
  });

  test("dash-prefixed flag arguments are usage errors (exit 2)", async () => {
    const result = await runValidator(["--help"]);
    expect(result.code).toBe(2);
    expect(result.err).toContain("Usage:");
  });

  test("unsupported extensions fail loudly (named reason)", async () => {
    const txt = await scratchFile("notes.txt", FENCE);
    const result = await runValidator([txt]);
    expect(result.code).toBe(1);
    expect(result.err).toContain("unsupported file extension");
  });

  test("missing files count as validation failures with the path echoed", async () => {
    const dir = await openScratch();
    const missing = join(dir, "never-created.mmd");
    const result = await runValidator([missing]);
    expect(result.code).toBe(1);
    expect(result.err).toContain(missing);
    expect(result.err).toContain("unreadable or missing file");
  });
});

describe("CLI integration — default discovery over a scratch git repo", () => {
  test("discovers tracked docs and reports a green run", async () => {
    const base = await openScratch();
    const repoRoot = join(base, "discovery-repo");
    const docsDir = join(repoRoot, "docs");
    await mkdir(docsDir, { recursive: true });
    await writeFile(join(docsDir, "sample.mmd"), "flowchart TD\n  A --> B\n");
    await writeFile(join(docsDir, "notes.md"), `${FENCE}\nsequenceDiagram\n  A->>B: hi\n${CLOSE}\n`);
    Bun.spawnSync(["git", "init", "-q"], { cwd: repoRoot });
    Bun.spawnSync(["git", "add", "docs"], { cwd: repoRoot });
    const result = await runValidator([], repoRoot);
    expect(result.code).toBe(0);
    expect(result.err).toBe("");
    expect(result.out).toContain("docs/notes.md");
    expect(result.out).toContain("docs/sample.mmd");
  });

  test("non-git directory fails discovery loudly", async () => {
    const base = await openScratch();
    const plain = join(base, "not-a-repo");
    await mkdir(plain, { recursive: true });
    const result = await runValidator([], plain);
    expect(result.code).toBe(1);
    expect(result.err).toContain("default discovery failed");
  });
});
