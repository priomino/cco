# Step 19 - One-command entry point

**Goal:** `claude.ps1` (starts the engine if needed, then Claude Code in bare mode on a Windows project folder), `up.ps1` and `down.ps1`, tested on a bind-mounted demo folder.

**What was done:** `docker/claude/entrypoint.sh` (reads the engine key copied into the container, then runs Claude Code), `docker/claude/claude.env` (fixed settings), Dockerfile changes (config directory `/home/cco/.claude-cfg`, entrypoint), `Ensure-CcoEngine` in `common.ps1`, `claude.ps1`, `up.ps1`, `down.ps1`, and `test-claude-entry.ps1`, which creates `C:\projects\cco-demo-project`, runs `claude.ps1 -Prompt ... -StopEngineOnExit` on it and checks the result on Windows. The Claude Code image was rebuilt with `build-claude.ps1`.

**Result (as reported, run twice, exit 0 both times; Claude Code 2.1.295):**
- Run 1: engine started in 32 s, session completed, `notes.txt` on Windows became `bar is here. bar again.`, version `2.0.1` reported, engine stopped.
- Run 2: `claude.ps1` found the engine already running with the model loaded and skipped the start; same result.
- A red `NativeCommandError` banner appeared around the informational `unrecognized_model` line because the test merged the child's error stream; fixed in step 20 (see troubleshooting).
- Not yet seen: the user's report of an interactive session.