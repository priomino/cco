# Step 27 - Configuration validation, upgrade and rollback

**Goal:** make Claude Code and Unsloth (both tracking the latest releases) safely upgradable.

**What was done:** `scripts/windows/versions.ps1` (helpers), `validate-config.ps1`, `rollback.ps1`, `upgrade.ps1` (see architecture D30).

**Result (as reported):**
- `validate-config.ps1`: 28 checks OK, 0 failures.
- `rollback.ps1 -Component claude`: listed the snapshots 2.1.294 and 2.1.295 and switched between them, verified both ways.
- First `upgrade.ps1` run reported "unchanged" but had not rebuilt: array splatting passed `-Upgrade` as plain text (see troubleshooting). After switching to hashtable splatting the upgrade ran for real: Claude Code 2.1.295 to 2.1.296, gate (end-to-end test and bare file-creation test, 95 s) passed, logged in `docs/01-build-log/upgrades.md`. `-SimulateFailure` ended `ROLLED_BACK` with exit code 1 as designed.