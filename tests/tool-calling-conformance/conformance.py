#!/usr/bin/env python3
"""Tool-calling conformance test for the Anthropic Messages endpoint.
Runs inside the engine container (Python standard library only).
Environment: KEY (required), BASE, REPEAT, MODEL_ID, REQ_TIMEOUT.
Gate: structure checks must pass on every run; semantic checks (right tool, right
arguments) must pass on at least 80% of runs."""
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("BASE", "http://127.0.0.1:8888")
KEY = os.environ["KEY"]
REPEAT = int(os.environ.get("REPEAT", "2"))
MODEL = os.environ.get("MODEL_ID", "default")
TIMEOUT = int(os.environ.get("REQ_TIMEOUT", "900"))


def tool(name, desc, props, required):
    return {"name": name, "description": desc,
            "input_schema": {"type": "object", "properties": props, "required": required}}


S = {"type": "string"}
TOOLS = [
    tool("Bash", "Run a shell command and return its output.",
         {"command": {"type": "string", "description": "The command to run"}, "description": S}, ["command"]),
    tool("Read", "Read a file from the filesystem.",
         {"file_path": S, "offset": {"type": "integer"}, "limit": {"type": "integer"}}, ["file_path"]),
    tool("Edit", "Replace text in a file.",
         {"file_path": S, "old_string": S, "new_string": S, "replace_all": {"type": "boolean"}},
         ["file_path", "old_string", "new_string"]),
    tool("Write", "Write a file, replacing any existing content.",
         {"file_path": S, "content": S}, ["file_path", "content"]),
    tool("Glob", "Find files by glob pattern.", {"pattern": S, "path": S}, ["pattern"]),
]
NAMES = {t["name"] for t in TOOLS}
SYSTEM = ("You are a coding assistant working in a project directory. Use the provided tools to inspect "
          "and change files and to run commands. Call a tool when you need information you do not have; "
          "otherwise answer directly.")


def call(path, body, stream):
    data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method="POST", headers={
        "content-type": "application/json", "anthropic-version": "2023-06-01",
        "authorization": "Bearer " + KEY})
    t0 = time.time()
    try:
        resp = urllib.request.urlopen(req, timeout=TIMEOUT)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", "replace"), time.time() - t0
    except Exception as e:  # connection problems, timeouts
        return 0, repr(e), time.time() - t0
    if not stream:
        return resp.status, resp.read().decode("utf-8", "replace"), time.time() - t0
    events, ev = [], None
    for raw in resp:
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if line.startswith("event:"):
            ev = line[6:].strip()
        elif line.startswith("data:"):
            try:
                events.append((ev, json.loads(line[5:].strip())))
            except Exception:
                events.append((ev, {"_unparsed": line[:200]}))
    return resp.status, events, time.time() - t0


def assemble(events):
    """Rebuild a message from streaming events; returns (message, problems)."""
    problems, blocks, stop = [], {}, None
    evs = [e for e, _ in events if e != "ping"]
    if not evs or evs[0] != "message_start":
        problems.append("first event is not message_start: %r" % (evs[:1],))
    if evs[-1:] != ["message_stop"]:
        problems.append("last event is not message_stop: %r" % (evs[-1:],))
    started, stopped = set(), set()
    for ev, d in events:
        t = d.get("type")
        if ev and t and ev != t:
            problems.append("event name %r differs from data.type %r" % (ev, t))
        if t == "content_block_start":
            blocks[d.get("index")] = {"block": d.get("content_block", {}), "json": "", "text": ""}
            started.add(d.get("index"))
        elif t == "content_block_delta":
            b = blocks.get(d.get("index"))
            if b is None:
                problems.append("content_block_delta before content_block_start")
                continue
            dl = d.get("delta", {})
            if dl.get("type") == "input_json_delta":
                b["json"] += dl.get("partial_json", "")
            elif dl.get("type") == "text_delta":
                b["text"] += dl.get("text", "")
        elif t == "content_block_stop":
            stopped.add(d.get("index"))
        elif t == "message_delta":
            stop = d.get("delta", {}).get("stop_reason")
    if started != stopped:
        problems.append("content blocks started %s but stopped %s" % (sorted(started), sorted(stopped)))
    content = []
    for i in sorted(k for k in blocks if k is not None):
        b = blocks[i]
        blk = b["block"]
        if blk.get("type") == "tool_use":
            raw = b["json"] if b["json"] else json.dumps(blk.get("input", {}))
            try:
                inp = json.loads(raw)
            except Exception:
                problems.append("tool_use input is not valid JSON: " + raw[:120])
                inp = None
            content.append({"type": "tool_use", "id": blk.get("id"), "name": blk.get("name"), "input": inp})
        else:
            content.append({"type": "text", "text": b["text"] or blk.get("text", "")})
    msg = {"type": "message", "role": "assistant", "content": content, "stop_reason": stop}
    return msg, problems


