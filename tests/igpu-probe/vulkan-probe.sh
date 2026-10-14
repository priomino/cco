#!/bin/bash
# vulkan-probe.sh - runs as root inside a throwaway ubuntu:24.04 container started with
#   --device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl -e LD_LIBRARY_PATH=/usr/lib/wsl/lib
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq mesa-vulkan-drivers vulkan-tools libvulkan1 >/dev/null 2>&1
echo "apt_exit=$?"
echo "--- packages ---"; dpkg -l | grep -E 'mesa-vulkan-drivers|vulkan-tools|libvulkan1' | awk '{print $2, $3}'
echo "--- ICD files ---"; ls -l /usr/share/vulkan/icd.d/ 2>&1
echo "--- dzn libraries ---"; (ls /usr/lib/x86_64-linux-gnu | grep -i dzn) || echo "no dzn library found"
echo "--- WSL libraries ---"; ls /usr/lib/wsl/lib 2>&1 | head
echo "--- /dev/dxg ---"; ls -l /dev/dxg 2>&1
export LD_LIBRARY_PATH=/usr/lib/wsl/lib:$LD_LIBRARY_PATH
DZN=$(ls /usr/share/vulkan/icd.d/dzn_icd*.json 2>/dev/null | head -1)
if [ -n "$DZN" ]; then
  echo "--- vulkaninfo --summary with the dzn ICD only: $DZN ---"
  VK_ICD_FILENAMES="$DZN" timeout 120 vulkaninfo --summary 2>&1 | head -50
  echo "--- features llama.cpp's Vulkan backend cares about (dzn only) ---"
  VK_ICD_FILENAMES="$DZN" timeout 120 vulkaninfo 2>/dev/null | grep -E 'apiVersion|deviceName|deviceType|driverName|driverInfo|subgroupSize|shaderFloat16|shaderInt16|shaderInt8|storageBuffer16BitAccess|storageBuffer8BitAccess|uniformAndStorageBuffer16BitAccess|maxComputeSharedMemorySize|maxStorageBufferRange|maxMemoryAllocationSize|VK_KHR_16bit_storage|VK_KHR_8bit_storage|VK_KHR_shader_float16_int8|VK_KHR_cooperative_matrix|VK_NV_cooperative_matrix2' | sort -u | cut -c1-140 | head -40
else
  echo "NO_DZN_ICD: the installed Mesa has no dzn Vulkan driver"
fi
echo "--- all ICDs (a software 'llvmpipe' device would be the CPU, not the GPU) ---"
timeout 120 vulkaninfo --summary 2>&1 | grep -E 'deviceName|deviceType|driverName|GPU[0-9]' | head -20
echo VKPROBE_OK