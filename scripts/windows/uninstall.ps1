# uninstall.ps1 - remove this project's containers, network, volumes and images. Nothing else is touched (no prune).
# Usage: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 [-Yes] [-RemoveModel] [-RemoveConfig]
#   -RemoveModel  also deletes the model volume cco_models (a 4.4 GB download to get back)
#   -RemoveConfig also deletes config\.env (including the generated engine password)
param([switch]$Yes, [switch]$RemoveModel, [switch]$RemoveConfig)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'uninstall-report.txt') -Force | Out-Null
function Lines([string]$argline) {
  $r = Run-Docker $argline 60 $null 3
  return @(($r.Text -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}
function Finish([int]$code, [string]$msg) {
  Write-Host ""
  Write-Host "RESULT: UNINSTALL_RESULT=$msg EXIT=$code"
  Write-Host "=== UNINSTALL COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering; nothing was changed.'; Finish 2 'DOCKER_DOWN' }
$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$eimg = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
$cimg = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }

Section 'What will be removed'
$otherBefore = (Lines 'ps --format "{{.Names}}"' | Where-Object { $_ -notlike 'cco-*' } | Sort-Object) -join ','
$containers = @(Lines 'ps -a --format "{{.Names}}"' | Where-Object { $_ -like 'cco-*' })
$networks = @(Lines 'network ls --format "{{.Name}}"' | Where-Object { $_ -eq 'cco_net' })
$wantVols = @('cco_claude_home', 'cco_workspace'); if ($RemoveModel) { $wantVols += 'cco_models' }
$volumes = @(Lines 'volume ls -q' | Where-Object { $wantVols -contains $_ })
$imgLines = @(Lines 'images --format "{{.Repository}}:{{.Tag}} {{.ID}}"' | Where-Object { $_ -like "${eimg}:*" -or $_ -like "${cimg}:*" })
$imageIds = @($imgLines | ForEach-Object { ($_ -split ' ')[-1] } | Sort-Object -Unique)
"Containers : $(if ($containers.Count) { $containers -join ', ' } else { '(none)' })"
"Network    : $(if ($networks.Count) { $networks -join ', ' } else { '(none)' })"
"Volumes    : $(if ($volumes.Count) { $volumes -join ', ' } else { '(none)' })$(if (-not $RemoveModel) { '   (cco_models is kept; add -RemoveModel to delete it)' })"
"Images     : $(if ($imgLines.Count) { ($imgLines | ForEach-Object { ($_ -split ' ')[0] }) -join ', ' } else { '(none)' })"
"Config     : $(if ($RemoveConfig) { 'config\.env will be deleted' } else { 'config\.env is kept' })"
"Other (non-cco) running containers, left alone: $otherBefore"
if (-not $Yes) {
  $a = Read-Host 'Type YES to remove these items'
  if ($a -cne 'YES') { 'Cancelled; nothing was changed.'; Finish 1 'CANCELLED' }
}

Section 'Removing'
foreach ($c in $containers) { "container $c"; Run-Docker "rm -f $c" 60 $null 2 | Out-Null }
foreach ($n in $networks) { "network $n"; Run-Docker "network rm $n" 30 $null 2 | Out-Null }
foreach ($v in $volumes) { "volume $v"; Run-Docker "volume rm $v" 30 $null 2 | Out-Null }
foreach ($i in $imageIds) { "image $i"; Run-Docker "rmi -f $i" 120 $null 2 | Out-Null }
if ($RemoveConfig -and (Test-Path $CcoEnvFile)) { Remove-Item -LiteralPath $CcoEnvFile -Force; 'config\.env deleted' }

Section 'Check'
$leftC = @(Lines 'ps -a --format "{{.Names}}"' | Where-Object { $_ -like 'cco-*' })
$leftV = @(Lines 'volume ls -q' | Where-Object { $wantVols -contains $_ })
$leftI = @(Lines 'images --format "{{.Repository}}"' | Where-Object { $_ -eq $eimg -or $_ -eq $cimg })
$otherAfter = (Lines 'ps --format "{{.Names}}"' | Where-Object { $_ -notlike 'cco-*' } | Sort-Object) -join ','
"Left over: containers=$($leftC.Count) volumes=$($leftV.Count) images=$($leftI.Count)"
"Other containers unchanged: $($otherBefore -eq $otherAfter)  (before=[$otherBefore] after=[$otherAfter])"
"Free disk on C: $([math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)) GiB (Docker's disk image does not shrink by itself, so this rarely goes up)"
if ($leftC.Count -eq 0 -and $leftV.Count -eq 0 -and $leftI.Count -eq 0 -and ($otherBefore -eq $otherAfter)) { Finish 0 'OK' } else { Finish 1 'INCOMPLETE' }