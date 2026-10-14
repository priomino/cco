# Step 13 - CPU thread / flash-attention sweep

**Goal:** find out whether CPU settings (threads, flash attention) or power state explain the slow prompt processing seen in step 12.

**What was done:** a first attempt with `llama-bench` measured nothing because the Unsloth llama.cpp bundle does not ship that executable (see troubleshooting). `scripts/windows/cpu-sweep.ps1` v2 then started `llama-server` directly in a throwaway container for each configuration, sent the same 576-token prompt (32 generated tokens, prompt cache off) and read llama-server's own timings, while sampling host CPU performance counters.

**Conditions:** AC power, 100% charge; Windows scheme "Balanced" with the power-mode overlay set to what appears to be "Best performance" (GUID `ded574b5-45a0-4f42-8737-46345c09c238`, mapping from memory); single runs, no repetition; Process Explorer using about one core.

**Result (as reported, exit 0):**

| Threads | Flash attention | Prefill tokens/s | Generation tokens/s |
|---|---|---|---|
| 4 | off | 15.8 | 5.6 |
| 6 | off | 17.2 | 5.8 |
| 8 | off | 16.1 | 5.2 |
| 12 | off | 16.0 | 0.71 |
| 4 | on | 14.6 | 4.7 |
| 6 | on | 15.8 | 5.6 |
| 8 | on | 20.8 | 6.0 |
| 12 | on | 17.3 | 0.75 |

Host sampler (106 samples): effective CPU performance 123-246% of base, about 181-186% (around 3.3 GHz) during sustained load, no downward trend. The VM reports 6 cores x 2 threads and CPU flags avx, avx2, avx_vnni, f16c, fma.

**Conclusions:** sane thread counts (4-8) give 15-21 tokens/s prefill and 5-6 tokens/s generation; 12 threads collapses generation to under 1 token/s; no throttling decay observed. Limit of the CPU path is therefore about 15-21 tokens/s prefill. Next: the iGPU attempt.