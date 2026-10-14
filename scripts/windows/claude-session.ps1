# claude-session.ps1 - Step 17: start the engine (internal network), run a real Claude Code (bare mode) session, verify, stop.
# Usage: powershell -ExecutionPolicy Bypass -File .\claude-session.ps1 [-KeepRunning]
param([switch]$KeepRunning)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'claude-session-report.txt') -Force | Out-Null
$script:result = 'NOT RUN'
function Finish([int]$code) {
  Run-Docker 'rm -f cco-claude-session' 30 $null 2 | Out-Null
  if (-not $KeepRunning) { Stop-CcoEngine }
  Write-Host ""
  Write-Host "RESULT: SESSION=$script:result EXIT=$code"
  Write-Host "=== CLAUDE-SESSION COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img   = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
$file  = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
$model = [System.IO.Path]::GetFileNameWithoutExtension($file)

Section 'Preconditions'
"Host memory: $(Mem)"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Docker "image inspect --format `"{{.Id}}`" ${img}:cli" 20 $null 2
if ($r.Exit -ne 0) { "Image ${img}:cli not found; run build-claude.ps1 first."; Finish 3 }
$r = Run-Docker 'volume create --label com.claude-code-offline.project=cco cco_workspace' 30 $null 2
"workspace volume: $($r.Text.Trim())"

Section 'Start the engine (internal network)'
if (-not (Start-CcoEngine 300)) { $script:result = 'ENGINE_NOT_READY'; Finish 1 }

Section 'API key'
$key = Get-CcoKey
if (-not $key) { 'No API key found.'; $script:result = 'NO_KEY'; Finish 1 }
'key found (not shown)'

Section 'Claude Code session (bare mode, up to 2400 s)'
$exports = @(
  "export ANTHROPIC_BASE_URL='http://engine:8888'",
  "export ANTHROPIC_AUTH_TOKEN='$key'",
  "export ANTHROPIC_MODEL='$model'",
  "export ANTHROPIC_DEFAULT_HAIKU_MODEL='$model'",
  "export ANTHROPIC_DEFAULT_SONNET_MODEL='$model'",
  "export ANTHROPIC_DEFAULT_OPUS_MODEL='$model'",
  "export CLAUDE_CODE_SUBAGENT_MODEL='$model'",
  "export CLAUDE_CODE_SIMPLE=1",
  "export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1",
  "export DISABLE_AUTOUPDATER=1",
  "export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1",
  "export CLAUDE_CODE_ATTRIBUTION_HEADER=0",
  "export CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false",
  "export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1",
  "export CLAUDE_CODE_DISABLE_AUTO_MEMORY=1",
  "export CLAUDE_CODE_DISABLE_THINKING=1",
  "export CLAUDE_CODE_MAX_CONTEXT_TOKENS=32768",
  "export CLAUDE_CODE_MAX_OUTPUT_TOKENS=4096",
  "export API_TIMEOUT_MS=3600000",
  "export API_FORCE_IDLE_TIMEOUT=0",
  "export CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000",
  "export CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000",
  "export CLAUDE_STREAM_FIRST_BYTE_TIMEOUT_MS=1800000",
  "export CLAUDE_CODE_DISABLE_NONSTREAMING_FALLBACK=1",
  "export CLAUDE_CODE_MAX_RETRIES=1"
) -join "`n"
$body = (Get-Content (Join-Path $CcoRoot 'tests\claude-session\session.sh') -Raw) -replace "`r`n", "`n"
$r = Run-Docker "run --rm -i --name cco-claude-session --network cco_net -v cco_workspace:/workspace ${img}:cli bash -s" 2400 ($exports + "`n" + $body) 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$out = $r.Text.Replace($key, '<key>')
$out
$ok = ($out -match 'EDIT_OK=yes') -and ($out -match 'VERSION_REPORTED=yes') -and ($out -match 'SESSION_DONE')
$script:result = if ($ok) { 'PASS' } elseif ($out -match 'SESSION_DONE') { 'FAIL' } else { 'NO_RESULT' }

Section 'Engine side: requests and llama-server timings (last 30 lines each)'
$lg = (Run-Docker "logs --tail 1500 $CcoContainer" 60).Text.Replace($key, '<key>')
"--- API requests ---"
($lg -split "`n" | Where-Object { $_ -match 'request_completed' -and $_ -match '/v1/' } | Select-Object -Last 30 | ForEach-Object { if ($_.Length -gt 230) { $_.Substring(0, 230) } else { $_ } }) -join "`n"
"--- engine warnings/errors ---"
($lg -split "`n" | Where-Object { $_ -match '"level": "(warning|error)"' } | Select-Object -Last 15 | ForEach-Object { if ($_.Length -gt 230) { $_.Substring(0, 230) } else { $_ } }) -join "`n"
"--- llama-server timings ---"
(Run-Docker "exec $CcoContainer sh -c `"grep -hE 'prompt eval time|[^t] eval time' /home/cco/.unsloth/studio/logs/llama-server/*.log | cut -c1-200 | tail -30`"" 60).Text

"Host memory: $(Mem)"
if ($script:result -eq 'PASS') { Finish 0 } else { Finish 1 }