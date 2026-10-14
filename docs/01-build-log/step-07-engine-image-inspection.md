# Step 07 - Engine image inspection (read-only, no network)

**Goal:** learn what is inside `cco-engine:cpu`: entrypoints, CLI options, disk use and outbound-contact spots.

**What was done:** `scripts/windows/probe-engine-image.ps1` ran a throwaway container from the image with `--network none` and printed help texts, file locations, disk use and selected code searches.

**Result (as reported, exit 0):**
- Runs as user `cco` (uid 1000). `unsloth` is a symlink in `~/.local/bin` to the Studio venv; that directory is on PATH only for interactive shells, so PATH must be set explicitly.
- The CLI works with the network disabled. Commands: train, inference, chat, export, eval, list-checkpoints, run (alias of `studio run`), studio, start (starts a coding agent such as Claude Code against Unsloth).
- `unsloth run` options seen (first 90 help lines only): `--model/-hf` (path or HF repo, `org/repo:variant`), `--gguf-variant`, `--max-seq-length` (0 = model default), `--gpu-memory-mode`, `--speculative-type` (default auto), `--api-key-name`, `--password` (or `UNSLOTH_STUDIO_PASSWORD`), `--verbose`, `--silent`, `--yes`. `unsloth studio` adds `--host` (default 127.0.0.1), `--port` (8888), `--api-only`, `--parallel` (4), `--cloudflare/--secure` (off).
- `llama-server` at `/home/cco/.unsloth/llama.cpp/build/bin/llama-server`, version build 11408 (commit 7e9d1839c); `libgomp.so.1` resolves.
- Disk under `~/.unsloth`: studio 1.7 GB, llama.cpp 248 MB, node 203 MB, whisper.cpp 1.6 MB.
- `studio/backend/run.py` contacts `ifconfig.me` and `check-host.net` on wildcard binds unless a switch disables it (docs name `UNSLOTH_STUDIO_DISABLE_PUBLIC_CHECK`; confirm). Other "telemetry" hits were hardware monitoring; the search was capped at 30 hits.

**Open:** full option list of `unsloth run`, how the API key is created and supplied, exact offline switches.