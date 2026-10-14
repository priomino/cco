# claude-tools-probe.ps1 - Step 21: which tools and system prompt does Claude Code send with --tools / --append-system-prompt-file?
# Reuses the stub server from tests\claude-request-size\measure.sh; no engine, no network.
# Usage: powershell -ExecutionPolicy Bypass -File .\claude-tools-probe.ps1
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'claude-tools-probe-report.txt') -Force | Out-Null
$script:done = $false
function Finish([int]$code) {
  Run-Docker 'rm -f cco-claude-probe' 30 $null 2 | Out-Null
  Write-Host ""
  Write-Host "RESULT: MEASURE_DONE=$script:done EXIT=$code"
  Write-Host "=== CLAUDE-TOOLS-PROBE COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }

Section 'Preconditions'
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Docker "image inspect --format `"{{.Id}}`" ${img}:cli" 20 $null 2
if ($r.Exit -ne 0) { "Image ${img}:cli not found; run build-claude.ps1 first."; Finish 3 }

$m = (Get-Content (Join-Path $CcoRoot 'tests\claude-request-size\measure.sh') -Raw) -replace "`r`n", "`n"
$idx = $m.IndexOf('run_cfg baseline')
if ($idx -lt 0) { 'measure.sh: marker "run_cfg baseline" not found.'; Finish 1 }
$head = $m.Substring(0, $idx)
$lines = @(
  "printf '%s\n' 'You work in /workspace. To create a new file you MUST call the Write tool, and to change an existing file you MUST call the Edit tool. Never only print file contents in your answer. After saving, tell the user the file path.' > /tmp/append.txt",
  "CLAUDE_FLAGS='--tools Bash,Read,Edit,Write' run_cfg bare_tools token CLAUDE_CODE_SIMPLE=1",
  "CLAUDE_FLAGS='--tools Bash,Read,Edit,Write --append-system-prompt-file /tmp/append.txt' run_cfg bare_tools_append token CLAUDE_CODE_SIMPLE=1",
  "CLAUDE_FLAGS='--tools Bash,Read,Edit,Write' run_cfg lean4 token CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1",
  "CLAUDE_FLAGS='--tools Bash,Read,Edit,Write,Glob,Grep' run_cfg lean6 token CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS=1",
  "echo MEASURE_DONE"
)
$body = $head + ($lines -join "`n") + "`n"

Section 'Measurement inside the Claude Code image (no network, up to 900 s)'
$r = Run-Docker "run --rm -i --network none --name cco-claude-probe ${img}:cli bash -s" 900 $body 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$r.Text
if ($r.Text -match 'MEASURE_DONE') { $script:done = $true }
if ($script:done) { Finish 0 } else { Finish 1 }