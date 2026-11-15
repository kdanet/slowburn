"""Test hook: how does a host show a held prompt and a warning?

Reacts only to prompts that start with a marker; everything else passes untouched.
    #brake-test ...  -> {"decision": "block", "reason": ...}
    #warn-test ...   -> {"systemMessage": ...}  (prompt goes through)
Each call is logged to logs/brake_test.jsonl. Always exits 0.
"""

import json
import os
import sys
import time

LOG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "logs", "brake_test.jsonl")


def main():
    client = sys.argv[1] if len(sys.argv) > 1 else "unknown"
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except ValueError:
        payload = {}
    prompt = (payload.get("prompt") or "").lstrip()
    out = None
    if prompt.startswith("#brake-test"):
        out = {"decision": "block",
               "reason": "◔ Блоб придержал запрос (тест): заряд вернётся к 21:40. "
                         "Очень надо — отправь снова с ++ в начале."}
    elif prompt.startswith("#warn-test"):
        out = {"systemMessage": "◔ Пропускаю (тест), но это уже запас: осталось около 2 часов."}
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a") as fh:
        fh.write(json.dumps({"ts": time.strftime("%H:%M:%S"), "client": client,
                             "event": payload.get("hook_event_name"), "session": str(payload.get("session_id"))[:8],
                             "prompt_head": prompt[:40], "answer": out}, ensure_ascii=False) + "\n")
    if out:
        print(json.dumps(out, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
    sys.exit(0)
