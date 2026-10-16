#!/usr/bin/env bun
/**
 * Mermaid validation script.
 *
 * Validates every Mermaid diagram in the given files using deterministic,
 * offline structural checks (NO network, NO headless renderer, NO npm deps —
 * minimal regex parsing + Bun.file).
 *
 * Usage:
 *   bun run scripts/validate-mermaid.ts <file...>   explicit mode (.md / .mmd)
 *   bun run scripts/validate-mermaid.ts             default discovery mode
 *   bun validate:mermaid                            (package.json alias)
 *
 * Explicit mode accepts one-or-more repo-relative-or-absolute paths as argv.
 * Paths resolve against the current working directory first; if that exact
 * location does not exist, against the repository root (so CI wrappers may
 * pass repo-relative paths from any cwd).
 *
 * Default discovery mode validates all git-tracked `.mmd` files under the
 * docs directory plus every tracked markdown file under it that contains a
 * raw triple-backtick mermaid fence (enumerated via array-argument
 * `git ls-files -- docs` — never shell-interpolated).
 *
 * DEFINED BEHAVIOR (all asserted in scripts/validate-mermaid.test.ts):
 *
 * 1. Fence extraction (markdown only). An opening fence is a line matching
 *    three backticks plus the word `mermaid` at column zero-to-three,
 *    optionally followed by an info-string suffix separated by whitespace
 *    (e.g. a title attribute). The suffix is captured and treated as INERT
 *    TEXT — parsed as characters only, never executed or expanded into any
 *    process/shell/context call. Closing fence = next bare three-backtick
 *    line (surrounding whitespace tolerated). An opened fence without a
 *    closer is an unterminated-fence issue attributed to the OPENING line.
 * 2. Diagrams must be non-empty once blank lines and percent-percent
 *    comment lines are stripped.
 * 3. The FIRST significant line must declare a KNOWN diagram keyword as its
 *    first whitespace-delimited token, compared CASE-INSENSITIVELY against
 *    the curated lowercase list in KNOWN_DIAGRAM_KEYWORDS (`flowchart`,
 *    `graph`, sequence/class/state(-v2)/er diagrams, journey, gantt, pie,
 *    mindmap, timeline, quadrantChart, gitGraph, the C4 family,
 *    requirementDiagram, the beta-suffixed family, kanban, radar where the
 *    beta suffix is optional-tolerant). Leading comment lines are skipped
 *    while locating the declaring line (Mermaid ignores such comments); a
 *    comments-only block fails rule 2 instead.
 * 4. Line-level sanity applies ONLY to flowchart/graph diagrams and ONLY to
 *    one unambiguous defect class: a line whose first characters are an
 *    arrow operator (`-->`, `==>`, `-.->`, `---`) with no source node token
 *    before them. Deliberately UNDER-flagging per design brief (false
 *    positives cost more than missed exotic syntax); everything else is
 *    left to rule 3.
 * 5. Exit codes: 0 = green (or default-discovery found zero diagrams — the
 *    CI wrapper owns empty-set semantics), 1 = any validation failure /
 *    unreadable input / enumeration failure, 2 = usage error (dash-prefixed
 *    flag argument; no flags exist by contract).
 *
 * Operator-facing messages are English-only strings written through
 * `process.stdout.write` / `process.stderr.write` — script-layer output is
 * exempt from the i18n requirement.
 */

import { existsSync } from "node:fs";
import { resolve } from "node:path";

/** Curated known diagram keywords (lowercase; matched case-insensitively). */
export const KNOWN_DIAGRAM_KEYWORDS: readonly string[] = [
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
] as const;

const KEYWORD_SET: ReadonlySet<string> = new Set(KNOWN_DIAGRAM_KEYWORDS);

/**
 * Case-insensitive keyword membership test (rule 3 exact matching rule:
 * first whitespace-delimited token of the first significant line,
 * lowercased, must EQUAL a listed entry — no prefix/suffix fuzzing).
 */
export function isKnownDiagramKeyword(token: string): boolean {
  return KEYWORD_SET.has(token.toLowerCase());
}