def check_message(m, stream):
    p = []
    if not isinstance(m, dict):
        return ["response is not a JSON object"]
    if m.get("type") != "message":
        p.append("type != message")
    if m.get("role") != "assistant":
        p.append("role != assistant")
    c = m.get("content")
    if not isinstance(c, list) or not c:
        p.append("content is not a non-empty list")
        c = []
    tu = 0
    for b in c:
        t = b.get("type")
        if t == "text":
            if not isinstance(b.get("text"), str):
                p.append("text block without text")
        elif t == "tool_use":
            tu += 1
            if not (isinstance(b.get("id"), str) and b["id"]):
                p.append("tool_use without id")
            if b.get("name") not in NAMES:
                p.append("tool_use with unknown name %r" % (b.get("name"),))
            if not isinstance(b.get("input"), dict):
                p.append("tool_use input is not an object")
        else:
            p.append("unexpected block type %r" % (t,))
    sr = m.get("stop_reason")
    if sr not in ("tool_use", "end_turn", "max_tokens", "stop_sequence"):
        p.append("bad stop_reason %r" % (sr,))
    if tu and sr != "tool_use":
        p.append("tool_use block present but stop_reason=%r" % (sr,))
    if sr == "tool_use" and not tu:
        p.append("stop_reason=tool_use but no tool_use block")
    if not stream:
        u = m.get("usage")
        if not (isinstance(u, dict) and isinstance(u.get("input_tokens"), int)
                and isinstance(u.get("output_tokens"), int)):
            p.append("usage missing or malformed")
    return p


def tool_blocks(m):
    return [b for b in m.get("content", []) if b.get("type") == "tool_use"]


def text_of(m):
    return " ".join(b.get("text", "") for b in m.get("content", []) if b.get("type") == "text")


def summarize(m):
    tb = tool_blocks(m)
    if tb:
        return "; ".join("%s(%s)" % (b.get("name"), json.dumps(b.get("input"))[:100]) for b in tb)
    return "text: " + text_of(m)[:120].replace("\n", " ")


def sem_read(m):
    tb = tool_blocks(m)
    if tb and tb[0]["name"] == "Read" and str((tb[0]["input"] or {}).get("file_path", "")).endswith("package.json"):
        return True, "Read package.json"
    return False, "expected Read(file_path ending in package.json), got " + summarize(m)


def sem_bash(m):
    tb = tool_blocks(m)
    if tb and tb[0]["name"] == "Bash" and "ls" in str((tb[0]["input"] or {}).get("command", "")):
        return True, "Bash ls"
    return False, "expected Bash(command containing ls), got " + summarize(m)


def sem_version(m):
    if not tool_blocks(m) and "1.2.3" in text_of(m):
        return True, "answered 1.2.3 without another tool call"
    return False, "expected a text answer containing 1.2.3 and no tool call, got " + summarize(m)


def sem_no_tool(m):
    if not tool_blocks(m) and "51" in text_of(m):
        return True, "answered 51 directly"
    return False, "expected a direct answer containing 51 and no tool call, got " + summarize(m)


