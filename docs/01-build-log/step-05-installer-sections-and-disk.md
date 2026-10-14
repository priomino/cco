# Step 05 - Installer sections and disk accounting (read-only)

**Goal:** find how to pin Unsloth, how llama.cpp is acquired, what system packages are needed, and where free disk space went.

**What was done:** `scripts/windows/probe-unsloth-install2.ps1` printed `docker system df`, VHDX sizes, and selected sections of `install.sh` (read in a throwaway container, not executed).

**Result (as reported, exit 0):**
- Docker uses about 6 GB (7 images, 5.7 GB; data VHDX 6.2 GB, up from 5.7 GB). Free space on C: was 19.7 GB, down from 24.7 GB at step 01, so most of that 5 GB drop is outside Docker.
- `--package` accepts only a bare package name (letters, digits, `.`, `_`, `-`); it cannot carry a version. `UNSLOTH_PYPI_JSON_URL` exists but its effect was not examined.
- GGUF-only is a supported mode (`--no-torch` / `UNSLOTH_NO_TORCH`). On Linux only a download transport (curl) is required; cmake, gcc and libcurl headers are for an optional llama.cpp source build and are not installed on the consumer path.
- The llama.cpp backend is selected at install time by `UNSLOTH_LLAMA_CPP_BACKEND` (`cpu`, `cuda`, `rocm`, `hip`, `vulkan`, `auto`), which takes precedence over the legacy `UNSLOTH_FORCE_VULKAN`.
- The installer's Vulkan diagnostics refer to Linux render nodes (`/dev/dri/renderD*`), which WSL2 does not provide; the `igpu` profile therefore depends on a Mesa `dzn` path that is unproven (verify in the iGPU phase).

**Decision taken:** version policy in architecture D10 (owner chose to track latest rather than pin).