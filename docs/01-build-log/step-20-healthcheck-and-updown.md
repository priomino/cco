# Step 20 - Health check and up/down acceptance test

**Goal:** make "healthy" mean "model loaded" and verify `up.ps1` / `down.ps1` end to end.

**What was done:** a `healthcheck` on the `engine-cpu` service (reads the cached API key, requires `/v1/models` to list a model), `Get-CcoHealth` in `common.ps1`, `up.ps1` v2 (waits for healthy), and `scripts/windows/test-up-down.ps1`.

**Result (as reported, exit 0):** engine healthy 34 s after `up.ps1`; no published ports; `cco_net` internal; container labelled; model volume present; after `down.ps1` the container and network were gone, the model volume and both images kept; the four non-cco containers (the user's other stack) were identical before, during and after.

**User trial of the interactive session (reported afterwards):** (1) Claude Code only prints files instead of saving them (bare mode has no Write tool and a 93-character system prompt; under investigation in step 21); (2) the engine should stop when Claude Code exits (fixed in step 21: `claude.ps1` stops it by default, `-KeepEngine` keeps it).