/** One extracted fenced block. `endLine === null` marks an unterminated fence. */
export interface MermaidBlock {
  /** 1-based line of the OPENING fence inside the markdown text. */
  readonly startLine: number;
  /** 1-based line of the closing fence, or null when unterminated. */
  readonly endLine: number | null;
  /** Raw info-string after the word `mermaid` on the opener, or null. Inert text only. */
  readonly infoString: string | null;
  /** Block body between the fences joined with `\n`. */
  readonly source: string;
}

/** Opening-fence matcher: exactly the word `mermaid`, optional info-string. */
const OPEN_FENCE = /^ {0,3}```mermaid\b(?: ([^\r\n]*))?$/;
/** Closing-fence matcher: a bare three-backtick line (whitespace tolerated). */
const CLOSE_FENCE = /^ {0,3}```\s*$/;

/**
 * Extract every fenced mermaid block in document order. Sequential scan: a
 * non-mermaid plain fence before/between blocks does not disturb pairing,
 * because tracking starts only at a recognized opener and ends at the first
 * following bare close (documented conservative parse — asserted Tier 3).
 * Handles LF and CRLF payloads identically (trailing CR removed by split).
 */
export function extractMermaidBlocks(content: string): MermaidBlock[] {
  const lines = content.split(/\r?\n/);
  const blocks: MermaidBlock[] = [];
  let openStart: number | null = null;
  let openInfo: string | null = null;
  const body: string[] = [];

  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index] ?? "";
    if (openStart === null) {
      const match = OPEN_FENCE.exec(line);
      if (match !== null) {
        openStart = index + 1;
        const info = (match[1] ?? "").trim();
        openInfo = info.length > 0 ? info : null;
        body.length = 0;
      }
      continue;
    }
    if (CLOSE_FENCE.test(line)) {
      blocks.push({ startLine: openStart, endLine: index + 1, infoString: openInfo, source: body.join("\n") });
      openStart = null;
      openInfo = null;
      continue;
    }
    body.push(line);
  }

  if (openStart !== null) {
    blocks.push({ startLine: openStart, endLine: null, infoString: openInfo, source: body.join("\n") });
  }
  return blocks;
}

/** A single problem found inside one diagram's source. `line` is 1-based WITHIN that source. */
export interface DiagramIssue {
  readonly line: number;
  readonly message: string;
}

interface SignificantLine {
  readonly index: number;
  readonly text: string;
}

/** First non-blank, non-comment line — the expected declaration line. */
function findFirstSignificantLine(lines: readonly string[]): SignificantLine | null {
  for (let index = 0; index < lines.length; index += 1) {
    const trimmed = (lines[index] ?? "").trim();
    if (trimmed.length === 0 || trimmed.startsWith("%%")) continue;
    return { index, text: trimmed };
  }
  return null;
}

/**
 * Arrow-operator starters that can NEVER legally begin an edge line without
 * a preceding node id. Kept intentionally minimal (rule 4 under-flagging).
 */
const BARE_ARROW_START = /^\s*(-->|==>|-\.-|---)/;

const GRAPH_FAMILY = new Set(["flowchart", "graph"]);

/**
 * Structural validation of ONE diagram's source (fence-agnostic — applied
 * wholesale to `.mmd` files too). Deterministic offline rules 2–4.
 *
 * Returns issues in document order. On an unknown declaration keyword the
 * root cause is reported alone (no secondary noise) — documented behavior.
 */
export function validateDiagramSource(source: string): DiagramIssue[] {
  const lines = source.split(/\r?\n/);
  const significant = findFirstSignificantLine(lines);

  // Rule 2 — emptiness beyond blank lines and comment lines.
  if (significant === null) {
    return [{ line: 1, message: "empty diagram: nothing but blank lines and/or comments" }];
  }

  // Rule 3 — known declaration keyword (case-insensitive whole-token equality).
  const token = significant.text.split(/\s+/)[0] ?? "";
  if (!isKnownDiagramKeyword(token)) {
    return [
      {
        line: significant.index + 1,
        message: `unknown diagram type "${token}" — first significant line must declare a known Mermaid keyword`,
      },
    ];
  }

  // Rule 4 — conservative edge sanity for the flowchart/graph family only.
  const issues: DiagramIssue[] = [];
  if (GRAPH_FAMILY.has(token.toLowerCase())) {
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index] ?? "";
      if (line.trim().startsWith("%%")) continue;
      const arrow = BARE_ARROW_START.exec(line);
      if (arrow !== null) {
        issues.push({
          line: index + 1,
          message: `malformed edge: line begins with arrow "${arrow[1]}" but carries no source node before it`,
        });
      }
    }
  }
  return issues;
}