def sem_edit(m):
    tb = tool_blocks(m)
    if tb:
        b, inp = tb[0], (tb[0]["input"] or {})
        fp = str(inp.get("file_path", ""))
        if b["name"] == "Edit" and fp.endswith("notes.txt") and str(inp.get("old_string", "")).strip() == "foo" \
                and str(inp.get("new_string", "")).strip() == "bar":
            return True, "Edit with correct arguments"
        if b["name"] == "Read" and fp.endswith("notes.txt"):
            return True, "Read notes.txt first (acceptable)"
    return False, "expected Edit(notes.txt, foo -> bar) or Read(notes.txt), got " + summarize(m)


MSGS_C = [
    {"role": "user", "content": "Check the version in package.json and tell me what it is."},
    {"role": "assistant", "content": [
        {"type": "text", "text": "I will read the file."},
        {"type": "tool_use", "id": "toolu_01TESTCALL", "name": "Read", "input": {"file_path": "package.json"}}]},
    {"role": "user", "content": [
        {"type": "tool_result", "tool_use_id": "toolu_01TESTCALL",
         "content": "{\"name\": \"demo\", \"version\": \"1.2.3\"}"}]},
]

CASES = [
    ("A_read_file", False, [{"role": "user", "content": "Read the file package.json."}], sem_read),
    ("B_bash_stream", True, [{"role": "user", "content": "Run the command `ls -la` in the shell."}], sem_bash),
    ("C_tool_result", False, MSGS_C, sem_version),
    ("D_no_tool", False, [{"role": "user", "content": "What is 17 times 3? Reply with just the number."}], sem_no_tool),
    ("E_edit_args", False, [{"role": "user", "content": "In notes.txt, replace the word foo with bar."}], sem_edit),
]


def run_case(name, stream, msgs, sem):
    body = {"model": MODEL, "max_tokens": 300, "system": SYSTEM, "tools": TOOLS,
            "messages": msgs, "stream": stream}
    status, payload, secs = call("/v1/messages", body, stream)
    problems, msg = [], None
    if status != 200:
        problems.append("HTTP status %s" % status)
        snippet = str(payload)[:300]
    else:
        if stream:
            msg, pp = assemble(payload)
            problems += pp
            snippet = str(payload[:4])[:300]
        else:
            snippet = payload[:300]
            try:
                msg = json.loads(payload)
            except Exception:
                problems.append("body is not valid JSON")
        if msg is not None:
            problems += check_message(msg, stream)
    structure_ok = not problems
    sem_ok, detail = (False, "no message to judge")
    if msg is not None:
        sem_ok, detail = sem(msg)
    return {"name": name, "secs": secs, "structure_ok": structure_ok, "problems": problems,
            "sem_ok": sem_ok, "detail": detail, "snippet": snippet, "stream": stream}


results = []
for run in range(1, REPEAT + 1):
    for name, stream, msgs, sem in CASES:
        r = run_case(name, stream, msgs, sem)
        results.append(r)
        print("CASE %-14s run %d: secs=%6.1f structure=%s semantic=%s | %s" % (
            r["name"], run, r["secs"], "OK" if r["structure_ok"] else "FAIL",
            "OK" if r["sem_ok"] else "FAIL", r["detail"]))
        if not r["structure_ok"]:
            for p in r["problems"]:
                print("    structure problem: " + p)
            print("    raw: " + r["snippet"].replace("\n", " "))
        sys.stdout.flush()

total = len(results)
s_ok = sum(1 for r in results if r["structure_ok"])
m_ok = sum(1 for r in results if r["sem_ok"])
gate = "PASS" if (s_ok == total and m_ok >= 0.8 * total) else "FAIL"
print("CONFORMANCE_SUMMARY runs=%d structure_ok=%d semantic_ok=%d semantic_rate=%.0f%% gate=%s" % (
    total, s_ok, m_ok, 100.0 * m_ok / total if total else 0, gate))
sys.exit(0 if gate == "PASS" else 1)