"""Stage-0 probe: log what Claude Code / Codex hand to hooks and the status line.

Usage (from a hook or statusLine command):
    python3 -I hook_logger.py <client> <event>

Never blocks anything: always exits 0 and prints nothing for hooks.
In `statusline` mode it prints a short marker so the status line stays visible.
Long strings are truncated (prompts, tool output) and env var VALUES are never
logged — only names of client-related variables, to learn what the host passes.
"""

import json
import os
import sys
import time

LOG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs")
MAX_STR = 240
ENV_PREFIXES = ("CLAUDE", "CODEX", "ANTHROPIC", "OPENAI")


def shrink(value):
    if isinstance(value, str):
        return value if len(value) <= MAX_STR else value[:MAX_STR] + f"…(+{len(value) - MAX_STR})"
    if isinstance(value, dict):
        return {k: shrink(v) for k, v in value.items()}
    if isinstance(value, list):
        return [shrink(v) for v in value[:20]]
    return value


def main():
    client = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    event = sys.argv[2] if len(sys.argv) > 2 else "unknown"
    raw = sys.stdin.read()
    try:
        payload = shrink(json.loads(raw)) if raw.strip() else None
    except ValueError:
        payload = {"_unparsed": shrink(raw)}
    record = {
        "ts": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "client": client,
        "event": event,
        "ppid": os.getppid(),
        "env_names": sorted(k for k in os.environ if k.startswith(ENV_PREFIXES)),
        "payload": payload,
    }
    os.makedirs(LOG_DIR, exist_ok=True)
    with open(os.path.join(LOG_DIR, f"{client}.jsonl"), "a") as fh:
        fh.write(json.dumps(record, ensure_ascii=False) + "\n")
    if event == "statusline":
        print("◔ claudergy probe")


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a probe must never break the host
        pass
    sys.exit(0)
