#!/bin/bash
# measure.sh - runs inside the Claude Code image (docker run -i --network none ... bash -s).
# Starts a stub Anthropic-style server, runs `claude -p` against it under several settings,
# and prints what Claude Code actually sends (sizes, tools, headers, extra requests).
export PATH="$HOME/.local/bin:$PATH"
echo "claude: $(claude --version 2>&1 | head -1)"
mkdir -p /tmp/demo && cd /tmp/demo
git init -q . 2>/dev/null
printf 'hello\n' > README.md
printf '{"name":"demo","version":"1.2.3"}\n' > package.json
git add -A >/dev/null 2>&1
git -c user.name=cco -c user.email=cco@example.invalid commit -q -m init >/dev/null 2>&1

cat > /tmp/stub.py <<'PY'
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LOG = sys.argv[1]
PORT = int(sys.argv[2])


def summarize(headers, path, method, body):
    rec = {"method": method, "path": path, "bytes": len(body)}
    low = {k.lower(): v for k, v in headers.items()}
    auth = low.get("authorization", "")
    rec["auth"] = "bearer" if auth.lower().startswith("bearer ") else ("other" if auth else "none")
    rec["x_api_key"] = "x-api-key" in low
    rec["beta"] = low.get("anthropic-beta", "")[:100]
    try:
        j = json.loads(body) if body else None
    except Exception:
        j = None
    if isinstance(j, dict):
        tools = j.get("tools") or []
        sysv = j.get("system")
        if isinstance(sysv, list):
            head = " | ".join(str(b.get("text", ""))[:90] for b in sysv[:2] if isinstance(b, dict))
            syschars = sum(len(str(b.get("text", ""))) for b in sysv if isinstance(b, dict))
        else:
            head = str(sysv or "")[:180]
            syschars = len(str(sysv or ""))
        rec.update({
            "model": j.get("model"), "stream": j.get("stream"), "max_tokens": j.get("max_tokens"),
            "n_tools": len(tools), "tools": [t.get("name") for t in tools if isinstance(t, dict)][:30],
            "tools_chars": len(json.dumps(tools)), "system_chars": syschars, "system_head": head, "system_tail": json.dumps(sysv)[-200:],
            "messages_chars": len(json.dumps(j.get("messages"))),
            "thinking": "thinking" in j,
            "extra_keys": sorted(k for k in j if k not in ("model", "messages", "system", "tools", "max_tokens", "stream")),
        })
    return rec, j


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _json(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _record(self, body):
        rec, j = summarize(self.headers, self.path, self.command, body)
        with open(LOG, "a") as f:
            f.write(json.dumps(rec) + "\n")
        return j

    def do_GET(self):
        self._record(b"")
        self._json(404, {"type": "error", "error": {"type": "not_found_error", "message": "stub"}})

    def do_HEAD(self):
        self._record(b"")
        self.send_response(200)
        self.send_header("content-length", "0")
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(n) if n else b""
        j = self._record(body)
        if "count_tokens" in self.path:
            self._json(200, {"input_tokens": 1})
        elif self.path.startswith("/v1/messages") and isinstance(j, dict):
            model = j.get("model") or "stub"
            if j.get("stream"):
                self._sse(model)
            else:
                self._json(200, {"id": "msg_stub", "type": "message", "role": "assistant", "model": model,
                                 "content": [{"type": "text", "text": "Hello from the stub."}],
                                 "stop_reason": "end_turn", "stop_sequence": None,
                                 "usage": {"input_tokens": 1, "output_tokens": 5}})
        else:
            self._json(404, {"type": "error", "error": {"type": "not_found_error", "message": "stub"}})

    def _sse(self, model):
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("cache-control", "no-cache")
        self.send_header("connection", "close")
        self.end_headers()

        def ev(name, data):
            self.wfile.write(("event: %s\ndata: %s\n\n" % (name, json.dumps(data))).encode())

        ev("message_start", {"type": "message_start", "message": {
            "id": "msg_stub", "type": "message", "role": "assistant", "model": model, "content": [],
            "stop_reason": None, "stop_sequence": None, "usage": {"input_tokens": 1, "output_tokens": 1}}})
        ev("content_block_start", {"type": "content_block_start", "index": 0, "content_block": {"type": "text", "text": ""}})
        ev("content_block_delta", {"type": "content_block_delta", "index": 0,
                                   "delta": {"type": "text_delta", "text": "Hello from the stub."}})
        ev("content_block_stop", {"type": "content_block_stop", "index": 0})
        ev("message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                             "usage": {"output_tokens": 5}})
        ev("message_stop", {"type": "message_stop"})
        self.wfile.flush()
        self.close_connection = True


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
PY

cat > /tmp/summary.py <<'PY'
import json
import sys

try:
    lines = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
except FileNotFoundError:
    lines = []
if not lines:
    print("  NO REQUESTS RECEIVED")
for r in lines:
    total = r.get("tools_chars", 0) + r.get("system_chars", 0) + r.get("messages_chars", 0)
    print("  REQ %s %s bytes=%s model=%s stream=%s max_tokens=%s" % (
        r["method"], r["path"], r["bytes"], r.get("model"), r.get("stream"), r.get("max_tokens")))
    print("      auth=%s x_api_key=%s beta=%r thinking=%s extra_keys=%s" % (
        r["auth"], r["x_api_key"], r["beta"], r.get("thinking"), r.get("extra_keys")))
    if "n_tools" in r:
        print("      tools=%s (%d) tools_chars=%d system_chars=%d messages_chars=%d" % (
            r["tools"], r["n_tools"], r["tools_chars"], r["system_chars"], r["messages_chars"]))
        print("      ROUGH_TOKENS=%d (characters / 3.5, an estimate)" % (total / 3.5))
        print("      system_head=%r" % r.get("system_head", "")[:170])
        print("      system_tail=%r" % r.get("system_tail", "")[-200:])
PY

PORT=9100
COMMON="ANTHROPIC_BASE_URL=http://127.0.0.1:$PORT ANTHROPIC_MODEL=Qwen2.5-7B-Instruct-Q4_K_M ANTHROPIC_DEFAULT_HAIKU_MODEL=Qwen2.5-7B-Instruct-Q4_K_M ANTHROPIC_DEFAULT_SONNET_MODEL=Qwen2.5-7B-Instruct-Q4_K_M ANTHROPIC_DEFAULT_OPUS_MODEL=Qwen2.5-7B-Instruct-Q4_K_M CLAUDE_CODE_SUBAGENT_MODEL=Qwen2.5-7B-Instruct-Q4_K_M CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_AUTOUPDATER=1 CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1 CLAUDE_CODE_ATTRIBUTION_HEADER=0 CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 CLAUDE_CODE_DISABLE_AUTO_MEMORY=1 CLAUDE_CODE_MAX_CONTEXT_TOKENS=32768 CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096 CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1 CLAUDE_CODE_MAX_RETRIES=1 API_TIMEOUT_MS=60000"

run_cfg() {   # $1 label, $2 auth mode (token|apikey), rest: extra env assignments
  local label="$1" mode="$2"
  shift 2
  local log="/tmp/req-$label.jsonl"
  rm -f "$log"
  python3 /tmp/stub.py "$log" $PORT > "/tmp/stub-$label.out" 2>&1 &
  local spid=$!
  sleep 1
  echo "=== CONFIG $label (auth mode: $mode; extras: $*) ==="
  local -a envargs=(-u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN)
  local kv
  for kv in $COMMON "CLAUDE_CONFIG_DIR=/tmp/cfg-$label" "$@"; do envargs+=("$kv"); done
  if [ "$mode" = "apikey" ]; then envargs+=("ANTHROPIC_API_KEY=stub-token-not-a-real-key"); else envargs+=("ANTHROPIC_AUTH_TOKEN=stub-token-not-a-real-key"); fi
  cd /tmp/demo
  env "${envargs[@]}" timeout 120 claude -p "Say hello in one word." --output-format json $CLAUDE_FLAGS > "/tmp/out-$label.txt" 2> "/tmp/err-$label.txt" < /dev/null
  echo "  claude exit code: $?"
  echo "  claude stdout: $(head -c 300 /tmp/out-$label.txt | tr '\n' ' ')"
  echo "  claude stderr: $(head -c 800 /tmp/err-$label.txt | tr '\n' ' ')"
  kill $spid 2>/dev/null
  wait $spid 2>/dev/null
  python3 /tmp/summary.py "$log"
}

run_cfg baseline    token
run_cfg nogit       token  CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1
run_cfg shortprompt token  CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1 CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1
run_cfg bare_token  token  CLAUDE_CODE_SIMPLE=1
run_cfg bare_apikey apikey CLAUDE_CODE_SIMPLE=1
echo MEASURE_DONE