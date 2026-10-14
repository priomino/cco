# up.ps1 - start the engine (if needed), wait until the model is loaded and the container reports healthy.
# Usage: powershell -ExecutionPolicy Bypass -File .\up.ps1
# Exit codes: 0 ready and healthy; 1 engine not ready; 2 Docker not answering; 4 model loaded but the health check did not turn healthy.
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Section 'Engine'
"Host memory: $(Mem)"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering. Start Rancher Desktop (dockerd / moby engine) and try again.'; exit 2 }
if (-not (Ensure-CcoEngine 300)) { exit 1 }
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$h = ''
while ($sw.Elapsed.TotalSeconds -lt 180) {
  $h = Get-CcoHealth
  if ($h -eq 'healthy') { 'Engine health: healthy. Stop it with down.ps1 when you are done.'; exit 0 }
  "[{0,4}s] engine health: {1}" -f [int]$sw.Elapsed.TotalSeconds, $h
  Start-Sleep -Seconds 10
}
"WARNING: the model is loaded but the health check says '$h'. The engine is usable; the health check needs attention."
exit 4