# Step 09 - Pre-flight reads (model repo, disk arithmetic, switch names)

**Goal:** confirm the model repository and file, work out the disk arithmetic for the download, and read exact switch names and the Claude Code launcher environment from the installed Unsloth.

**What was done:** `scripts/windows/probe-preflight.ps1` queried the Hugging Face API from the host and searched the installed packages in a throwaway container with `--network none`.

**Result (as reported, exit 0):**
- `unsloth/Qwen2.5-7B-Instruct-GGUF`: the API answered "Invalid username or password" (what Hugging Face returns to anonymous requests for missing or private repos); not used.
- `bartowski/Qwen2.5-7B-Instruct-GGUF`: lists the usual quants; `Qwen2.5-7B-Instruct-Q4_K_M.gguf` is 4.36 GiB with a published SHA-256.
- C: free was 13.3 GiB (15.6 GiB at step 06, with nothing of ours running in between), so about 8.9 GiB would remain after the download.
- Switch names confirmed in the code: `UNSLOTH_STUDIO_DISABLE_PUBLIC_CHECK`, `UNSLOTH_HELPER_MODEL_DISABLE`, `UNSLOTH_STUDIO_OFFLINE`, `UNSLOTH_OFFLINE_PROBE`, `UNSLOTH_STUDIO_PASSWORD`, `UNSLOTH_STUDIO_ENGINE_STALL_TIMEOUT_S`, `UNSLOTH_STUDIO_MAX_BODY_MB`. The listing was capped at 60 lines.
- `unsloth_cli/commands/start.py` shows the Claude Code environment used by Unsloth's own launcher (see architecture D13).
- The three hidden `.venv_t5_*` environments are 68 MB, 50 MB and 47 MB; not worth removing.