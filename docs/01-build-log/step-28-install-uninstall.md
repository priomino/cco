# Step 28 - Install, uninstall and the clean-reinstall test

**Goal:** show that a fresh setup works with one command and measure it.

**What was done:** `Ensure-CcoEnv` (creates `config/.env`, generates `CCO_STUDIO_PASSWORD`; called when the engine starts), `install.ps1`, `uninstall.ps1` (architecture D31). Test: `uninstall.ps1 -RemoveModel -RemoveConfig`, then `install.ps1 -NoCache`.

**Result (as reported):** the uninstall removed three volumes, six image tags (four images) and `config\.env`, left no containers, and left the other containers unchanged. The install finished in 1,123 s (18.7 minutes): engine image 247 s, Claude Code image 107 s, model download 534 s, validation 2 s, end-to-end test 132 s, conformance test 101 s. The fresh build picked up Unsloth 2026.10.5 and Claude Code 2.1.299, and both passed the tests. The goal of a quick start under 10 minutes was not met; the time is download and build time.