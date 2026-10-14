#!/usr/bin/env python3
"""Summarize Claude Code session transcripts stored in the config volume (mounted read-only at /cfg).
Usage: python3 - [number_of_sessions] [max_lines]   (script read from stdin)
For every message: the role, and per content block whether it is text, a tool call (tool name and key input) or a tool result."""
import glob
import json
import os
import sys
import time

n = int(sys.argv[1]) if len(sys.argv) > 1 else 1
maxlines = int(sys.argv[2]) if len(sys.argv) > 2 else 80
LIM = 240


def short(v, lim=LIM):
    s = str(v).replace("\n", " \\n ")
    return s if len(s) <= lim else s[:lim] + "..."


files = glob.glob("/cfg/**/*.jsonl", recursive=True)
files.sort(key=os.path.getmtime, reverse=True)
if not files:
    print("NO_TRANSCRIPTS_FOUND under /cfg; top-level entries: %r" % (os.listdir("/cfg"),))
    sys.exit(0)

for path in files[:n]:
    print("=== transcript: %s  size=%d  modified=%s" % (
        path, os.path.getsize(path), time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(path)))))
    lines, other = [], 0
    for raw in open(path, encoding="utf-8", errors="replace"):
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except Exception:
            continue
        msg = rec.get("message") if isinstance(rec.get("message"), dict) else None
        if msg is None:
            other += 1
            continue
        role = msg.get("role") or rec.get("type")
        content = msg.get("content")
        extra = ""
        if role == "assistant":
            extra = " stop_reason=%s" % msg.get("stop_reason")
        if isinstance(content, str):
            lines.append("%s%s: text: %s" % (role, extra, short(content)))
            continue
        if not isinstance(content, list):
            lines.append("%s%s: (no content)" % (role, extra))
            continue
        kinds = []
        for b in content:
            if not isinstance(b, dict):
                continue
            t = b.get("type")
            if t == "text":
                kinds.append("text: " + short(b.get("text", "")))
            elif t == "tool_use":
                inp = b.get("input") or {}
                key = inp.get("file_path") or inp.get("command") or inp.get("path") or ""
                kinds.append("TOOL_CALL %s keys=%s %s" % (b.get("name"), sorted(inp.keys()), short(key, 100)))
            elif t == "tool_result":
                c = b.get("content")
                if isinstance(c, list):
                    c = " ".join(x.get("text", "") for x in c if isinstance(x, dict))
                kinds.append("tool_result is_error=%s: %s" % (b.get("is_error"), short(c, 140)))
            elif t == "thinking":
                kinds.append("(thinking)")
            else:
                kinds.append("(%s)" % t)
        lines.append("%s%s: %s" % (role, extra, " || ".join(kinds) if kinds else "(empty)"))
    print("messages: %d   other records: %d" % (len(lines), other))
    for ln in lines[:maxlines]:
        print("  " + ln)
    if len(lines) > maxlines:
        print("  ... %d more messages not shown" % (len(lines) - maxlines))