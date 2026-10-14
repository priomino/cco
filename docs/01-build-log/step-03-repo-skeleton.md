# Step 03 - Repository skeleton

**Goal:** create the approved repository layout and move the proven scripts into it.

**What was done:** `scaffold.ps1` created the tree under the repo root, copied `audit2.ps1` to `scripts/windows/audit.ps1` and `igpu-probe2.ps1` to `scripts/windows/probe-igpu.ps1`, and wrote the first docs (architecture, build log for steps 01/01b, configuration reference, troubleshooting, limitations, roadmap), `.gitignore`, `config/` examples, `README.md` and `CHANGELOG.md`.

**Command:** `powershell -ExecutionPolicy Bypass -File .\scaffold.ps1`

**Result (as reported):** 22 files written, 0 skipped, `SCAFFOLD OK files=22`.

**Issue on the first attempt:** the scaffold stopped with "Missing source script" because the two earlier scripts had been pasted into the console and never saved as files (see troubleshooting). A restore script recreated them as real files, after which the scaffold passed unchanged.

**Not created yet:** `LICENSE` (chosen in the publish-readiness phase), a git repository, compose files.