# Step 16 - Claude Code image and request-size measurement

**Goal:** build the Claude Code container and measure, without the engine and without a network, what Claude Code sends under several settings.

**What was done:** `docker/claude/Dockerfile` (ubuntu:24.04, curl, git, python3, non-root user `cco`, official native installer `curl -fsSL https://claude.ai/install.sh | bash`, tracking the latest release), `scripts/windows/build-claude.ps1`, and `tests/claude-request-size/measure.sh` driven by `scripts/windows/claude-request-size.ps1`: a stub Anthropic-style server in the container logs each request made by `claude -p` (container started with `--network none`).

**Issues on the first run (see troubleshooting):** `python3-minimal` has no standard library; `claude -p` swallowed the rest of the script from stdin.

**Result (as reported, exit 0; Claude Code 2.1.295, image about 0.17 GB reported by Docker):**

| Configuration | Request bytes | Tools | tools / system / messages characters | Estimated tokens | Auth header |
|---|---|---|---|---|---|
| default settings | 60,841 | 20 | 47,909 / 3,626 / 9,897 | about 17,500 | Bearer |
| + `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1` | 59,229 | 20 | 47,518 / 3,626 / 8,660 | about 17,100 | Bearer |
| + `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` | 59,229 | 20 | identical to the previous row (no effect) | about 17,100 | Bearer |
| `CLAUDE_CODE_SIMPLE=1` (bare) | 3,710 | 3 (Bash, Edit, Read) | 3,152 / 93 / 123 | about 960 | Bearer |
| bare, with `ANTHROPIC_API_KEY` | 3,710 | 3 | same | about 960 | `x-api-key`, no Bearer |

Token figures are characters / 3.5 (an estimate). One `/v1/messages?beta=true` request per run; no other paths were requested. Every request carries `thinking`, `output_config` and `metadata` fields. Claude Code printed `[claude-code:unrecognized_model]` on stderr for the local model name (informational). All runs exited 0.