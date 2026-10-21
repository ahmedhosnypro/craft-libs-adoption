#!/usr/bin/env python3
"""Live renderer for craft-agent's stream-json run transcript.

Follows the NDJSON event stream the agent binary writes and prints a
compact, turn-organized view: tool calls, spawn waves, every subagent's
lifecycle, per-turn usage, and the final verdict. Stdlib only.

A workflow run's stream carries only its framing events, so workflow
mode follows the run's journal as well for the per-step detail.
"""

import json
import os
import signal
import sys
import time

MAX_CARRY = 1_048_576

DIM = "\033[2m"
BOLD = "\033[1m"
GREEN = "\033[32m"
RED = "\033[31m"
CYAN = "\033[36m"
YELLOW = "\033[33m"
RESET = "\033[0m"

BAR = 68
OK_ICON, FAIL_ICON, SPAWN_ICON, TURN_MARK = "✓", "✗", "▲", "▸"


def c(text, code):
    return f"{code}{text}{RESET}"


def human(n):
    return f"{n:,}" if isinstance(n, int) else str(n)


def first_line(text, limit=96):
    line = text.strip().splitlines()[0] if text.strip() else ""
    return line[: limit - 1] + "…" if len(line) > limit else line


def summarize_call(rec):
    name = rec.get("name", "?")
    raw = rec.get("arguments") or ""
    try:
        args = json.loads(raw) if isinstance(raw, str) else (raw or {})
    except ValueError:
        args = {}
    if isinstance(args, dict):
        if name in ("spawn_agents", "spawn_agent"):
            items = args.get("items") or []
            head = args.get("agent", "?")
            if len(items) > 1:
                head += f" ×{len(items)}"
            if args.get("maxTurns"):
                head += f" · maxTurns {args['maxTurns']}"
            if items:
                head += f" · {first_line(str(items[0]), 44)}"
            return head
        if name == "bash":
            return first_line(str(args.get("command", "")), BAR)
        if name in ("read_file", "write_file"):
            return first_line(str(args.get("path", "")), BAR)
        if name in ("glob", "grep"):
            return first_line(str(args.get("pattern", "")), BAR)
        if name == "gh":
            return first_line(" ".join(args.get("args", [])), BAR)
    return first_line(str(raw), BAR)


def render(rec, fold):
    kind = rec.get("type")
    if kind == "turn_started":
        flush_fold(fold)
        n = rec.get("turn", "?")
        print(f"{c(f'── turn {n} ', YELLOW + BOLD)}{c('─' * max(4, BAR - len(str(n)) - 9), DIM)}", flush=True)
    elif kind == "tool_call":
        name = rec.get("name", "?")
        print(f"  {c(TURN_MARK, CYAN)} {c(f'{name:<11}', BOLD)} {first_line(summarize_call(rec))}", flush=True)
    elif kind == "tool_result":
        content = rec.get("content", "")
        if isinstance(content, (list, dict)):
            content = json.dumps(content)
        text = str(content)
        if text.strip():
            mark = c("↳ error", RED) if rec.get("is_error") else c("↳", DIM)
            print(f"  {mark} {first_line(text, 92)}", flush=True)
    elif kind == "subagent_started":
        extras = [f"maxTurns {rec['maxTurns']}"] if rec.get("maxTurns") else []
        if rec.get("timeout_secs"):
            extras.append(f"{rec['timeout_secs']}s cap")
        print(
            f"  {c(SPAWN_ICON, CYAN)} {c(rec.get('id', '?'), BOLD)} {rec.get('profile', '?')}"
            f" {c('· ' + ' · '.join(extras), DIM)}",
            flush=True,
        )
    elif kind == "subagent_finished":
        reason = rec.get("stop_reason", "?")
        icon = c(OK_ICON, GREEN) if reason == "completed" else c(FAIL_ICON, RED)
        usage = rec.get("usage") or {}
        total = f"in {human(usage.get('input_tokens', 0))} · out {human(usage.get('output_tokens', 0))}"
        print(
            f"  {icon} {c(rec.get('id', '?'), BOLD)} {reason} · {rec.get('turns', '?')} turns"
            f" {c('· ' + total, DIM)}",
            flush=True,
        )
    elif kind == "tool_progress":
        key = (rec.get("turn"), rec.get("name"))
        chunk = fold.setdefault(key, [0, 0])
        chunk[0] += 1
        chunk[1] += len(rec.get("text", ""))
    elif kind == "turn_usage":
        u = rec.get("usage") or {}
        print(
            f"  {c('⊢', DIM)} turn {rec.get('turn', '?')}: in {human(u.get('input_tokens', 0))}"
            f" · out {human(u.get('output_tokens', 0))}"
            f" · reasoning {human(u.get('reasoning_tokens', 0))}"
            f" · cache {human(u.get('cache_read_tokens', 0))}",
            flush=True,
        )
    elif kind == "workflow_started":
        flush_fold(fold)
        print(
            f"{c('■', BOLD)} workflow {rec.get('name', '?')} started"
            f" · run {rec.get('run_id', '?')}",
            flush=True,
        )
    elif kind == "workflow_finished":
        # The report is the terminal line's payload; a report is the
        # only signal that the run settled rather than erroring out.
        flush_fold(fold)
        report = rec.get("report") or {}
        steps = report.get("steps") or []
        skipped = sum(1 for s in steps if (s.get("status") or {}).get("kind") == "skipped")
        usage = report.get("total_usage") or {}
        print(
            f"\n{c('■', BOLD)} workflow {report.get('name', '?')}"
            f" conclusion={(report.get('conclusion') or {}).get('kind', '?')}"
            f" · failed_step {report.get('failed_step') or '-'}"
            f" · {len(steps)} steps · {skipped} skipped"
            f" · {human(usage.get('turns', 0))} turns"
            f" · in {human(usage.get('input_tokens', 0))} · out {human(usage.get('output_tokens', 0))}"
            f" · reasoning {human(usage.get('reasoning_tokens', 0))}",
            flush=True,
        )
        return "done"
    elif kind == "run_finished":
        flush_fold(fold)
        u = rec.get("usage") or {}
        print(
            f"\n{c('■', BOLD)} conclusion={rec.get('conclusion', rec.get('category', '?'))}"
            f" · {rec.get('turns', '?')} turns"
            f" · in {human(u.get('input_tokens', 0))} · out {human(u.get('output_tokens', 0))}"
            f" · reasoning {human(u.get('reasoning_tokens', 0))}"
            f" · cache {human(u.get('cache_read_tokens', 0))}",
            flush=True,
        )
        return "done"
    return None


