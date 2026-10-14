# Step 01 - Environment audit

**Goal:** capture facts about the host, WSL2 and the container runtime before making decisions.

**What was done:** a read-only PowerShell audit (`scripts/windows/audit.ps1`) run as a file. A first version failed (see troubleshooting: pasted script, format-string bug); the corrected script passed.

**Command:** `powershell -ExecutionPolicy Bypass -File .\audit.ps1`

**Result (as reported):**
- Windows 11 Pro 25H2 (build 26200.9457); Intel Core i7-1265U (10 cores / 12 threads); 31.4 GB RAM; Intel Iris Xe, driver 32.0.101.7084.
- WSL 2.6.3.0, kernel 6.6.87.2-1; `/dev/dxg` and `libd3d12`/`libdxcore` present in the Rancher Desktop distro; no `.wslconfig`.
- Container runtime: Rancher Desktop 1.22.0 with moby engine (not Docker Desktop). Docker VM reports 12 CPUs and about 15.3 GB (WSL2 default of about half of host RAM).
- C: had about 24.7 GB free of 235 GB, the tightest resource.

**Decisions taken:** keep Rancher Desktop (architecture D2). Proxy-strategy choice postponed to Phase 3 (D4).