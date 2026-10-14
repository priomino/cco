# test-up-down.ps1 - Step 20: acceptance test for up.ps1 / down.ps1.
# Usage: powershell -ExecutionPolicy Bypass -File .\test-up-down.ps1
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'test-up-down-report.txt') -Force | Out-Null
$script:fails = 0
function Check([string]$name, [bool]$ok, [string]$detail = '') {
  if (-not $ok) { $script:fails++ }
  "{0,-54} {1}  {2}" -f $name, $(if ($ok) { 'OK' } else { 'FAIL' }), $detail
}
function OtherContainers {
  $r = Run-Docker 'ps --format "{{.Names}}"' 30 $null 3
  return ((($r.Text -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notlike 'cco-*' } | Sort-Object) -join ',')
}
function Finish([int]$code) {
  Write-Host ""
  Write-Host "RESULT: UPDOWN_TEST=$(if ($code -eq 0) { 'PASS' } else { 'FAIL' }) FAILED_CHECKS=$script:fails EXIT=$code"
  Write-Host "=== TEST-UP-DOWN COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Before'
"Host memory: $(Mem)"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering.'; Finish 2 }
$before = OtherContainers
"Other (non-cco) running containers: $before"
'Making sure the stack is down first...'
& (Join-Path $here 'down.ps1') | Out-Null

Section 'up.ps1'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& (Join-Path $here 'up.ps1')
$upRc = $LASTEXITCODE
$upSecs = [int]$sw.Elapsed.TotalSeconds
Check 'up.ps1 exit code 0' ($upRc -eq 0) "exit=$upRc after $upSecs s"
$h = Get-CcoHealth
Check 'engine health status is healthy' ($h -eq 'healthy') $h
$ports = (Run-Docker "port $CcoContainer" 20 $null 2).Text.Trim()
Check 'no ports published to the host' ($ports -eq '') $ports
$int = (Run-Docker 'network inspect cco_net --format "{{.Internal}}"' 20 $null 2).Text.Trim()
Check 'network cco_net is internal (no internet route)' ($int -eq 'true') $int
$lab = (Run-Docker 'ps -q --filter label=com.claude-code-offline.project=cco' 20 $null 2).Text.Trim()
Check 'engine container carries the project label' ($lab -ne '')
$vol = (Run-Docker 'volume ls -q --filter name=cco_models' 20 $null 2).Text.Trim()
Check 'model volume cco_models exists' ($vol -eq 'cco_models') $vol
Check 'other containers untouched while the engine runs' ($before -eq (OtherContainers)) ''

Section 'down.ps1'
& (Join-Path $here 'down.ps1')
$gone = (Run-Docker "ps -a -q --filter name=$CcoContainer" 20 $null 2).Text.Trim()
Check 'engine container removed' ($gone -eq '')
$net = (Run-Docker 'network ls -q --filter name=cco_net' 20 $null 2).Text.Trim()
Check 'network cco_net removed' ($net -eq '')
$vol = (Run-Docker 'volume ls -q --filter name=cco_models' 20 $null 2).Text.Trim()
Check 'model volume kept (persistence)' ($vol -eq 'cco_models') $vol
$e = Run-Docker 'image inspect --format "{{.Id}}" cco-engine:cpu' 20 $null 2
Check 'engine image kept' ($e.Exit -eq 0)
$cl = Run-Docker 'image inspect --format "{{.Id}}" cco-claude:cli' 20 $null 2
Check 'Claude Code image kept' ($cl.Exit -eq 0)
$after = OtherContainers
Check 'other (non-cco) containers unchanged overall' ($before -eq $after) "before=[$before] after=[$after]"

if ($script:fails -eq 0) { Finish 0 } else { Finish 1 }