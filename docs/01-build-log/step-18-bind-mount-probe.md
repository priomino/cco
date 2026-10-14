# Step 18 - Bind-mount probe (Windows project folders)

**Goal:** find out which path notation the engine inside Rancher Desktop accepts for bind-mounting a Windows folder, and whether the container user can write to it.

**What was done:** `scripts/windows/probe-bind-mount.ps1` created a small test folder, then started throwaway containers from the Claude Code image (uid 1000) with `--mount type=bind,source=<path>,target=/ws` in four notations and checked read, write and whether the new file appears on Windows. An optional read-only listing of a user folder was available but skipped (a placeholder path was passed).

**Result (as reported, exit 0):**
- `C:\projects\cco-bind-test` (plain Windows path) and `/mnt/c/projects/cco-bind-test`: read and write work, the file written by the container appears on Windows; `/ws` shows as `drwxrwxrwx root root`.
- `//c/...` and `/c/...`: `bind source path does not exist`.
- Decision: use the plain Windows path with `--mount type=bind,...`.