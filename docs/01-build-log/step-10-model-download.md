# Step 10 - Model download into a Docker volume

**Goal:** put the model into the volume `cco_models` and verify it against the checksum published by Hugging Face.

**What was done:** `scripts/windows/download-model.ps1` queries the Hugging Face API for the expected size and SHA-256, starts a throwaway container from the engine image (as root, network on) that downloads with `curl -C -` into `/models`, polls progress, then verifies the SHA-256 in a second container.

**Command:** `powershell -ExecutionPolicy Bypass -File .\download-model.ps1`

**Result (as reported, exit 0):** `Qwen2.5-7B-Instruct-Q4_K_M.gguf`, 4,683,074,240 bytes, SHA-256 `65b8fcd92af6b4fefa935c625d1ac27ea29dcb6ee14589c55a8f115ceaaa1423`, verified. About 530 s for the download (roughly 8 MiB/s). Free space on C. went from 28.2 GiB to 23.8 GiB.