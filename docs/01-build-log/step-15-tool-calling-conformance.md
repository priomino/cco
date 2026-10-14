# Step 15 - Tool-calling conformance test

**Goal:** prove with a script that the engine's Anthropic `/v1/messages` endpoint returns well-formed tool calls, and measure how often Qwen2.5-7B chooses the right tool with the right arguments.

**What was done:** `tests/tool-calling-conformance/conformance.py` (Python standard library, run inside the engine container) driven by `scripts/windows/conformance.ps1`, which uses the new shared helpers in `scripts/windows/common.ps1`. Five cases (non-streaming `Read`, streaming `Bash` with SSE event-order validation, tool-result round trip, no-tool question, multi-argument `Edit`), 2 runs each, with Claude-Code-shaped tool definitions (`Bash`, `Read`, `Edit`, `Write`, `Glob`).

**Command:** `powershell -ExecutionPolicy Bypass -File .\conformance.ps1`

**Result (as reported, exit 0):** `runs=10 structure_ok=10 semantic_ok=10 semantic_rate=100% gate=PASS`. First request 32 s (processes the tool definitions), later requests 2-11 s (prefix cache). No tool-call healing messages appeared in the engine log. Free Windows commit fell to 0.8 GiB after the model load.

**Limits of the result:** small tool set and ten runs; Claude Code's own request has more tools and a much larger system prompt, so the end-to-end session is the real test (steps 16 onwards).