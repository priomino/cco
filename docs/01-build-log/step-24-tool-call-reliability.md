# Step 24 - Tool-call reliability test

**Goal:** after the owner reported that `lean` mode sometimes answers with a chat message instead of a tool call, measure how often Claude Code really creates and edits files, per mode and engine temperature.

**What was done:** `CCO_ENGINE_TEMPERATURE` (default 0.7) passed as `unsloth run --temperature` in `docker/compose.yaml`; `scripts/windows/test-tool-reliability.ps1` runs the same task five times per mode and temperature in print mode on a bind-mounted folder (task: create `hello.py` that prints hello world, and replace `foo` by `bar` in `notes.txt`; a run passes only if both happened).

**Result (as reported, exit 0):** 20 of 20 runs passed.

| Temperature | bare | lean |
|---|---|---|
| 0.7 | 5/5, average 44 s | 5/5, average 67 s |
| 0.2 | 5/5, average 46 s | 5/5, average 68 s |

The first run of each mode took about 90 s (`bare`) or 191 s (`lean`); later runs 30-40 s (prefix cache). The reported failure was not reproduced: the test is single-turn, non-interactive, with edits pre-approved. Candidate differences: interactive permission prompts, longer conversations, different wording. Script issues: the printed engine command line failed because of nested quotes (fixed in step 25), and `cco_net` stayed "in use" because a Claude Code container had been left behind (fixed in step 25).