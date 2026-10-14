# Architecture and decisions

Decisions are recorded as they are made, with the alternatives rejected. Items marked "verify:" were not confirmed at the time of writing.

## Overview
- **Engine** (D3, D8-D12, D14, D25): a container built from `ubuntu:24.04` with Unsloth's installer in GGUF-only mode; llama.cpp (CPU) loads the model from the volume `cco_models`; started by compose with `--disable-tools`, `--parallel 1`, a 32,768-token context and a health check that means "model loaded".
- **Network** (D6, D23, D24): the compose network `cco_net` is internal (no route to the internet); no ports are published; the Claude Code container joins it on demand.
- **Claude Code** (D21, D22, D27, D28): the official native build in its own container, configured with environment files (`docker/claude/claude.env` and a mode file); three modes trade tool set against prompt size.
- **Scripts** (D24, D26, D30, D31): `claude.ps1`, `up.ps1`, `down.ps1`, install, upgrade, rollback, validation and the tests, all PowerShell, all sharing `scripts/windows/common.ps1`.
- **Future macOS support** (D7): the engine sits behind a single `engine.backend` key and a stable endpoint contract so a Docker Model Runner backend can be added later.

## D1. Everything runs in Docker
Engine, optional proxy, Claude Code and tests are containers in one compose project (`cco`). GPU mode (iGPU or CPU) is a compose profile, not a topology change.

## D2. Container runtime: Rancher Desktop with the moby (dockerd) engine
- Chosen because it was already installed, it runs dockerd in a WSL2 distro that exposes `/dev/dxg`, and a second runtime would compete for limited disk and WSL memory.
- Evidence (step 01b): a container under Rancher can see `/dev/dxg` and Intel OpenCL lists the iGPU.
- Rejected: Docker Desktop (extra install, licence terms, no demonstrated advantage here).
- Requirement stated for users: any Docker-API-compatible runtime on WSL2; tested on Rancher Desktop 1.22 in moby mode.