/** Per-file aggregate consumed by both CLI modes. */
interface FileValidation {
  readonly path: string;
  readonly ok: boolean;
  readonly diagramCount: number;
  /** stderr-ready details formatted `<path>:<line>: <message>`. */
  readonly details: readonly string[];
}

/** Repository root (this script lives under `<root>/skills/<skill>/scripts/`). */
const REPO_ROOT = resolve(import.meta.dir, "../../..");

const RAW_FENCE_NEEDLE = "```mermaid";

async function readTextOrThrow(path: string): Promise<string> {
  const text = await Bun.file(path).text();
  if (text.slice(0, 4096).includes("\u0000")) throw new Error("binary content");
  return text;
}

/** cwd-first resolution with repository-root fallback (documented order). */
function resolveTarget(path: string): string {
  const fromCwd = resolve(process.cwd(), path);
  if (existsSync(fromCwd)) return fromCwd;
  return resolve(REPO_ROOT, path);
}

/** Validate one explicitly-passed path (explicit-mode semantics). */
async function validateExplicitFile(path: string): Promise<FileValidation> {
  let text: string;
  try {
    text = await readTextOrThrow(resolveTarget(path));
  } catch {
    return { path, ok: false, diagramCount: 0, details: [`${path}:1: unreadable or missing file`] };
  }

  if (path.endsWith(".mmd")) return finishWholeFile(path, validateDiagramSource(text));

  if (path.endsWith(".md")) {
    const blocks = extractMermaidBlocks(text);
    const details: string[] = [];
    let unclosed = false;
    for (const block of blocks) {
      if (block.endLine === null) {
        unclosed = true;
        details.push(`${path}:${block.startLine}: unterminated code fence — opened here, missing closing backticks`);
      }
      for (const issue of validateDiagramSource(block.source)) {
        details.push(`${path}:${block.startLine + issue.line}: ${issue.message}`);
      }
    }
    return {
      path,
      ok: !unclosed && details.length === 0,
      diagramCount: unclosed ? 0 : blocks.length,
      details,
    };
  }

  return {
    path,
    ok: false,
    diagramCount: 0,
    details: [`${path}:1: unsupported file extension (expected .md or .mmd)`],
  };
}

/** Bundle whole-file diagram issues into the per-file aggregate. */
function finishWholeFile(path: string, issues: readonly DiagramIssue[]): FileValidation {
  return {
    path,
    ok: issues.length === 0,
    diagramCount: 1,
    details: issues.map(issue => `${path}:${issue.line}: ${issue.message}`),
  };
}

/** Stable ascending UTF-16 ordering so runs stay reproducible across machines. */
function comparePaths(a: string, b: string): number {
  if (a === b) return 0;
  return a < b ? -1 : 1;
}

/**
 * Default-discovery target list: git-tracked `.mmd` anywhere under docs plus
 * tracked markdown under docs containing a raw fence, enumerated relative to
 * the current working directory (the invoking project's repo root). Enumerated
 * strictly through array argv (`git ls-files -- docs`) — zero shell
 * interpolation. Returns null when enumeration itself fails (loud exit 1
 * upstream), so a broken checkout can never masquerade as an all-green empty
 * set.
 */