def flush_fold(fold):
    for (turn, name), (events, chars) in sorted(fold.items(), key=lambda kv: (kv[0][0] or 0, kv[0][1] or "")):
        print(f"  {c('↳', DIM)} {name} output: {events} chunks · {human(chars)} chars", flush=True)
    fold.clear()


def render_journal(rec):
    kind = rec.get("type")
    if kind == "run_started":
        limits = rec.get("limits") or {}
        caps = (f"{limits.get('max_steps', '?')} steps · {limits.get('max_total_turns', '?')} turns"
                f" · {limits.get('max_total_tokens', '?')} tokens")
        print(
            f"{c('■', BOLD)} workflow {rec.get('name', '?')} run {rec.get('run_id', '?')}"
            f" {c('· ' + caps, DIM)}",
            flush=True,
        )
    elif kind == "step_started":
        step = rec.get("id", "?")
        print(f"{c(f'── step {step} ', YELLOW + BOLD)}{c('─' * max(4, BAR - len(str(step)) - 10), DIM)}", flush=True)
    elif kind == "step_retried":
        print(f"  {c('↻', YELLOW)} {c(rec.get('id', '?'), BOLD)} retry attempt {rec.get('attempt', '?')}", flush=True)
    elif kind == "feedback_retried":
        issues = rec.get("issues") or []
        head = f" {c('· ' + first_line(issues[0], BAR), DIM)}" if issues else ""
        print(
            f"  {c('↻', YELLOW)} {c(rec.get('id', '?'), BOLD)} requeued by {rec.get('judge', '?')}"
            f" · feedback {rec.get('attempt', '?')} · {len(issues)} issue(s){head}",
            flush=True,
        )
    elif kind == "step_finished":
        conclusion = rec.get("conclusion") or "?"
        icon = c(OK_ICON, GREEN) if conclusion == "success" else c(FAIL_ICON, RED)
        usage = rec.get("usage") or {}
        print(
            f"  {icon} {c(rec.get('id', '?'), BOLD)} {conclusion} · {human(usage.get('turns', 0))} turns"
            f" {c('· in ' + human(usage.get('input_tokens', 0)) + ' · out ' + human(usage.get('output_tokens', 0)), DIM)}",
            flush=True,
        )
        preview = str(rec.get("final_message") or "")
        if preview.strip():
            print(f"  {c('↳', DIM)} {first_line(preview, 92)}", flush=True)
    elif kind == "step_skipped":
        reason = rec.get("reason") or {}
        detail = reason.get("kind") or "?"
        if reason.get("dep"):
            detail += f" <- {reason['dep']}"
        print(f"  {c('⊘', YELLOW)} {c(rec.get('id', '?'), BOLD)} skipped · {detail}", flush=True)
    elif kind == "run_finished":
        conclusion = rec.get("conclusion") or {}
        usage = rec.get("total_usage") or {}
        print(
            f"\n{c('■', BOLD)} conclusion={conclusion.get('kind', '?')}"
            f" · failed_step {rec.get('failed_step') or '-'}"
            f" · {human(usage.get('turns', 0))} turns"
            f" · in {human(usage.get('input_tokens', 0))} · out {human(usage.get('output_tokens', 0))}"
            f" · reasoning {human(usage.get('reasoning_tokens', 0))}",
            flush=True,
        )


