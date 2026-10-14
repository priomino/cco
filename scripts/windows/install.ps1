# install.ps1 - from "Docker is running" to a working stack: images, model, validation, end-to-end test.
# Usage (normal PowerShell window): powershell -ExecutionPolicy Bypass -File .\install.ps1 [-SkipTests] [-NoCache]
#   -NoCache rebuilds the images without Docker's layer cache (what a clean machine would do).
# Needs the internet (image builds and the model download, about 6 GiB). Run it again safely: finished parts are reused.
param([switch]$SkipTests, [switch]$NoCache)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'install-report.txt') -Force | Out-Null
$t0 = Get-Date
$script:phases = New-Object System.Collections.ArrayList
$script:failedAt = ''
function Finish([int]$code) {
  $total = [int]((Get-Date) - $t0).TotalSeconds
  Write-Host ""
  Write-Host "=== TIMINGS ==="
  $script:phases | ForEach-Object { Write-Host $_ }
  Write-Host ("total {0} s ({1:N1} minutes)" -f $total, ($total / 60))
  if ($code -eq 0) {
    Write-Host ""
    Write-Host "Installed. Start Claude Code from your project folder with:"
    Write-Host "  powershell -ExecutionPolicy Bypass -File $here\claude.ps1"
    Write-Host "RESULT: INSTALL_RESULT=OK TOTAL_SECONDS=$total EXIT=0"
  } else {
    Write-Host "RESULT: INSTALL_RESULT=FAILED FAILED_AT=$script:failedAt TOTAL_SECONDS=$total EXIT=$code"
  }
  Write-Host "=== INSTALL COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}
function Phase([string]$name, [string]$script, [hashtable]$scriptArgs = @{}) {
  Section $name
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & (Join-Path $here $script) @scriptArgs | Out-Host
  $rc = $LASTEXITCODE
  [void]$script:phases.Add(("{0,-36} exit {1}  {2,5} s" -f $name, $rc, [int]$sw.Elapsed.TotalSeconds))
  if ($rc -ne 0) { $script:failedAt = $name }
  return $rc
}

Section 'Prerequisites'
"Host memory: $(Mem)"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) {
  'Docker is not answering. Install and start Rancher Desktop (container engine: dockerd / moby) or Docker Desktop with the WSL 2 backend, then run this again.'
  $script:failedAt = 'Docker not running'; Finish 2
}
"Docker engine: $($r.Text.Trim())"
$freeC = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
"Free disk on C: $([math]::Round($freeC, 1)) GiB (about 12 GiB are needed)"
if ($freeC -lt 12) { 'Not enough free disk space on C:.'; $script:failedAt = 'disk space'; Finish 4 }
$ramGb = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
"Installed memory: $([math]::Round($ramGb, 1)) GiB (16 GiB or more recommended; the engine uses about 7 GiB)"
if ($ramGb -lt 15) { 'WARNING: less than 16 GiB of memory; loading the model may fail or be very slow.' }
[void](Ensure-CcoEnv)

$build = @{}; if ($NoCache) { $build = @{ Upgrade = $true } }
if ((Phase 'Build the engine image' 'build-engine.ps1' $build) -ne 0) { Finish 1 }
if ((Phase 'Build the Claude Code image' 'build-claude.ps1' $build) -ne 0) { Finish 1 }
if ((Phase 'Download and verify the model' 'download-model.ps1') -ne 0) { Finish 1 }
if ((Phase 'Validate the configuration' 'validate-config.ps1') -ne 0) { Finish 1 }
if (-not $SkipTests) {
  if ((Phase 'End-to-end test (Claude Code session)' 'test-claude-entry.ps1') -ne 0) { Finish 1 }
  if ((Phase 'Tool-calling conformance test' 'conformance.ps1' @{ Repeat = 1 }) -ne 0) { Finish 1 }
}
Finish 0