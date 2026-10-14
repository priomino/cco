# Step 06 - Build the cpu engine image (tracking latest)

**Goal:** build `cco-engine:cpu` from `ubuntu:24.04` with Unsloth's installer in GGUF-only mode.

**What was done:** `docker/engine/Dockerfile` and `scripts/windows/build-engine.ps1` (reads settings from `config/.env`). The Dockerfile runs the installer as a non-root user with `UNSLOTH_NO_TORCH=1`, `UNSLOTH_SKIP_AUTOSTART=1`, `UNSLOTH_PYTHON=3.12` and `UNSLOTH_LLAMA_CPP_BACKEND=cpu`, optionally verifies the installer hash, optionally constrains the `unsloth` version, and records what was installed in `/home/cco/.cco-versions`. After a build the script tags a snapshot `cco-engine:<unsloth-version>-cpu`.

**Command:** `powershell -ExecutionPolicy Bypass -File .\build-engine.ps1`

**Result (as reported):**
- First attempt failed: the installer's llama.cpp preflight reported `libgomp.so.1` missing for `llama-server` and `llama-quantize` (see troubleshooting). Fix: add `libgomp1` to the Dockerfile's apt packages.
- Second build succeeded. Installed: `unsloth 2026.9.14`, `unsloth_zoo 2026.9.9` (venv under `/home/cco/.unsloth/studio/unsloth_studio`), prebuilt llama.cpp CPU bundle (upstream tag b11408). Tags: `cco-engine:cpu` and the snapshot `cco-engine:2026.9.14-cpu`.
- Docker reports the image as 0.68 GB (probably compressed, containerd snapshotter); free disk on C: fell by about 1.8 GB. Free space after the build: about 15.6 GB.
- The build script initially printed `BUILD FAILED` with an empty exit code even though the build succeeded (see troubleshooting); fixed in `build-engine.ps1`.
- The installer put the launcher in `~/.local/bin` and added it to `.bashrc`, which non-interactive container processes do not read; the entrypoint must set `PATH` explicitly.