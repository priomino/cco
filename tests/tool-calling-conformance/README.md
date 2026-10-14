# Tool-calling conformance test

Sends five kinds of `/v1/messages` requests (non-streaming tool call, streaming tool call with event-sequence
validation, tool-result round trip, a request that needs no tool, a multi-argument edit) with tool definitions shaped
like Claude Code's (`Bash`, `Read`, `Edit`, `Write`, `Glob`).

- **Structure** (valid message shape, ids, stop reasons, JSON arguments, SSE event order) must pass on every run.
- **Semantics** (right tool, right arguments) must pass on at least 80% of runs.

Run it with `scripts\windows\conformance.ps1 [-Repeat 2]`. The Python file runs inside the engine container
(standard library only). It is the hard gate before Claude Code is connected; re-run it after every engine or model upgrade.