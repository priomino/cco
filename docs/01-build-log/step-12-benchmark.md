# Step 12 - Benchmark with realistic prompt sizes

**Goal:** measure prompt-processing (prefill) and generation speed on long prompts and the effect of prompt caching.

**What was done:** `tests/engine-bench/bench.sh` (runs inside the engine container) driven by `scripts/windows/engine-bench.ps1`. The first attempt crashed the Windows docker client under host memory pressure (see troubleshooting); the script was hardened (retries, memory reporting) and re-run after closing heavy applications.

**Command:** `powershell -ExecutionPolicy Bypass -File .\engine-bench.ps1`

**Result (as reported, exit 0; CPU profile, 32768 context, Qwen2.5-7B-Instruct Q4_K_M):**
- Model load: 33 s.
- Prompt of 1,864 tokens: 159 s (11.7 tokens/s); generation 3.3 tokens/s.
- Prompt of 7,327 tokens: 701 s (10.5 tokens/s); generation 1.9 tokens/s at that context. The 16,000-token size was skipped by the 400 s rule.
- Second turn on the same 7.3k prefix with a different last question: 7.9 s total, only 14 prompt tokens evaluated (the prefix cache works).
- Generation at short context: 154 tokens in 37.7 s (4.1 tokens/s).
- Memory: engine container 7.3 GiB; free Windows commit fell from 10.0 GiB to 1.2 GiB during the load.
- Conclusion: prefill, not generation, limits agent-style use; the first message of a Claude Code session may take tens of minutes unless prefill speed improves (next: thread/power diagnostics, then the iGPU).