#!/usr/bin/env python3
"""Regenerates Sources/LaxKit/Resources/emoji.json: Slack shortcode -> emoji.

Slack's built-in shortcodes come from iamcal/emoji-data (MIT licensed).
Usage: scripts/generate_emoji.py path/to/emoji.json
(download from https://raw.githubusercontent.com/iamcal/emoji-data/master/emoji.json)
"""
import json
import pathlib
import sys

source = json.loads(pathlib.Path(sys.argv[1]).read_text())
table = {}
for entry in source:
    emoji = "".join(chr(int(code, 16)) for code in entry["unified"].split("-"))
    for name in entry["short_names"]:
        table[name] = emoji

out = pathlib.Path(__file__).parent.parent / "Sources/LaxKit/Resources/emoji.json"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(table, ensure_ascii=False, sort_keys=True, separators=(",", ":")))
print(f"wrote {len(table)} shortcodes to {out}")
