# Step 14 - iGPU feasibility, attempt 1: Vulkan through Mesa dzn

**Goal:** check whether a container can see the Intel Iris Xe through Vulkan (Mesa `dzn`, Vulkan over Direct3D 12 via `/dev/dxg`), the GPU path Unsloth documents for Intel GPUs.

**What was done:** `scripts/windows/probe-igpu-vulkan.ps1` ran `tests/igpu-probe/vulkan-probe.sh` as root in a throwaway `ubuntu:24.04` container with `--device /dev/dxg`, `-v /usr/lib/wsl:/usr/lib/wsl` and `LD_LIBRARY_PATH=/usr/lib/wsl/lib`, installing `mesa-vulkan-drivers`, `vulkan-tools` and `libvulkan1` from Ubuntu.

**Result (as reported, exit 0):**
- Installed: mesa-vulkan-drivers 25.2.8-0ubuntu0.24.04.4, vulkan-tools 1.3.275, libvulkan1 1.3.275.
- Vulkan ICD files present: asahi, gfxstream_vk, intel_hasvk, intel, lvp, nouveau, radeon, virtio. No `dzn` ICD and no dzn library.
- `/dev/dxg` present; `libd3d12.so`, `libd3d12core.so`, `libdxcore.so` present.
- `vulkaninfo` lists one device: llvmpipe (software renderer on the CPU).

**Conclusion:** the first iGPU step failed its gate cleanly: Ubuntu's Mesa is built without `dzn`. The `cpu` profile remains the default. One iGPU step remains in the budget.