#!/usr/bin/env python3
"""Live renderer for craft-agent's stream-json run transcript.

Follows the NDJSON event stream the agent binary writes and prints a
compact, turn-organized view: tool calls, spawn waves, every subagent's
lifecycle, per-turn usage, and the final verdict. Stdlib only.
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
                    try:
                        outcome = render(rec, fold)
                    except BrokenPipeError:  # a closed log never kills the render
                        return
                    except Exception as exc:  # a bad record never kills the render
                        print(c(f"render skipped record: {exc}", RED), flush=True)
                        continue
                    if outcome == "done":
                        return
            elif STOP["flag"]:
                return  # the agent is gone and the file is drained
            else:
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
