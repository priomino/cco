# Step 21 - Tool-set probe (stub server, no engine) and engine stop on exit

**Goal:** understand why interactive Claude Code printed files instead of saving them in bare mode, and make the engine stop with the session.

**What was done:** `claude.ps1` now stops the engine when the session ends (unless another `cco-claude-*` container runs; `-KeepEngine` keeps it); `tests/claude-request-size/measure.sh` was extended with `CLAUDE_FLAGS` and a `system_tail` field; `scripts/windows/claude-tools-probe.ps1` measured four configurations against the stub server.

**Result (as reported, exit 0; Claude Code 2.1.295; token counts are characters / 3.5 estimates):**

| Configuration | Tools sent | Request bytes | Estimated tokens |
|---|---|---|---|
| bare | Bash, Edit, Read | 3,710 | about 960 |
| bare + `--tools Bash,Read,Edit,Write` | Bash, Edit, Read (no change) | 3,710 | about 960 |
| bare + `--tools ... --append-system-prompt-file` | Bash, Edit, Read | 3,972 | about 1,036 |
| normal mode, `--tools Bash,Read,Edit,Write`, git instructions off | Bash, Edit, Read, Write | 10,991 | about 3,040 |
| normal mode, `--tools Bash,Read,Edit,Write,Glob,Grep`, git instructions off | 6 tools | 14,970 | about 4,220 |

- Bare mode has no `Write` tool and `--tools` cannot add one to it.
- Appended text arrives at the end of the system prompt; the base identity line becomes "You are Claude Code, Anthropic's official CLI for Claude...".
- Normal-mode requests end the system prompt with a `<total_tokens>N tokens left</total_tokens>` line, which may change per turn (to be switched off with `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off`, as Unsloth's launcher does).