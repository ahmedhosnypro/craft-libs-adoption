/**
 * Regression tests for syntax defects the offline validator historically
 * missed while the real Mermaid renderer (mmdc) rejected the diagram.
 *
 * Every fixture here was verified against the renderer FIRST (mmdc +
 * Chrome); each expectation below records that observed behavior:
 *   - flowchart/graph `[*]` terminal          → renderer parse error
 *   - timeline colon inside the period text   → renderer parse error
 *   - timeline colon-free period w/ colon-rich event text → renderer OK
 *   - sequence `A->>B:: text`                 → renderer OK (message text
 *     simply starts with a colon — pinned as ACCEPTED to prevent an
 *     over-eager future rule from false-flagging it)
 *
 * Run: bun test scripts/tests/validate-mermaid.defects.test.ts
 */

import { afterAll, describe, expect, test } from "bun:test";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { validateDiagramSource } from "../validate-mermaid";

const FENCE = "```mermaid";
const CLOSE = "```";

/** Join markdown lines LF-style (common committed shape). */
function mdOf(lines: readonly string[]): string {
  return lines.join("\n");
}

let scratchBase: string | null = null;

/** Lazily create one shared temp workspace; every caller gets its absolute directory. */
async function openScratch(): Promise<string> {
  scratchBase ??= await mkdtemp(join(tmpdir(), "validate-mermaid-defects-test-"));
  return scratchBase;
}

async function scratchFile(name: string, content: string): Promise<string> {
  const target = join(await openScratch(), name);
  await writeFile(target, content);
  return target;
}

afterAll(async () => {
  if (scratchBase !== null) await rm(scratchBase, { recursive: true, force: true });
});

/** Spawn helper targeting the real validator script (array argv only). */
function runValidator(args: readonly string[], cwd?: string): Promise<{ code: number; out: string; err: string }> {
  const proc = Bun.spawn([process.execPath, join(import.meta.dir, "..", "validate-mermaid.ts"), ...args], {
    cwd: cwd ?? join(import.meta.dir, "..", ".."),
    stdout: "pipe",
    stderr: "pipe",
  });
  const outPromise = new Response(proc.stdout).text();
  const errPromise = new Response(proc.stderr).text();
  return proc.exited.then(async code => ({ code, out: await outPromise, err: await errPromise }));
}

describe("flowchart/graph — state-only [*] terminal rejection", () => {
  test("[*] as an edge target in a flowchart is flagged at its own line", () => {
    const issues = validateDiagramSource(mdOf(["flowchart TD", "A --> B", 'Defer --> Report["Report in window comment"]', "Report --> [*]"]));
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(4);
    expect(issues[0]?.message).toContain('"[*]"');
    expect(issues[0]?.message).toContain("flowchart/graph");
  });

  test("[*] as a leading node in a flowchart is flagged", () => {
    const issues = validateDiagramSource(mdOf(["flowchart TD", "[*] --> A", "A --> B"]));
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(2);
  });

  test("every [*] occurrence in the graph family is flagged independently", () => {
    const issues = validateDiagramSource(mdOf(["graph LR", "Report --> [*]", "File --> [*]", "Refuse --> [*]"]));
    expect(issues.map(issue => issue.line)).toStrictEqual([2, 3, 4]);
  });

  test("a literal [*] inside a quoted label or pipe edge label is NOT a node", () => {
    expect(validateDiagramSource(mdOf(['flowchart TD', 'A["see [*] note"] --> B']))).toStrictEqual([]);
    expect(validateDiagramSource(mdOf(["flowchart TD", "A -->|pick [*]| B"]))).toStrictEqual([]);
  });

  test("stateDiagram-v2 keeps its legal [*] terminals (no false positives)", () => {
    expect(validateDiagramSource(mdOf(["stateDiagram-v2", "[*] --> Draft", "Draft --> Sent", "Sent --> [*]"]))).toStrictEqual(
      []
    );
  });

  test("non-graph families are untouched by the [*] rule", () => {
    expect(validateDiagramSource(mdOf(["sequenceDiagram", "A->>B: [*] discussed"]))).toStrictEqual([]);
    expect(validateDiagramSource(mdOf(["timeline", "section S", "Window 1 : [*] not a node here"]))).toStrictEqual([]);
  });
});