async function discoverDefaultTargets(): Promise<string[] | null> {
  const cwd = process.cwd();
  const proc = Bun.spawn(["git", "ls-files", "--", "docs"], { cwd, stdout: "pipe", stderr: "pipe" });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const code = await proc.exited;
  if (code !== 0) {
    const reason = stderr.trim();
    const suffix = reason.length > 0 ? `: ${reason}` : "";
    process.stderr.write(`default discovery failed: git ls-files exited ${code}${suffix}\n`);
    return null;
  }

  const trackedPaths = stdout
    .split(/\r?\n/)
    .map(line => line.trim())
    .filter(tracked => tracked.length > 0);
  const mmdTargets = trackedPaths.filter(tracked => tracked.endsWith(".mmd"));
  const markdownCandidates = trackedPaths.filter(tracked => tracked.endsWith(".md"));

  // null ⇒ fence-less markdown (skip); "unreadable:<path>" ⇒ I/O failure.
  const fenceChecks = await Promise.all(
    markdownCandidates.map(async tracked => {
      try {
        const text = await readTextOrThrow(resolve(cwd, tracked));
        return text.includes(RAW_FENCE_NEEDLE) ? tracked : null;
      } catch {
        return `unreadable:${tracked}`;
      }
    })
  );
  const firstUnreadable = fenceChecks.find(entry => entry?.startsWith("unreadable:"));
  if (typeof firstUnreadable === "string") {
    process.stderr.write(
      `default discovery failed: tracked file not readable: ${firstUnreadable.slice("unreadable:".length)}\n`
    );
    return null;
  }

  const fencedMarkdown = fenceChecks.filter((entry): entry is string => entry !== null);
  return [...mmdTargets, ...fencedMarkdown].toSorted(comparePaths);
}

const USAGE = [
  "Usage: bun run scripts/validate-mermaid.ts [<file.md|.mmd> ...]",
  "",
  "With paths: validates each file (markdown = every fenced mermaid block;",
  ".mmd = whole file). Without paths: discovers and validates all tracked",
  "docs .mmd files plus docs markdown containing mermaid fences.",
  "Exit codes: 0 green or empty-set no-op, 1 invalid input, 2 usage error.",
  "",
].join("\n");

/** Aggregates per-file results after emitting live per-file lines. */
async function runAll(paths: readonly string[]): Promise<number> {
  let diagramTotal = 0;
  let failedFiles = 0;
  const allDetails: string[] = [];

  // Parallelized per file; results are positional so stdout ordering stays
  // deterministic regardless of completion order.
  const results = await Promise.all(paths.map(path => validateExplicitFile(path)));
  for (const result of results) {
    diagramTotal += result.diagramCount;
    if (result.ok) {
      process.stdout.write(`✅ ${result.path} — ${result.diagramCount} mermaid diagram(s)\n`);
      continue;
    }
    failedFiles += 1;
    allDetails.push(...result.details);
  }

  if (allDetails.length > 0) {
    process.stdout.write(
      `❌ Mermaid validation failed: ${failedFiles} failing file(s), ${paths.length - failedFiles} passing file(s), ${diagramTotal} clean diagram(s) scanned\n`
    );
    for (const detail of allDetails) process.stderr.write(`❌ ${detail}\n`);
    return 1;
  }

  process.stdout.write(`✅ Mermaid validation passed: ${paths.length} file(s), ${diagramTotal} diagram(s)\n`);
  return 0;
}

async function runExplicit(paths: readonly string[]): Promise<number> {
  if (paths.length === 0) {
    process.stderr.write("validation failed: explicit mode received no files\n");
    return 1;
  }
  return runAll(paths);
}

async function runDefaultDiscovery(): Promise<number> {
  const discovered = await discoverDefaultTargets();
  if (discovered === null) return 1;
  if (discovered.length === 0) {
    process.stdout.write("✅ No documentation files/diagrams discovered — passing no-op (empty set owned by caller)\n");
    return 0;
  }
  return runAll(discovered);
}

/** Thin orchestrator: mode selection → aggregation → numeric exit code. */
async function main(): Promise<number> {
  const args = process.argv.slice(2);
  if (args.length === 0) return runDefaultDiscovery();
  if (args.some(argument => argument.startsWith("-"))) {
    process.stderr.write(USAGE);
    return 2;
  }
  return runExplicit(args);
}

if (import.meta.main) {
  process.exit(await main());
}
