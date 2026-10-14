# Step 22 - Claude Code modes and the file-creation test

**Goal:** make Claude Code save new files (reported problem), and turn the tool-set options into named modes.

**What was done:** `docker/claude/claude.env` (common settings, now including `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=off`), `mode-bare.env`, `mode-lean.env`, `mode-full.env`, `claude.ps1` v3 (`-Mode`, `CCO_CLAUDE_MODE`, appended instructions per mode, engine stops with the session), and `scripts/windows/test-file-creation.ps1`, which runs the same request ("create hello.py ... and todo.md with three bullet points") in `bare` and `lean` mode on bind-mounted Windows folders and checks the files on Windows.

**Issues on the way (see troubleshooting):** a `$mode:` variable-reference syntax slip; the first run was started from PowerShell ISE, which aborted at the first stderr line of a child process; print mode now runs `docker start` through `cmd.exe` with the error stream merged and drops the informational `unrecognized_model` notice.

**Result (as reported, normal console, exit 0):**

| | bare | lean |
|---|---|---|
| total time for the task | 87 s | 191 s |
| first request | 1,064 tokens in 51.6 s (20.6 tokens/s) | 2,709 tokens in 148.5 s (18.2 tokens/s) |
| follow-up request | 40 new tokens in 2.7 s | 77 new tokens in 5.6 s |
| files on Windows | hello.py with `print`, todo.md with 3 bullets | same |

The follow-up requests evaluated only a few dozen new tokens, so the prefix cache stays intact in both modes. Estimates (characters / 3.5) were 1,036 and 3,044 tokens against 1,064 and 2,709 measured.