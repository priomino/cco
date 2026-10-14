# Known limitations

An honest list, with the numbers that were measured on the reference machine (Intel Core i7-1265U, 31.4 GiB RAM, Windows 11, Rancher Desktop with a 15.3 GiB / 12-CPU Docker VM, CPU profile, Qwen2.5-7B-Instruct Q4_K_M, 32,768-token context).

## Performance
- Prompt processing about 18 to 21 tokens per second; generation about 4 to 6 tokens per second (about 2 tokens per second after a 7,000-token prompt). The best CPU setting found was 8 threads with flash attention (about 21 / 6); using all 12 threads collapses generation to under 1 token per second.
- First message of a session with a freshly started engine: `bare` mode about 1,060 prompt tokens, about 52 to 63 s; `lean` mode about 2,700 tokens, about 150 s; `full` mode about 17,000 tokens (estimate), about 15 minutes. Later requests reuse the prefix cache and process only new tokens (40 to 77 tokens, 3 to 6 s).
- A three-step task (read, edit, report) took about 90 s in `bare` mode.
- Engine start 22 to 35 s. Installation 18.7 minutes (a 4.4 GB download and two image builds).
- The model is a 7B model: much weaker than hosted Claude models. Tool calling passed the conformance test (structure and semantics) and the file-creation tests, and was reported to work in interactive use, but an occasional answer in prose instead of a tool call was reported once and not explained.

## Features that are not available
- No GPU: the integrated graphics are not used. Ubuntu 24.04's Mesa has no `dzn` Vulkan driver, so containers see only a software renderer (see the roadmap for the remaining options).
- Bare mode (the default) offers only the Bash, Read and Edit tools and no CLAUDE.md, hooks, skills, MCP servers, subagents or auto memory; `lean` adds Write; `full` is not practical on CPU.
- One request at a time (`--parallel 1`) and one prompt cache: several Claude Code sessions at once queue up and evict each other's cache (parked item in the roadmap).
- The engine is not reachable from the host (by design; parked item in the roadmap).
- Windows only; no macOS, no Linux host, no NVIDIA/AMD GPUs.

## Platform and operation
- Windows bind mounts appear inside the container as `drwxrwxrwx root root`: permissions are not preserved or enforced, file operations on them are slower than on container volumes, and Windows (CRLF) line endings can make multi-line edits fail to match.
- All scripts must be run from a normal PowerShell window or Windows Terminal; PowerShell ISE is not supported.
- Memory: loading the model needs about 9 GiB of Windows commit; with little headroom the Windows docker client can crash (see troubleshooting). The Docker VM keeps its memory for a while after the engine stops.
- Free disk space on the host fluctuates for reasons unrelated to this project (13 to 28 GiB free was observed within a day). Docker's disk image does not shrink by itself, and every engine or Claude Code build leaves a snapshot image for rollback (about 2 GB per engine version); remove old ones, see docs/04-upgrading.md.

## Versions and dependencies
- Unsloth and Claude Code track the latest releases by default, so behaviour can change after an upgrade (`upgrade.ps1` runs gate tests and rolls back automatically). Unsloth Studio is labelled beta. Transitive dependencies and the llama.cpp bundle are not locked.
- Claude Code reports the local model as "unrecognized" on stderr (informational) and assumes a 200K context window unless told otherwise (`CLAUDE_CODE_MAX_CONTEXT_TOKENS` is set).