## D3. Engine: Unsloth (fixed)
Unsloth serves GGUF models through `llama-server` and exposes an Anthropic-compatible `/v1/messages` endpoint on the same port as the OpenAI-style endpoints (docs: https://unsloth.ai/docs/basics/api). Unsloth Studio is beta software, so versions are pinned.

## D4. API translation: native endpoint first (option A), proxy as fallback
Claude Code talks to the engine's `/v1/messages` directly. If the tool-calling conformance test fails, a `proxy` service (LiteLLM or custom) is enabled behind the same config key. Final choice is made in Phase 3 on test evidence.

## D5. GPU strategy
- Profiles `cpu` and `igpu` share image and config; only device flags and engine build variant differ.
- Unsloth's documented Intel GPU path for GGUF is Vulkan, not OpenCL (verify: selection via `UNSLOTH_LLAMA_CPP_BACKEND`). Inside WSL2 this most likely goes through Mesa `dzn` (Vulkan over D3D12) (verify:).
- `igpu` budget: two steps (Vulkan device visible in a container; engine actually offloads). If it fails, `cpu` is the default and the failure goes in troubleshooting.

## D6. Isolation from other workloads on the same engine
Other containers may already run on the user's Docker engine. Everything here uses project name `cco`, `cco-` prefixes, one network (`cco_net`), a label `com.claude-code-offline.project=cco`, no host port publishing except an optional `127.0.0.1` diagnostic port, and scripts only act on labelled resources (never `system prune`).

## D7. Future macOS support
The engine sits behind a single `engine.backend` config key and a stable proxy contract, so a `dmr` backend (Docker Model Runner, Compose `models:` element, Metal via vllm-metal) can be added later without touching Claude Code, tests or the docs structure. No macOS code exists in v1.0.
## D8. The engine image is built by us, not pulled
Docker Hub lists `unsloth/unsloth` at about 7.4 GB (`core`) and about 9.95 GB (`studio`/`latest`), and those images target training. Rejected for a machine with under 20 GB free. We build from `ubuntu:24.04` with Unsloth's installer in GGUF-only mode (`UNSLOTH_NO_TORCH=1`). Studio components are AGPL-3.0; we download them at build time and do not redistribute them (relevant to the repo LICENSE choice).

## D9. `cpu` and `igpu` are two builds of one Dockerfile
Per Unsloth's docs the llama.cpp bundle (CPU or Vulkan) is chosen at install time (`UNSLOTH_FORCE_VULKAN=1`), not at launch. So a build argument selects the variant while config, ports and the proxy contract stay identical. This refines D5 (verify during the build).

## D10. Version policy: track latest, upgrade on demand (owner decision, 2026-10-06)
The original requirement was to pin Unsloth and Claude Code explicitly. The owner chose instead to track the latest releases and make upgrades easy. This supersedes the earlier "layered pinning" plan.
- Default `CCO_UNSLOTH_VERSION=latest`. An exact version can still be set in one line (optional pin). The optional installer hash check is off by default.
- `build-engine.ps1 -Upgrade` rebuilds without cache; every build is tagged with its resolved version (`cco-engine:<version>-<variant>`) so older builds remain available for rollback until deleted.
- Claude Code follows the same policy when its container is added (its self-updater to be disabled in the container so upgrades happen only on rebuild; verify the setting name then).
- Risk accepted: Unsloth is beta and a new release can break behaviour (notably tool calling). The tool-calling conformance test is the gate after every upgrade.
- Facts found in step 05: `install.sh` has no version variable and `--package` cannot carry a version, so pinning goes through a constraints file (`UV_CONSTRAINT` / `PIP_CONSTRAINT`; verify) rather than the installer.
Rejected: mandatory pinning (against the owner's preference); the official image (size, see D8).

## D11. Engine runtime layout (from image inspection, step 07)
- The engine container runs as the non-root user `cco`; the entrypoint sets `PATH` to include `/home/cco/.local/bin`.
- The server is started with `unsloth run` (alias of `unsloth studio run`), bound to `0.0.0.0` inside the compose network only; `--cloudflare` and `--secure` are never used.
- The public-IP and reachability checks (`ifconfig.me`, `check-host.net`) are disabled with Unsloth's documented switch (name to confirm in step 08).
- Unsloth also ships `unsloth start <agent>` (including Claude); we do not use it, because Claude Code runs in its own container, but the environment it sets is a useful reference.

## D12. Engine start policy (draft from step 08; confirmed on first run)
- Draft command: `unsloth run -hf <model> --context-length <N> --parallel 1 --host 0.0.0.0 --port 8888 --api-only --disable-tools --speculative-type off`.
- `--disable-tools`: server-side tools are on by default for every bind in the installed version (this contradicts a docs summary read earlier), so they are forced off. Claude Code executes its own tools on the client side.
- `--parallel 1`: each parallel slot gets context/N of the KV cache, so the default of 4 would quarter the context available to a request.
- Tool-call healing and nudging stay on (defaults). They convert text-form `<tool_call>` output of small models into structured calls; the conformance test remains the gate.
- Offline and privacy switches to set: `UNSLOTH_OFFLINE`, `UNSLOTH_LLAMA_CPP_OFFLINE`, `UNSLOTH_DISABLE_UPDATE_CHECK`, `UNSLOTH_DISABLE_STATISTICS`, plus the public-IP-check switch (name to confirm).
- Auth: the server prints an API key at start, reused per `--api-key-name`; how to supply a fixed key is open. An initial admin password is supplied through `UNSLOTH_STUDIO_PASSWORD` (generated into the git-ignored `.env`).
- Disk: the 1.6 GB uv cache is most likely hard-linked into the venv, so deleting it frees little; the hidden `.venv_t5_*` environments (non-GGUF models) are the slimming candidates, to be measured first.

## D13. Model source, storage and Claude Code environment reference (step 09)
- **Model:** `bartowski/Qwen2.5-7B-Instruct-GGUF`, file `Qwen2.5-7B-Instruct-Q4_K_M.gguf` (4.36 GiB). The `unsloth/` GGUF repo did not exist on the Hugging Face API. The download is verified against Hugging Face's published SHA-256. Model source, file and checksum are configurable (`CCO_MODEL_*`).
- **Storage:** Docker volume `cco_models`, mounted at `/models`; the download is the only step that needs the internet besides image builds.
- **Engine switches to set** (names confirmed in the installed code): `UNSLOTH_STUDIO_DISABLE_PUBLIC_CHECK=1`, `UNSLOTH_HELPER_MODEL_DISABLE=1` (stops a background pre-download of a helper model), `UNSLOTH_DISABLE_UPDATE_CHECK=1`, `UNSLOTH_DISABLE_STATISTICS=1`; `UNSLOTH_STUDIO_OFFLINE` and `UNSLOTH_OFFLINE_PROBE=0` after the model is in place (semantics to verify). To watch on slow hardware: `UNSLOTH_STUDIO_ENGINE_STALL_TIMEOUT_S`, `UNSLOTH_STUDIO_MAX_BODY_MB`.
- **API key:** `unsloth studio run` caches its key in a file `.cli_api_key_<name>_<digest>` (mode 0600) under the studio home and mints a new one only when the cached key is dead. The Claude Code container can read it from a shared volume (exact path to be confirmed on first run).
- **Claude Code environment used by Unsloth's launcher** (reference only; verify against Claude Code's documentation before use): `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, `CLAUDE_CODE_ATTRIBUTION_HEADER=0`, `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`, `CLAUDE_CODE_NO_FLICKER=1`, and with a known window `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`. It also unsets provider-routing variables (`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`, `CLAUDE_CODE_USE_BEDROCK`, `CLAUDE_CODE_USE_VERTEX`, `CLAUDE_CODE_USE_FOUNDRY` and related) so nothing bypasses the local server. The attribution header and token reminder change the system-prompt prefix, which would defeat llama.cpp prompt caching (inference; to verify by measurement).

## D14. Compose layout (step 11)
- One compose file, `docker/compose.yaml`, project name `cco`, always run through the scripts (they pass `--env-file config\.env` and the profile).
- Service `engine-cpu` (profile `cpu`, container `cco-engine-cpu`, image `cco-engine:cpu`), runs as `cco` (uid 1000), network `cco_net` with alias `engine`, no published ports, model volume `cco_models` mounted read-only at `/models`.
- Command: `unsloth run -hf /models/<file> --context-length 32768 --parallel 1 --host 0.0.0.0 --port 8888 --api-only --disable-tools --speculative-type off`.
- Environment: PATH including `~/.local/bin`, `HF_HUB_DISABLE_TELEMETRY`, `UNSLOTH_STUDIO_DISABLE_PUBLIC_CHECK`, `UNSLOTH_HELPER_MODEL_DISABLE`, `UNSLOTH_DISABLE_UPDATE_CHECK`, `UNSLOTH_DISABLE_STATISTICS`, `UNSLOTH_STUDIO_PASSWORD` (from `.env`). `UNSLOTH_STUDIO_OFFLINE` and `HF_HUB_OFFLINE` are added in the offline phase, after the first run shows what they change.
- Context 32768 is the model's native maximum and about the minimum Claude Code needs; the KV cache for it is roughly 1.8 GiB (estimate; confirm from the engine log).
- Engine state: the API key is cached in `/home/cco/.unsloth/studio/auth/.cli_api_key_cli_<digest>`; that directory is created at runtime and is not in the image. Nothing is persisted yet. Persisting it (a volume on `auth/`, read-only in the Claude Code container) needs the directory added to the image and is a later step.

## D15. First measurements and readiness (step 11)
- Startup: web server up in about 11 s, model loaded in about 14 s more. Readiness must mean "model loaded" (log line `Loaded GGUF model via llama-server`), not "web server answers".
- `llama-server` is started by Unsloth with `--flash-attn on --no-context-shift --jinja --fit on` and no explicit thread count; thread tuning (`UNSLOTH_CPU_THREADS`) is a later experiment.
- Tool-call healing is part of the server; whether tool calls from this model are reliable is decided by the conformance test, not assumed.
- The engine prints the API key in its log; the compose port is not published, so the key is only usable inside the compose network.

## D16. Performance findings and the plan they imply (step 12)
- Measured on the i7-1265U under WSL2, CPU profile: prefill about 10-12 tokens/s, generation about 4 tokens/s (about 2 at 7k context), prefix cache effective. See `docs/06-known-limitations.md`.
- Earlier assumption corrected: the iGPU was expected to give only a modest gain because generation is memory-bandwidth-bound; but prefill is compute-bound and is the bottleneck for an agent, so the `igpu` attempt (two-step budget) is moved up, right after the CPU thread/power diagnostics.
- Levers, to be applied and measured one at a time: power/thermal state and thread count (step 13), iGPU via Vulkan, a smaller model, restricting Claude Code's tools to shrink its prompt, and pre-warming the prompt cache at engine start (Unsloth starts llama-server with `--slot-save-path`).

## D17. What the CPU sees inside the Docker VM (step 13)
- The VM reports the i7-1265U as 6 cores x 2 threads (12 CPUs), hiding the real hybrid layout (2 performance + 8 efficiency cores); llama.cpp therefore cannot place threads by core type, and its default thread count (not set by Unsloth) is probably 6 (to verify from the sweep).
- The llama.cpp bundle contains several CPU backends, including one for Alder Lake; which one is loaded depends on the CPU features the VM exposes (printed by the sweep).
- `llama-bench` is not available in the bundle; sweeps use `llama-server` directly.

## D18. CPU tuning outcome (step 13)
- Use at most 8 threads (6-8 are equivalent within the noise of single runs); never 12, which collapses generation speed. Unsloth does not set a thread count; `UNSLOTH_CPU_THREADS` exists and is to be tested for whether it reaches `llama-server` (not yet verified).
- Best observed CPU configuration: 8 threads, flash attention on: about 21 tokens/s prefill, 6 tokens/s generation.
- Next lever: iGPU via Vulkan (two-step budget; step 14 checks that a Vulkan device is visible).

## D19. iGPU status after attempt 1 (step 14)
- Vulkan on Ubuntu 24.04 cannot reach the Iris Xe (no `dzn`). The `igpu` profile does not work in v1.0 as it stands; `cpu` is the default.
- Remaining routes, unverified: (1) a distribution whose Mesa package includes `dzn` (Fedora or Arch are candidates), then a variant engine image on that base, subject to llama.cpp's Vulkan backend accepting a `dzn` device; (2) a locally built SYCL / Level Zero llama.cpp (Unsloth supports a local llama.cpp directory), which needs Intel's oneAPI toolchain (multi-gigabyte build stage).
- One step of the two-step iGPU budget is left; the decision on whether to spend it now is taken after step 14.

## D20. Tool-calling conformance gate (step 15)
- The test (`tests/tool-calling-conformance/conformance.py`, run by `scripts/windows/conformance.ps1`) sends requests with Claude-Code-shaped tools to `/v1/messages`: non-streaming tool call, streaming tool call with SSE event-order validation, tool-result round trip, no-tool request, multi-argument edit.
- Two levels: structure must be correct on every run; semantic correctness (right tool, right arguments) must reach 80%.
- It runs inside the engine container with the Python standard library only, so it needs nothing on the host, and it is repeated after every engine or model upgrade (see D10).
- Decision rule for a FAIL: fix the translation or template layer first (engine flags, chat template, proxy option B or C of D4); do not connect Claude Code on hope.

## D21. Claude Code runtime settings and why (step 16; from the official environment-variable reference)
- Auth and routing: `ANTHROPIC_BASE_URL` (the engine on the compose network), `ANTHROPIC_AUTH_TOKEN` (sent as a Bearer token). In the minimal mode (`CLAUDE_CODE_SIMPLE`) the documentation says authentication must come from `ANTHROPIC_API_KEY` or an `apiKeyHelper`; step 16 measures which header Claude Code really sends.
- Timeouts, because prompt processing is slow and sends no bytes before the first token: raise `API_TIMEOUT_MS`, set `API_FORCE_IDLE_TIMEOUT=0`, and raise `CLAUDE_STREAM_IDLE_TIMEOUT_MS` and `CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS` (the latter is clamped to 10 s - 30 min); disable the non-streaming fallback (`CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1`) and limit retries (`CLAUDE_CODE_MAX_RETRIES`), so that a slow turn is not resent while the single-slot server is still working on it. The default idle-timeout values differ between sources, so they are set explicitly.
- Prompt size (each 1,000 tokens costs about a minute at 15-20 tokens/s): `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1`, `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` (shorter system prompt, abbreviated tool descriptions) or `CLAUDE_CODE_SIMPLE=1` (minimal prompt, only Bash, file read and file edit tools, no hooks/skills/MCP/CLAUDE.md/auto memory); `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`.
- Prefix caching: `CLAUDE_CODE_ATTRIBUTION_HEADER=0` removes a block at the very start of the system prompt that a local server would treat as plain text.
- No competing background requests on the single model slot: all model aliases (`ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_HAIKU_MODEL`, `_SONNET_`, `_OPUS_`, `CLAUDE_CODE_SUBAGENT_MODEL`) point at the one local model; `CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1`, `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false`.
- Offline and telemetry: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (auto-updates, telemetry, error reporting, feedback, release notes), `DISABLE_AUTOUPDATER=1`, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1`.
- Context: `CLAUDE_CODE_MAX_CONTEXT_TOKENS=32768` (the auto-compact window variable only accepts 100,000 and up), `CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096` (a larger value shrinks the usable window).
- The image is built from the official native installer and tracks the latest release (owner decision, see D10); the resolved version is recorded in `/home/cco/.cco-versions` and as a snapshot tag.

## D22. Claude Code runs in bare mode by default (step 16)
- Measured: the default Claude Code request is about 60 KB with 20 tool definitions (about 48 KB of it tools), an estimated 17,000-17,500 tokens, which is roughly 15 minutes of prompt processing at the measured 15-20 tokens/s. `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS` saves about 0.4k tokens and `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` had no effect on an unrecognized model.
- `CLAUDE_CODE_SIMPLE=1` (bare mode) sends 3 tools (Bash, Edit, Read) and a 93-character system prompt: about 3.7 KB, roughly 1,000 tokens (about one minute). Authentication with `ANTHROPIC_AUTH_TOKEN` still produces a Bearer header, which is what the engine needs.
- Trade-off: no Write, Glob, Grep, web, subagent or task tools, and no CLAUDE.md, hooks, skills, MCP servers or auto memory in bare mode. Bash covers most of the gap. The three tools are the ones the conformance test exercised (D20).
- Full mode stays available as a configuration for faster hardware (planned key `CCO_CLAUDE_MODE=full`), but is not practical on the reference machine.
- Added for the real session: `CLAUDE_CODE_DISABLE_THINKING=1` (omit the `thinking` parameter, which Qwen2.5 does not use). Whether the engine copes with `output_config` and `metadata` is checked by the session test (step 17).

## D23. End-to-end result and what it proves (step 17)
- With `cco_net` internal, the engine starts and serves Anthropic-format requests with no internet access, and Claude Code (bare mode) completes a read-and-edit task through it. The offline claim is therefore tested at the network level (no route out), not just by configuration; a test with the host network disabled is still planned (Phase 6).
- Observed cost of a three-tool task: about 90 s, dominated by 56 s of prompt processing for the first 1,008 tokens; follow-up requests reuse the prefix cache and only process new tokens.
- Not yet covered: the interactive terminal interface, larger tasks, a bind-mounted project folder, and running everything from one `docker compose up`.

## D24. Entry point, bind mounts and key delivery (steps 18-19)
- The engine runs under compose (`up.ps1`, `down.ps1`); the Claude Code container is started on demand by `claude.ps1` with `docker create`, `docker cp` and `docker start -ai`, because its project folder is a per-invocation Windows path and it needs a terminal.
- Windows folders are bind-mounted with `--mount type=bind,source=C:\path,target=/workspace` (plain Windows notation, tested; `//c/` and `/c/` forms do not work). The container user (uid 1000) can read and write the mount.
- The engine API key is read from the running engine (`docker exec`), written to a temporary file on Windows, copied into the created container as `/tmp/cco-engine-key` and deleted from Windows immediately; the entrypoint `cco-claude-entry` exports it as `ANTHROPIC_AUTH_TOKEN` and deletes the file. The key never appears on a command line or in script output.
- Fixed Claude Code settings are in `docker/claude/claude.env`; model-dependent ones (`ANTHROPIC_MODEL` and aliases) are derived from `CCO_MODEL_FILE`. Claude Code's own configuration lives in the named volume `cco_claude_home` (`CLAUDE_CONFIG_DIR=/home/cco/.claude-cfg`).
- The engine is left running after `claude.ps1` exits (restart in seconds, about 7 GiB of memory held); `down.ps1` or `-StopEngineOnExit` stops it.

## D25. Engine health check (step 20)
- The compose service `engine-cpu` has a health check that reads the cached API key and succeeds only when `/v1/models` lists a model, i.e. the model is loaded (the web server and `/api/health` answer earlier, see D15). Interval 15 s, timeout 10 s, 8 retries, start period 90 s.
- `up.ps1` waits for `healthy` (exit 4 if the model is loaded but the check never turns healthy); `Ensure-CcoEngine` and `claude.ps1` still accept the log line `Loaded GGUF model via llama-server` as readiness, so a wrong health check cannot block a session.
- The Claude Code container is deliberately outside compose (D24), so "the stack" under `docker compose` is the engine; `claude.ps1` is the one-command entry into a session.

## D26. Engine lifecycle follows the Claude Code session (step 21)
- `claude.ps1` stops the engine when Claude Code exits (also after Ctrl+C), unless another `cco-claude-*` container is running, in which case it leaves the engine up. `-KeepEngine` keeps the engine running, which keeps the engine's prompt cache and makes the next start quick; `up.ps1` and `down.ps1` remain for manual control.
- Trade-off: stopping loses the prompt cache, so the first message of the next session needs about a minute of prompt processing again (bare mode); closing the console window abruptly cannot run the cleanup, so `down.ps1` stays the fallback.

## D27. Claude Code modes (step 22)
- `bare`: `CLAUDE_CODE_SIMPLE=1`; tools Bash, Read, Edit; about 1,000 tokens; an appended instruction tells the model to create new files with Bash (heredoc) and change files with Edit. Default.
- `lean`: normal mode with `--tools Bash,Read,Edit,Write` and git instructions off; about 3,000 tokens; an appended instruction names the Write and Edit tools.
- `full`: normal mode, all tools; about 17,000 tokens; kept for faster hardware.
- Selected with `CCO_CLAUDE_MODE` in `config/.env` or `claude.ps1 -Mode`. Common settings are in `docker/claude/claude.env`, mode settings in `docker/claude/mode-<mode>.env`.
- `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off` is set for all modes because the `<total_tokens>` line near the end of the normal-mode system prompt may change between turns and would invalidate the engine's prefix cache; its effect is checked from the llama-server prompt timings in the file-creation test.

## D28. Mode comparison (step 22)
- `bare`: about 1,060 prompt tokens, 87 s for a create-two-files task; files are written through Bash. `lean`: about 2,700 prompt tokens, 191 s; files are written with the Write tool. The cold-start cost of each session (engine freshly started) is about 1 minute for `bare` and about 2.5 minutes for `lean`.
- The default mode is the owner's choice (`CCO_CLAUDE_MODE`); `bare` stays the default until a choice is made. `full` is not practical on the reference machine.

## D29. Sampling temperature and tool-call reliability (step 24)
- Reported by the owner (interactive use): in `lean` mode the model sometimes answers with a chat message instead of a tool call. The conformance test (10/10) and the two file-creation runs did not show it, so the failure is probabilistic.
- `unsloth run --temperature` pins the sampling temperature server-side for requests that omit it (Claude Code sends none). It is exposed as `CCO_ENGINE_TEMPERATURE` (default 0.7, the model's usual default, to be confirmed against Unsloth's per-model value); 0.2 is expected to be steadier for tool use.
- `scripts/windows/test-tool-reliability.ps1` repeats the same create-and-edit task per mode and temperature and prints the answer text of every failure.

## D30. Upgrade and rollback model (step 27)
- The engine and Claude Code images track the latest releases (D10). Each build records its resolved version inside the image (`/home/cco/.cco-versions`) and leaves a snapshot tag with that version; the floating tag is what compose and the scripts use.
- `upgrade.ps1` validates the configuration, rebuilds without cache, compares versions and, if a newer version arrived, runs a gate (engine: conformance test and file-creation test; Claude Code: end-to-end entry test and file-creation test). A failed gate points the floating tag back at the previous snapshot automatically. Successful upgrades are logged in `docs/01-build-log/upgrades.md`.
- `rollback.ps1` lists snapshots and retags the floating tag to any kept version; nothing is rebuilt.
- `validate-config.ps1` checks configuration values, repository files, Docker state and the safety settings (internal network, no published ports, server-side tools disabled, `.env` git-ignored).
- Model swap stays a configuration change plus `download-model.ps1` plus the same gate tests.

## D31. Install and uninstall (step 28)
- `install.ps1` takes a machine with a running Docker engine to a working stack: prerequisite checks, `Ensure-CcoEnv` (creates `config/.env` from the example and generates `CCO_STUDIO_PASSWORD`), engine image, Claude Code image, model download with checksum verification, configuration validation, an end-to-end Claude Code session and a tool-calling conformance run; it prints a timing table. `-NoCache` rebuilds the images without Docker's layer cache.
- `Ensure-CcoEnv` is also called whenever the engine starts, so a fresh checkout does not fail on the missing password.
- `uninstall.ps1` removes only named project resources: containers `cco-*`, network `cco_net`, volumes `cco_claude_home` and `cco_workspace` (and `cco_models` with `-RemoveModel`), images `cco-engine` and `cco-claude` (all tags, so the rollback snapshots go too), and `config/.env` with `-RemoveConfig`. It never prunes, and compares the other running containers before and after.