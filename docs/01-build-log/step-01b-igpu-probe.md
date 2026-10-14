# Step 01b - iGPU passthrough probe on Rancher Desktop

**Goal:** check whether a container can see and use the Intel Iris Xe before choosing the runtime.

**What was done:** `scripts/windows/probe-igpu.ps1` starts throwaway `ubuntu:24.04` containers with `--device /dev/dxg` and `-v /usr/lib/wsl:/usr/lib/wsl`, then (A) checks the device and WSL libraries, (B) installs `clinfo` and `intel-opencl-icd` inside the container and lists OpenCL devices. Every external call has a timeout.

**Command:** `powershell -ExecutionPolicy Bypass -File .\probe-igpu.ps1`

**Result (as reported, exit code 0):**
- Stage A PASS: `/dev/dxg`, `libd3d12.so`, `libd3d12core.so`, `libdxcore.so` visible.
- Stage B PASS: `clinfo` listed `Intel(R) Graphics [0x46a8]`, type GPU, 96 compute units, 14.34 GiB global memory (shared system memory, no separate VRAM). Package: `intel-opencl-icd` 23.43.27642.40 from Ubuntu 24.04.

**What this does not prove:** that the Unsloth engine can use the GPU. Its Intel path is Vulkan (architecture D5), which is a separate check in Phase 2.

**Issues:** the first probe hung at the daemon check (see troubleshooting: docker CLI hang). A hardened version with timeouts was used.