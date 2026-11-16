#!/usr/bin/env python3
"""Release notes for one version, from release-notes/<version>.en.md and .ru.md.

  scripts/notes.py appcast <version>    <description> elements for the appcast item (English by default, Russian by xml:lang)
  scripts/notes.py github <version>     Markdown body for the GitHub release

A notes file is a short list: one "- " line per change, in plain words for people who use the app.
"""
from __future__ import annotations

import html
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


def items(version: str, lang: str) -> list[str]:
    path = ROOT / "release-notes" / f"{version}.{lang}.md"
    if not path.exists():
        sys.exit(f"missing {path.relative_to(ROOT)}")
    lines = [l.strip() for l in path.read_text().splitlines() if l.strip()]
    out = [l[2:].strip() if l.startswith("- ") else l for l in lines]
    if not out:
        sys.exit(f"{path.relative_to(ROOT)} is empty")
    return out


def appcast(version: str) -> str:
    def block(lang: str | None) -> str:
        body = "<ul>" + "".join(f"<li>{html.escape(i, quote=False)}</li>" for i in items(version, lang or "en")) + "</ul>"
        attr = f' xml:lang="{lang}"' if lang else ""
        return f"      <description{attr}><![CDATA[{body}]]></description>\n"
    return block(None) + block("ru")


def github(version: str) -> str:
    en = "\n".join(f"- {i}" for i in items(version, "en"))
    ru = "\n".join(f"- {i}" for i in items(version, "ru"))
    return f"{en}\n\n**По-русски**\n\n{ru}\n"


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("appcast", "github"):
        sys.exit(__doc__)
    sys.stdout.write({"appcast": appcast, "github": github}[sys.argv[1]](sys.argv[2]))
