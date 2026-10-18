# Roadmap

- **v1.0:** Windows 11, CPU profile working first, optional iGPU profile, tool-calling conformance gate, offline verification.
- **Next (v1.x or v2):** macOS support through a Docker Model Runner (`dmr`) backend (Compose `models:` element, Metal via vllm-metal), added behind the existing `engine.backend` key without changing Claude Code, tests or docs structure.
- **Later, optional:** revisit iGPU acceleration if it does not pass its gate in v1.0.
- **iGPU acceleration (optional, later):** revisit with a Mesa build that includes `dzn` (Vulkan over Direct3D 12) or with an Intel SYCL / Level Zero build of llama.cpp; both need measurement against the CPU baseline (about 15-21 tokens/s prompt processing).

## Parked by the owner (2026-10-11), to be designed later
1. **Access to Unsloth from the host.** Today nothing is published to the host (architecture D6 and D24, tested in step 20) and the engine runs `--api-only` on an internal network. Design notes: published ports do not work on a Docker network marked `internal`, so the options are a small forwarder container on a second network that publishes `127.0.0.1:<port>` and forwards to the engine (the engine keeps no route out), or attaching the engine to a second, non-internal network (which gives it a route out and works against the offline design). The API key lives inside the container (`.cli_api_key_cli_*`) and would have to be made available to the host tool; the Studio web interface would need the engine to run without `--api-only` and its admin password (`CCO_STUDIO_PASSWORD`). `CCO_DIAG_PORT` is reserved in the configuration but not wired. To clarify first: which host tool needs access (browser interface, editor plugin, another script) and whether localhost-only exposure is enough.
2. **Several Claude Code sessions at the same time** (several projects in parallel, or several sessions on one project). Already in place: unique container names, the engine is kept running while other `cco-claude-*` containers exist, project folders are mounted independently. Constraints: the engine serves one request at a time (`--parallel 1`) with one prompt cache, so concurrent sessions queue and alternating sessions evict each other's cache (each switch can cost 1 to 3 minutes of prompt processing); `--parallel N` divides the 32,768-token context by N; two simultaneous generations share the same CPU cores and memory bandwidth; all sessions share one configuration volume (`cco_claude_home`, with history and settings). Options to evaluate: keep requests serialized and document it, `--parallel 2` with a larger context if the model and memory allow, separate configuration volumes per session.

## Status
v1.0.0 is released (Windows 11, CPU only). Next: macOS through a Docker Model Runner backend; iGPU acceleration if a working route is found; the two parked items above.

## Target: v1.1.0 (planned 2026-10-16; branch v1.1)
Scope, set by the owner after the v1.0.0 release:
1. Host access to Unsloth (parked item 1 above).
2. Several Claude Code sessions at the same time (parked item 2 above).
3. Support for all native Unsloth model-loading parameters (some may need another or a separate model; unsupported-here parameters are kept for the future, with a status).
4. Support for llama.cpp parameters that Unsloth does not expose.
5. Support for all Claude Code run parameters.
6. Claude Code configuration per project it runs.
7. A tuning script: analyse the system, test the parameters found earlier, pick the best-performing model and parameters; the speed target is adjustable (initial target: 10+ tokens per second).

Phases: A inventory of the option surfaces and an experiment on environment-variable pass-through; B engine parameter layer; C Claude Code parameter layer and per-project configuration; D gateway for host access and parallel sessions; E tuner with a mandatory quality gate (tool-calling conformance and file-creation tests); F release. Existing `.env` files and commands must keep working.

Physics note for item 7: generation speed on CPU is limited by memory bandwidth (about 25 GB/s measured, so a 4.4 GB model tops out near 5.7 tokens per second); 10+ tokens per second needs a model that reads about 2.5 GB or less per token (a 3B-class model, a mixture-of-experts model with few active parameters, or speculative decoding). Whether such models still pass the tool-calling gate is to be measured.

### Decisions taken (owner, 2026-10-16)
- Host access means the **Unsloth Studio web interface** only (not the API): the engine is started without `--api-only` when the interface is enabled, and a gateway container on a second network publishes it on 127.0.0.1 only; the engine itself stays on the internal network.
- "t/s" means tokens per second. The tuner has two adjustable targets: generation speed (default 10) and prompt-processing speed (default: measured and reported, no minimum); the generation target decides the selection.
- The tuner's download mode is a setting: `one-by-one` (default: download a candidate, test it, delete it unless it is the best so far) or `all`.
- Scope of per-project settings (Claude Code side only, or also an engine profile per project): pending the owner's choice.