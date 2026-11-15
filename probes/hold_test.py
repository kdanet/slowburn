"""Test: can a PreToolUse hook pause an agent until an outside decision, then let it continue?

Only sessions that opted in are ever held, so the rest of your sessions keep working:
    submit   (UserPromptSubmit) a prompt starting with "#hold-test" registers its session.
    pretool  (PreToolUse)       a registered session waits while logs/HOLD exists (up to MAX_WAIT),
                                then is allowed through. Progress goes to logs/hold_test.jsonl and
                                the live queue to logs/holding.json.
Always exits 0 with no output: the tool call is allowed once the hold ends.
"""

import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
LOGS = os.path.join(HERE, "logs")
SESSIONS = os.path.join(LOGS, "hold_sessions.txt")
FLAG = os.path.join(LOGS, "HOLD")
QUEUE = os.path.join(LOGS, "holding.json")
MAX_WAIT = 1800


def log(**kw):
    kw["ts"] = time.strftime("%H:%M:%S")
    with open(os.path.join(LOGS, "hold_test.jsonl"), "a") as fh:
        fh.write(json.dumps(kw, ensure_ascii=False) + "\n")


def queue(update):
    try:
        q = json.load(open(QUEUE))
    except Exception:
        q = {}
    update(q)
    tmp = QUEUE + ".tmp"
    json.dump(q, open(tmp, "w"), ensure_ascii=False, indent=1)
    os.replace(tmp, QUEUE)


def main():
    os.makedirs(LOGS, exist_ok=True)
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    payload = json.loads(sys.stdin.read() or "{}")
    session = str(payload.get("session_id", ""))
    registered = set(open(SESSIONS).read().split()) if os.path.exists(SESSIONS) else set()

    if mode == "submit":
        if (payload.get("prompt") or "").lstrip().startswith("#hold-test") and session not in registered:
            with open(SESSIONS, "a") as fh:
                fh.write(session + "\n")
            log(event="registered", session=session[:8])
        return

    if mode != "pretool" or session not in registered or not os.path.exists(FLAG):
        return
    key = f"{session[:8]}:{payload.get('tool_use_id', '')[-6:]}"
    tool = payload.get("tool_name")
    start = time.time()

    # If the host gives up on the hook, record when and how.
    import signal

    def on_signal(signum, _frame):
        log(event="killed", key=key, tool=tool, signal=signum, waited=round(time.time() - start, 1))
        queue(lambda q: q.pop(key, None))
        os._exit(0)

    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, on_signal)
    log(event="hold", key=key, tool=tool, agent=payload.get("agent_id"))
    queue(lambda q: q.__setitem__(key, {"tool": tool, "since": time.strftime("%H:%M:%S"), "pid": os.getpid()}))
    try:
        while os.path.exists(FLAG) and time.time() - start < MAX_WAIT:
            time.sleep(0.5)
    finally:
        waited = round(time.time() - start, 1)
        log(event="release", key=key, tool=tool, waited=waited, reason="flag removed" if not os.path.exists(FLAG) else "max wait")
        queue(lambda q: q.pop(key, None))


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # a probe must never break the host
        try:
            log(event="error", error=repr(e))
        except Exception:
            pass
    sys.exit(0)
