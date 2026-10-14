# Steps 24-26 - Tool-call reliability and the session viewer

**Goal:** investigate the owner's report that `lean` mode sometimes answered with a chat message instead of a tool call.

**What was done:** `test-tool-reliability.ps1` (20 of 20 runs passed in print mode; see step 24), `show-last-session.ps1` with `tests/transcript/summarize.py` (lists the config volume, prints the prompt history and summarizes session transcripts if any), and `down.ps1` now removes leftover `cco-claude-*` containers.

**Result:** the owner reproduced the problem once interactively in a real project, the viewer found only `history.jsonl` (no message transcripts are kept in this setup), and afterwards the owner reported that it works properly. The cause was not identified; the reliability test, the viewer and the `CCO_ENGINE_TEMPERATURE` setting stay available if it returns.