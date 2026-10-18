# Changelog

## [1.0.1] - 2026-10-18
- Fixed: gitattributes now forces LF line endings, so a clone on Windows no longer breaks docker/claude/entrypoint.sh.
- Fixed: the request-size stub test no longer uses a key-shaped dummy token (release check false positive).

## [1.0.0] - 2026-10-14

First release. Windows 11, CPU only.

### Added
- Engine container (Unsloth, GGUF-only, prebuilt llama.cpp for CPU) built by `build-engine.ps1`; model Qwen2.5-7B-Instruct Q4_K_M downloaded into the volume `cco_models` and verified by SHA-256 (`download-model.ps1`).
- Compose stack with an internal network (no route to the internet), no published ports, server-side tools disabled and a health check that means "model loaded".
- Claude Code container built from the official native installer, configured for offline use (telemetry, updates and non-essential traffic off; timeouts raised for slow prompt processing); modes `bare` (default), `lean` and `full`.
- One-command entry point `claude.ps1` with `up.ps1` and `down.ps1`: bind-mounted Windows project folders, the engine key passed without appearing on a command line, the engine stopping with the session.
- Tests: tool-calling conformance (structure and semantics, streaming included), file creation, tool-call reliability, end to end, up/down acceptance, offline verification.
- `install.ps1`, `uninstall.ps1`, `validate-config.ps1`, `upgrade.ps1` (gate tests and automatic rollback) and `rollback.ps1`; automatic generation of the engine password.
- Documentation: architecture decisions D1 to D31 with rejected alternatives, a step-by-step build log, troubleshooting from the problems actually met, known limitations with measured numbers, and a roadmap.

### Not included
- GPU acceleration (no usable Vulkan driver for the integrated GPU in the container), macOS and Linux hosts, access to the engine from the host, parallel Claude Code sessions. See `docs/07-roadmap.md`.

## v1.1.0 (in progress)
- Parameter inventory of llama-server, Unsloth and Claude Code (build log step 30); environment pass-through experiment (step 31).
- Unsloth extra-arguments mechanism found by source scan (build log step 32); load schema inspection (step 33).