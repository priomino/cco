# conformance.ps1 - Step 15: start the engine, run the tool-calling conformance test inside the container, stop.
# Usage: powershell -ExecutionPolicy Bypass -File .\conformance.ps1 [-Repeat 2] [-KeepRunning]
param([int]$Repeat = 2, [switch]$KeepRunning)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'conformance-report.txt') -Force | Out-Null
$script:gate = 'NOT RUN'
function Finish([int]$code) {
  if (-not $KeepRunning) { Stop-CcoEngine }
  Write-Host ""
  Write-Host "RESULT: CONFORMANCE=$script:gate EXIT=$code"
  Write-Host "=== CONFORMANCE COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Preconditions'
"Host memory: $(Mem)"
if (-not (Test-Path $CcoEnvFile)) { 'config\.env missing; run engine-first-run.ps1 first.'; Finish 3 }
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }

Section 'Start the engine'
if (-not (Start-CcoEngine 300)) { $script:gate = 'ENGINE_NOT_READY'; Finish 1 }

Section 'API key'
$key = Get-CcoKey
if (-not $key) { 'No API key found.'; $script:gate = 'NO_KEY'; Finish 1 }
'key found (not shown)'

Section "Conformance test, $Repeat run(s) per case (up to 2400 s)"
$py = (Get-Content (Join-Path $CcoRoot 'tests\tool-calling-conformance\conformance.py') -Raw) -replace "`r`n", "`n"
$stdin = "import os`nos.environ['KEY'] = '$key'`nos.environ['REPEAT'] = '$Repeat'`n" + $py
$r = Run-Docker "exec -i $CcoContainer /home/cco/.unsloth/studio/unsloth_studio/bin/python -" 2400 $stdin 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$out = $r.Text.Replace($key, '<key>')
$out
if ($out -match 'gate=PASS') { $script:gate = 'PASS' } elseif ($out -match 'gate=FAIL') { $script:gate = 'FAIL' } else { $script:gate = 'NO_RESULT' }

Section 'Engine log lines mentioning tools (last 25)'
$lg = (Run-Docker "logs --tail 800 $CcoContainer" 60).Text.Replace($key, '<key>')
($lg -split "`n" | Where-Object { $_ -match 'tool|heal|nudg' } | Select-Object -Last 25 | ForEach-Object { if ($_.Length -gt 220) { $_.Substring(0, 220) } else { $_ } }) -join "`n"

"Host memory: $(Mem)"
if ($script:gate -eq 'PASS') { Finish 0 } else { Finish 1 }