def render_session_message(rec, step):
    """One model-visible message from a step's session transcript.

    The workflow stream carries no per-turn detail, so these lines are
    the liveness of a running step: its prompts, tool calls, and the
    first line of each tool result.
    """
    tag = c(f"[{step}]", DIM)
    role = rec.get("role")
    if role == "assistant":
        for call in rec.get("tool_calls") or []:
            name = call.get("name", "?")
            args = str(call.get("arguments") or "")
            print(f"  {c(TURN_MARK, CYAN)} {tag} {c(f'{name:<11}', BOLD)} {first_line(args, BAR)}", flush=True)
        text = str(rec.get("text") or "")
        if text.strip():
            print(f"  {c('·', DIM)} {tag} {first_line(text, 92)}", flush=True)
    elif role == "user":
        text = str(rec.get("text") or "")
        if "## Judge feedback" in text:
            print(f"  {c('↻', YELLOW)} {tag} re-prompted with judge feedback", flush=True)
        else:
            print(f"  {c('·', DIM)} {tag} prompt: {first_line(text, 88)}", flush=True)
    elif role == "tool":
        content = str(rec.get("content") or "")
        mark = c("↳ error", RED) if rec.get("is_error") else c("↳", DIM)
        if content.strip():
            print(f"  {mark} {tag} {first_line(content, 92)}", flush=True)


class SessionTail:
    """Follows the run's per-step session transcripts — one
    `sessions/<step-id>.jsonl`, one ChatMessage per line, appended as
    the step's run works — rendering each message as it lands."""

    def __init__(self, root):
        self.root = root
        self.handles = {}

    def drain(self):
        try:
            names = sorted(
                name for name in os.listdir(self.root) if name.endswith(".jsonl")
            )
        except OSError:
            return False
        rendered = False
        for name in names:
            handle = self.handles.get(name)
            if handle is None:
                try:
                    handle = open(os.path.join(self.root, name), "rb")
                except OSError:
                    continue
                self.handles[name] = handle
            chunk = handle.read()
            if not chunk:
                continue
            data = chunk.decode("utf-8", "replace")
            for line in data.split("\n"):
                if not line.strip():
                    continue
                rec = parse_record(line)
                if rec is None:
                    DROPS["count"] += 1  # unparsable JSON — drop, never stall
                    continue
                step = name[: -len(".jsonl")]
                try:
                    render_session_message(rec, step)
                    rendered = True
                except Exception as exc:  # a bad record never kills the render
                    print(c(f"render skipped session record: {exc}", RED), flush=True)
        return rendered

    def settle(self, budget_seconds=5):
        deadline = time.monotonic() + budget_seconds
        while time.monotonic() < deadline:
            self.drain()
            time.sleep(0.2)


def journal_path(run_id):
    root = os.environ.get("CRAFT_AGENT_JOURNAL_DIR") or os.path.join(
        os.environ.get("GITHUB_WORKSPACE") or os.getcwd(), ".craft-agent", "workflows"
    )
    return os.path.join(root, run_id, "journal.jsonl")


