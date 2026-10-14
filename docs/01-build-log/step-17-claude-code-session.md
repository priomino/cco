# Step 17 - First Claude Code session against the engine (offline)

**Goal:** run a real Claude Code session in bare mode against the engine and check that it reads a file, edits another and reports correctly, with the compose network cut off from the internet.

**What was done:** `docker/compose.yaml` network `cco_net` made `internal: true`; `tests/claude-session/session.sh` run in a Claude Code container (`docker run --network cco_net`, workspace volume `cco_workspace`) by `scripts/windows/claude-session.ps1`, which starts the engine, reads its API key (never printed) and passes it to the container through standard input together with the Claude Code settings from architecture D21 and D22 (plus `CLAUDE_CODE_DISABLE_THINKING=1`).

**Command:** `powershell -ExecutionPolicy Bypass -File .\claude-session.ps1`

**Result (as reported, exit 0, Claude Code 2.1.295):**
- The engine loaded in 32 s on the internal network; the engine answered HTTP 200 from the Claude container; the internet check failed (curl 000).
- `claude -p` in bare mode: exit 0, 4 turns, 90 s. Result: version `1.2.3` reported, `notes.txt` became `bar is here. bar again.`. No permission denials. stderr only the informational `unrecognized_model` line.
- Two API requests. Request 1: 1,008 prompt tokens in 55.8 s (18.1 tokens/s), 83 tokens generated at 4.7 tokens/s (73 s in total). Request 2: 124 new prompt tokens in 8.2 s (the rest from the prefix cache), 40 tokens at 5.1 tokens/s (16 s in total). The bare-mode estimate (about 960 tokens) matched the measured 1,008.
- Host free commit fell to 2.2 GiB during the run.