# Step 08 - Engine CLI reference and switches (read-only, no network)

**Goal:** read the complete options of `unsloth run`, `unsloth studio` and `unsloth start`, and find API-key handling and offline switches.

**What was done:** `scripts/windows/probe-engine-cli.ps1` ran a throwaway container from `cco-engine:cpu` with `--network none` and printed the full help texts plus code searches.

**Result (as reported, exit 0):**
- `unsloth studio run` starts the server, loads a model and prints an API key; the key is reused per label (`--api-key-name`, default `cli`). An initial admin password can be set with `--password` or `UNSLOTH_STUDIO_PASSWORD`.
- Server-side tools (web search, code execution) are on by default for every bind; `--disable-tools` forces them off.
- `--parallel` defaults to 4; each slot gets context/N of the KV cache.
- Tool-call healing and nudging are on by default (`--disable-tool-call-healing` is a kill switch).
- Sampling can be pinned server-side (`--temperature`, `--top-p`, `--top-k`, `--min-p`, penalties); `--speculative-type` defaults to auto; `--context-length` 0 means the model default.
- Environment switches present in code include `UNSLOTH_OFFLINE`, `UNSLOTH_LLAMA_CPP_OFFLINE`, `UNSLOTH_DISABLE_UPDATE_CHECK`, `UNSLOTH_DISABLE_STATISTICS`, `UNSLOTH_DISABLE_XET`, `UNSLOTH_HELPER_MODEL_DISABLE`. The search output was capped at 60 lines, so `UNSLOTH_STUDIO_*` names were not seen.
- `~/.unsloth/studio` holds `cache` (1.6 GB uv cache, apparently hard-linked into the venv), `unsloth_studio` (venv, 71 MB by du), `share`, and three hidden `.venv_t5_*` environments (transformers 5.1/5.3/5.5) whose size was not measured.
- No analytics libraries found in the Studio code (one probable false positive in a diffusion source file). `ANTHROPIC_BASE_URL` does not appear in the Studio code searched, so the code behind `unsloth start claude` lives elsewhere.

**Open:** exact name of the public-IP-check switch, where the API key is stored and how to supply it, what `UNSLOTH_HELPER_MODEL_DISABLE` controls, size of the `.venv_t5_*` environments.