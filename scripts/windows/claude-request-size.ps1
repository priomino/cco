# claude-request-size.ps1 - Step 16: measure what Claude Code sends, against a stub server, no engine, no network.
# Usage: powershell -ExecutionPolicy Bypass -File .\claude-request-size.ps1
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'claude-request-size-report.txt') -Force | Out-Null
$script:done = $false
function Finish([int]$code) {
  Run-Docker 'rm -f cco-claude-probe' 30 $null 2 | Out-Null
  Write-Host ""
  Write-Host "RESULT: MEASURE_DONE=$script:done EXIT=$code"
  Write-Host "=== CLAUDE-REQUEST-SIZE COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Preconditions'
$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Docker "image inspect --format `"{{.Id}}`" ${img}:cli" 20 $null 2
if ($r.Exit -ne 0) { "Image ${img}:cli not found; run build-claude.ps1 first."; Finish 3 }

Section 'Measurement inside the Claude Code image (no network, up to 900 s)'
$body = (Get-Content (Join-Path $CcoRoot 'tests\claude-request-size\measure.sh') -Raw) -replace "`r`n", "`n"
$r = Run-Docker "run --rm -i --network none --name cco-claude-probe ${img}:cli bash -s" 900 $body 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$r.Text
if ($r.Text -match 'MEASURE_DONE') { $script:done = $true }
if ($script:done) { Finish 0 } else { Finish 1 }