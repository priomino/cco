# Step 04 - Unsloth install probe (read-only)

**Goal:** learn how to install the Unsloth engine into a lean container, pinned, and what the install touches on the network.

**What was done:** `scripts/windows/probe-unsloth-install.ps1` queried Docker Hub for `unsloth/unsloth` tag sizes and, in a throwaway `ubuntu:24.04` container, downloaded `https://unsloth.ai/install.sh` and read it without executing it.

**Command:** `powershell -ExecutionPolicy Bypass -File .\probe-unsloth-install.ps1`

**Result (as reported, exit 0):**
- Official images: `latest`/`studio` about 9.95 GB, `core` about 7.41 GB (Docker Hub, early October 2026). Too large for the target disk.
- Free space on C: was 19.7 GB (24.7 GB at step 01).
- `install.sh`: 8911 lines, SHA-256 `3e68fc36d670131ff1f66136a4bc3f7729433d91532bb36b5e8538529fadf6aa` at the time of the probe. About 60 `UNSLOTH_*` variables, among them `UNSLOTH_NO_TORCH`, `UNSLOTH_FORCE_VULKAN`, `UNSLOTH_LLAMA_CPP_BACKEND`, `UNSLOTH_PYTHON`, `UNSLOTH_STUDIO_HOME`, `UNSLOTH_SKIP_AUTOSTART`. No version-pin variable found. A `--package` argument and `UNSLOTH_PYPI_JSON_URL` exist; their behaviour is not yet known.
- Hosts referenced by the installer: pypi.org, files.pythonhosted.org, github.com, raw.githubusercontent.com, releases.astral.sh, nodejs.org, registry.npmjs.org, unsloth.ai (plus PyTorch and ROCm hosts that a GGUF-only CPU/Vulkan install should not need).

**Next:** read the specific installer sections that decide pinning, llama.cpp acquisition and system-package needs, and check where the free disk space went (step 05).