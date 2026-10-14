# Step 11 - First engine start and smoke test

**Goal:** start the engine from the model volume through compose (profile `cpu`, no published ports), read its API key, and send one Anthropic-format and one OpenAI-format request.

**What was done:** `docker/compose.yaml` (service `engine-cpu`), `tests/engine-smoke/smoke.sh`, `scripts/windows/engine-first-run.ps1`. The run script generates `CCO_STUDIO_PASSWORD` into the git-ignored `config/.env`, starts the stack, waits for HTTP, reads the key (masked in output), runs the smoke test inside the container, then stops the stack.

**Command:** `powershell -ExecutionPolicy Bypass -File .\engine-first-run.ps1`

**Result (as reported, exit 0):**
- The web server answered after about 11 s; the model finished loading about 14 s after start (llama-server with flash attention, context 32768, estimated KV cache 1.8 GB; the GGUF reports tool-calling support).
- `/v1/messages` (Anthropic format) and `/v1/chat/completions` (OpenAI format) both returned 200. Prompt of 38 tokens: 14 completion tokens in 4.3 s server-side (first request, includes waiting for the model load) and 12 tokens in 2.2 s (second request, 37 prompt tokens served from cache), roughly 5 tokens/s on this tiny sample.
- Container memory 6.7 GiB of the VM's 15.3 GiB after the requests.
- The API key is cached at `/home/cco/.unsloth/studio/auth/.cli_api_key_cli_<digest>` (43 characters) and also printed in the container log.
- Server-side tools reported as disabled.
- The readiness check passed before the model was loaded (see troubleshooting).