"""Add or remove the stage-0 logging hooks.

    python3 -I install_probes.py install
    python3 -I install_probes.py uninstall

Only entries whose command mentions MARKER are touched; existing hooks
(e.g. Orca's Codex hooks) keep their positions, so their trust state stays valid.
A timestamped backup of each config is written next to this script first.
"""

import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
LOGGER = os.path.join(HERE, "hook_logger.py")
MARKER = "Claudergy/probes/hook_logger.py"
PY = "/usr/bin/python3"

CLAUDE_SETTINGS = os.path.expanduser("~/.claude/settings.json")
CODEX_HOOKS = os.path.expanduser("~/.codex/hooks.json")

CLAUDE_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "SubagentStop"]
CODEX_EVENTS = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Stop"]


def cmd(client, event):
    return f"{PY} -I '{LOGGER}' {client} {event}"


def load(path):
    with open(path) as fh:
        return json.load(fh)


def save_atomic(path, data):
    tmp = path + ".claudergy-tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)


def backup(path):
    os.makedirs(os.path.join(HERE, "backups"), exist_ok=True)
    dst = os.path.join(HERE, "backups", f"{os.path.basename(path)}.{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.copy2(path, dst)
    return dst


def strip_ours(hooks):
    for event in list(hooks):
        groups = [g for g in hooks[event] if not any(MARKER in h.get("command", "") for h in g.get("hooks", []))]
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]


def apply(path, client, events, install, statusline=False):
    data = load(path) if os.path.exists(path) else {}
    print(f"{client}: backup -> {backup(path)}" if os.path.exists(path) else f"{client}: no existing file")
    hooks = data.setdefault("hooks", {})
    strip_ours(hooks)
    if install:
        for event in events:
            hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": cmd(client, event), "timeout": 5}]})
    if not hooks:
        data.pop("hooks", None)
    if statusline:
        current = data.get("statusLine")
        ours = current and MARKER in current.get("command", "")
        if install and not current:
            data["statusLine"] = {"type": "command", "command": cmd(client, "statusline")}
        elif not install and ours:
            del data["statusLine"]
        elif install and current and not ours:
            print(f"{client}: existing statusLine left untouched")
    save_atomic(path, data)
    print(f"{client}: {'installed' if install else 'removed'} probe hooks in {path}")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode not in ("install", "uninstall"):
        sys.exit(__doc__)
    install = mode == "install"
    apply(CLAUDE_SETTINGS, "claude", CLAUDE_EVENTS, install, statusline=True)
    apply(CODEX_HOOKS, "codex", CODEX_EVENTS, install)


if __name__ == "__main__":
    main()
