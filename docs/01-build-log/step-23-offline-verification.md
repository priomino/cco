# Step 23 - Offline verification (host network switched off)

**Goal:** show that the whole stack works with the host's network actually switched off.

**What was done:** `scripts/windows/verify-offline.ps1` checks that DNS, TCP and HTTPS are unreachable from the host, starts the engine, runs a Claude Code session on a demo folder and scans the engine log for outbound attempts. The owner also tested by hand.

**Result (reported by the owner, not captured by the script):** with the host network switched off, Claude Code works, including interactive sessions. Together with the internal compose network (step 17, verified: no route to the internet from the Claude Code container), this covers the offline requirement.