class JournalTail:
    """Follows one workflow journal, rendering each event as it lands."""

    def __init__(self, path):
        self.path = path
        self.handle = None
        self.inode = None
        self.carry = ""
        self.finished = False

    def _open(self):
        try:
            stat = os.stat(self.path)
        except OSError:
            return False
        if self.handle is None or (stat.st_ino, stat.st_dev) != self.inode:
            try:
                self.handle = open(self.path, "rb")
            except OSError:
                return False
            self.inode = (stat.st_ino, stat.st_dev)
            self.carry = ""
        return True

    def drain(self):
        if not self._open():
            return
        chunk = self.handle.read()
        if not chunk:
            return
        data = self.carry + chunk.decode("utf-8", "replace")
        lines = data.split("\n")
        self.carry = lines.pop()  # trailing fragment — carried, healing torn writes
        for line in lines:
            if not line.strip():
                continue
            rec = parse_record(line)
            if rec is None:
                DROPS["count"] += 1  # unparsable JSON — drop, never stall
                continue
            try:
                render_journal(rec)
                if rec.get("type") == "run_finished":
                    self.finished = True
            except Exception as exc:  # a bad journal record never kills the render
                print(c(f"render skipped journal record: {exc}", RED), flush=True)

    def settle(self, budget_seconds=15):
        """Drains until the journal's terminal event lands, bounded.

        The wrapper's SIGTERM asks the render to finish, which here means
        flushing the journal first, so the stop flag does not cut this
        short. A real run journals its terminal event before the stream's
        last line, so this is a short catch-up; the deadline is the bound
        when no journal ever lands (a CLI failure after the start event).
        """
        deadline = time.monotonic() + budget_seconds
        while not self.finished:
            self.drain()
            if self.finished or time.monotonic() > deadline:
                return
            time.sleep(0.1)


def parse_record(candidate):
    try:
        return json.loads(candidate)
    except ValueError:
        return None


STOP = {"flag": False}
DROPS = {"count": 0}


def _request_stop(signum, frame):
    STOP["flag"] = True


def follow(path):
    fold = {}
    handle = None
    inode = None
    carry = ""
    journal = None
    sessions = None
    last_signal = time.monotonic()
    print(c("renderer attached — following " + path, DIM), flush=True)
    try:
        while True:
            try:
                stat = os.stat(path)
            except FileNotFoundError:
                if STOP["flag"]:
                    return
                time.sleep(0.1)
                continue
            if handle is None or (stat.st_ino, stat.st_dev) != inode:
                handle = open(path, "rb")
                inode = (stat.st_ino, stat.st_dev)
                carry = ""
            chunk = handle.read()
            # Journal and session lines land while the run works, whether
            # or not the framing stream has a new chunk this iteration.
            if journal is not None and journal.drain():
                last_signal = time.monotonic()
            if sessions is not None and sessions.drain():
                last_signal = time.monotonic()
            if chunk:
                data = carry + chunk.decode("utf-8", "replace")
                lines = data.split("\n")
                carry = lines.pop()  # trailing fragment — carried, healing torn writes
                for line in lines:
                    if not line.strip():
                        continue
                    rec = parse_record(line)
                    if rec is None:
                        DROPS["count"] += 1  # unbondable JSON — drop, never stall
                        continue
                    # The workflow framing event names the run whose journal
                    # carries the per-step detail this stream omits.
                    if journal is None and rec.get("type") == "workflow_started":
                        journal = JournalTail(journal_path(rec.get("run_id", "")))
                        sessions = SessionTail(os.path.join(os.path.dirname(journal.path), "sessions"))
                        print(c("renderer attached — following " + journal.path, DIM), flush=True)
                        print(c("renderer attached — following sessions", DIM), flush=True)
                    try:
                        outcome = render(rec, fold)
                    except BrokenPipeError:  # a closed log never kills the render
                        return
                    except Exception as exc:  # a bad record never kills the render
                        print(c(f"render skipped record: {exc}", RED), flush=True)
                        continue
                    if outcome == "done":
                        if journal is not None:
                            journal.settle()
                        if sessions is not None:
                            sessions.settle()
                        return
            elif STOP["flag"]:
                return  # the agent is gone and the file is drained
            else:
                # Silence is expected mid-step, so say so periodically: a
                # quiet workflow run is alive, and this is the proof.
                if journal is not None and time.monotonic() - last_signal > 90:
                    waited = int(time.monotonic() - last_signal)
                    print(
                        f"  {c('…', DIM)} workflow still running — no new journal or session"
                        f" lines for {waited}s",
                        flush=True,
                    )
                    last_signal = time.monotonic()
                for _ in range(4):
                    if STOP["flag"]:
                        break
                    time.sleep(0.1)
    finally:
        if DROPS["count"]:
            print(c(f"renderer dropped {DROPS['count']} unparsable stream lines", YELLOW), flush=True)


def main():
    signal.signal(signal.SIGTERM, _request_stop)
    if len(sys.argv) < 2:
        print("usage: stream-render.py <stream.jsonl>", file=sys.stderr)
        return 2
    try:
        follow(sys.argv[1])
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        try:
            os.dup2(os.open(os.devnull, os.O_WRONLY), sys.stdout.fileno())
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