describe("timeline — colon-in-period rejection", () => {
  test("a clock time inside the period text is flagged at its own line", () => {
    // The original incident: `00:20 UTC scan : looks back to 17:20 UTC previous day`
    const issues = validateDiagramSource(
      mdOf(["timeline", "title Six-hour cadence, cron 20 0,6,12,18 * * *", "section Daily windows", "00:20 UTC scan : looks back to 17:20 UTC previous day"])
    );
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(4);
    expect(issues[0]?.message).toContain("colon inside the period text");
  });

  test("a bare period carrying a colon with no event is flagged", () => {
    const issues = validateDiagramSource(mdOf(["timeline", "section S", "00:20 scan"]));
    expect(issues).toHaveLength(1);
    expect(issues[0]?.line).toBe(3);
  });

  test("the fixed shape — colon-free period, colon-rich event — stays clean", () => {
    const issues = validateDiagramSource(
      mdOf([
        "timeline",
        "title Six-hour cadence, cron 20 0,6,12,18 * * *",
        "section Daily windows",
        "Window 1 : 00:20 UTC scan, looks back to 17:20 UTC previous day",
        "Window 2 : 06:20 UTC scan, looks back to 23:20 UTC",
      ])
    );
    expect(issues).toStrictEqual([]);
  });

  test("a colon attached to a non-first token without a spaced separator is accepted (renderer-verified)", () => {
    expect(validateDiagramSource(mdOf(["timeline", "section S", "Window 1: 00:20 UTC scan"]))).toStrictEqual([]);
  });

  test("title and section header lines are exempt even when they carry colons", () => {
    expect(validateDiagramSource(mdOf(["timeline", "title Windows: four a day", "section Daily windows: all of them", "Window 1 : 00:20 scan"]))).toStrictEqual(
      []
    );
  });

  test("a colon-free period-only statement stays clean", () => {
    expect(validateDiagramSource(mdOf(["timeline", "00 20 slot"])).length).toBe(0);
  });
});

describe("renderer-verified legal syntax stays ACCEPTED (guard against over-flagging)", () => {
  test("sequence double-colon message text renders fine and must not be flagged", () => {
    // mmdc renders `A->>B:: text` — the second colon is simply message text.
    expect(validateDiagramSource(mdOf(["sequenceDiagram", "participant A", "participant B", "A->>B: double colon text"]))).toStrictEqual(
      []
    );
    expect(validateDiagramSource(mdOf(["sequenceDiagram", "A->>B:: verbatim message"]))).toStrictEqual([]);
  });

  test("colons inside ordinary sequence message text stay accepted", () => {
    expect(validateDiagramSource(mdOf(["sequenceDiagram", "A->>B: window 17:20 to 00:20 UTC"]))).toStrictEqual([]);
  });

  test("the workflow doc's working diagrams all pass the strengthened validator", () => {
    expect(validateDiagramSource("sequenceDiagram\nCoord->>Coord: Split batch into per-PR prompts")).toStrictEqual([]);
    expect(
      validateDiagramSource("timeline\nsection Daily windows\nWindow 1 : 00:20 UTC scan, looks back to 17:20 UTC previous day")
    ).toStrictEqual([]);
    expect(validateDiagramSource('flowchart TD\nFile --> Report["File adoption-scan: <slug>"]')).toStrictEqual([]);
  });
});

describe("CLI integration — incident fixtures through the real process", () => {
  test("a doc mixing the two defect classes exits 1 with file:line attribution", async () => {
    const dir = await openScratch();
    const broken = await scratchFile(
      "broken-workflow.md",
      mdOf([
        "# Workflow",
        "",
        FENCE,
        "flowchart TD",
        '    Defer --> Report["Report in window comment"]',
        "    Report --> [*]",
        CLOSE,
        "",
        FENCE,
        "timeline",
        "    section Daily windows",
        "    00:20 UTC scan : looks back to 17:20 UTC previous day",
        CLOSE,
      ])
    );
    const result = await runValidator([broken]);
    expect(result.code).toBe(1);
    expect(result.err).toContain(`${broken}:6`);
    expect(result.err).toContain('"[*]"');
    expect(result.err).toContain(`${broken}:12`);
    expect(result.err).toContain("colon inside the period text");
    expect(result.out).toContain("1 failing file(s)");
  });

  test("the fixed doc passes clean end to end", async () => {
    const fixed = await scratchFile(
      "fixed-workflow.md",
      mdOf([
        "# Workflow",
        "",
        FENCE,
        "flowchart TD",
        '    Defer --> Report["Report in window comment"]',
        "    Unverified --> File",
        CLOSE,
        "",
        FENCE,
        "timeline",
        "    section Daily windows",
        "    Window 1 : 00:20 UTC scan, looks back to 17:20 UTC previous day",
        "    Window 2 : 06:20 UTC scan, looks back to 23:20 UTC",
        CLOSE,
      ])
    );
    const result = await runValidator([fixed]);
    expect(result.code).toBe(0);
    expect(result.err).toBe("");
    expect(result.out).toContain("2 diagram(s)");
  });

  test("existing defect class (bare arrow) still flags — no regression from the new rules", async () => {
    const file = await scratchFile("bare-arrow.mmd", "graph TD\nA --> B\n--> C\n");
    const result = await runValidator([file]);
    expect(result.code).toBe(1);
    expect(result.err).toContain("malformed edge");
    expect(result.err).toContain('"-->"');
  });

  test("default discovery over a scratch git repo still green with the new rules active", async () => {
    const base = await openScratch();
    const repoRoot = join(base, "defects-discovery-repo");
    const docsDir = join(repoRoot, "docs");
    await mkdir(docsDir, { recursive: true });
    await writeFile(join(docsDir, "diagram.mmd"), "flowchart TD\n  A --> B\n");
    Bun.spawnSync(["git", "init", "-q"], { cwd: repoRoot });
    Bun.spawnSync(["git", "add", "docs"], { cwd: repoRoot });
    const result = await runValidator([], repoRoot);
    expect(result.code).toBe(0);
    expect(result.err).toBe("");
  });
});
