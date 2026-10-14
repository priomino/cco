# engine-first-run.ps1 - Step 11: first engine start through compose (profile cpu), smoke test, state discovery
# Usage: powershell -ExecutionPolicy Bypass -File .\engine-first-run.ps1 [-KeepRunning]
param([switch]$KeepRunning)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path
Start-Transcript -Path (Join-Path $here 'engine-first-run-report.txt') -Force | Out-Null
function Section($t) { Write-Host ""; Write-Host "=== $t ===" }

function Run-Timeout([string]$exe, [string]$argline, [int]$sec, [string]$stdin = $null) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argline
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.RedirectStandardInput = ($null -ne $stdin)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($null -ne $stdin) { $p.StandardInput.Write($stdin); $p.StandardInput.Close() }
    if (-not $p.WaitForExit($sec * 1000)) {
      try { $p.Kill() } catch {}
      return [pscustomobject]@{ Exit = -1; TimedOut = $true; Secs = [int]$sw.Elapsed.TotalSeconds; Text = "TIMEOUT after ${sec}s" }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ Exit = $p.ExitCode; TimedOut = $false; Secs = [int]$sw.Elapsed.TotalSeconds; Text = (($o.Result + $e.Result) -replace "`0", '') }
  } catch { return [pscustomobject]@{ Exit = -2; TimedOut = $false; Secs = 0; Text = "could not run ${exe}: $_" } }
}

$envFile = Join-Path $Root 'config\.env'
$compose = Join-Path $Root 'docker\compose.yaml'
$smoke   = Join-Path $Root 'tests\engine-smoke\smoke.sh'
$cn = 'cco-engine-cpu'
$script:ready = $false; $script:keyOk = $false; $script:msgOk = $false

function Compose([string]$sub, [int]$sec) {
  Run-Timeout 'docker.exe' ("compose --project-directory `"$Root`" --env-file `"$envFile`" -f `"$compose`" --profile cpu $sub") $sec
}
function Finish([int]$code) {
  if (-not $KeepRunning) { "Stopping the stack (compose down)..."; (Compose 'down' 120).Text }
  Write-Host ""
  Write-Host "RESULT: READY=$script:ready KEY=$script:keyOk MESSAGES_OK=$script:msgOk EXIT=$code"
  Write-Host "=== ENGINE-FIRST-RUN COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Settings'
if (-not (Test-Path $envFile)) { Copy-Item (Join-Path $Root 'config\.env.example') $envFile; 'Created config\.env from .env.example' }
$raw = Get-Content $envFile -Raw
if ($raw -notmatch '(?m)^\s*CCO_STUDIO_PASSWORD\s*=\s*\S+') {
  $bytes = New-Object byte[] 24
  [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  $pw = ([Convert]::ToBase64String($bytes)).Replace('+','A').Replace('/','B').Replace('=','')
  $prefix = if ($raw.EndsWith("`n")) { '' } else { "`n" }
  Add-Content -Path $envFile -Value ($prefix + "CCO_STUDIO_PASSWORD=$pw") -Encoding ASCII
  'Generated CCO_STUDIO_PASSWORD in config\.env (value not shown; the file is git-ignored).'
} else { 'CCO_STUDIO_PASSWORD already set.' }
$cfg = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
}
$img  = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
$file = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
$ctx  = if ($cfg['CCO_ENGINE_CONTEXT']) { $cfg['CCO_ENGINE_CONTEXT'] } else { '32768' }
"Image ${img}:cpu, model $file, context $ctx"

Section 'Preconditions'
$r = Run-Timeout 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Timeout 'docker.exe' "run --rm -v cco_models:/models:ro ${img}:cpu stat -c %s /models/$file" 90
"model file size in volume: $($r.Text.Trim())"
if ($r.Text.Trim() -notmatch '^\d{9,}$') { 'Model file not found in volume cco_models; run download-model.ps1.'; Finish 3 }
$r = Compose 'config -q' 60
if ($r.Exit -ne 0) { "compose config check failed:"; $r.Text; Finish 1 }
'compose config OK'

Section 'Start (docker compose up -d)'
Compose 'down' 120 | Out-Null
$r = Compose 'up -d' 180
$r.Text
if ($r.Exit -ne 0) { 'compose up failed'; Finish 1 }

Section 'Wait for readiness (up to 300 s)'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 300) {
  $st = (Run-Timeout 'docker.exe' "inspect -f `"{{.State.Status}}`" $cn" 20).Text.Trim()
  if ($st -ne 'running') { "container state: $st"; break }
  $code = (Run-Timeout 'docker.exe' "exec $cn curl -s -o /dev/null -w %{http_code} --max-time 5 http://127.0.0.1:8888/" 25).Text.Trim()
  $last = (Run-Timeout 'docker.exe' "logs --tail 1 $cn" 20).Text.Trim()
  if ($last.Length -gt 140) { $last = $last.Substring(0, 140) }
  "[{0,4}s] http={1} | {2}" -f [int]$sw.Elapsed.TotalSeconds, $code, $last
  if ($code -match '^[1-5]\d\d$') { $script:ready = $true; break }
  Start-Sleep -Seconds 10
}
if (-not $script:ready) {
  'Engine did not become ready. Last 60 log lines:'
  (Run-Timeout 'docker.exe' "logs --tail 60 $cn" 30).Text
  Finish 1
}
"Engine answering after about $([int]$sw.Elapsed.TotalSeconds) s."

Section 'API key (masked)'
$logs = (Run-Timeout 'docker.exe' "logs $cn" 60).Text
$key = $null
$m = [regex]::Matches($logs, 'sk-unsloth-[A-Za-z0-9_\-]+')
if ($m.Count -gt 0) { $key = $m[$m.Count - 1].Value }
$fileList = (Run-Timeout 'docker.exe' "exec $cn sh -c `"find /home/cco -xdev -name '.cli_api_key*' 2>/dev/null`"" 30).Text.Trim()
"cached key file(s): $(if ($fileList) { $fileList } else { '(none found)' })"
if (-not $key -and $fileList) {
  $first = ($fileList -split "`n")[0].Trim()
  $c = (Run-Timeout 'docker.exe' "exec $cn cat $first" 20).Text.Trim()
  if ($c -match 'sk-unsloth-[A-Za-z0-9_\-]+') { $key = $Matches[0] }
}
if ($key) {
  $script:keyOk = $true
  "key found: $($key.Substring(0, [Math]::Min(14, $key.Length)))... (length $($key.Length)); source: $(if ($m.Count -gt 0) { 'container log' } else { 'cached file' })"
} else { 'No API key found in the log or cache.' }

if ($script:keyOk) {
  Section 'Smoke test inside the container (up to 900 s)'
  $body = (Get-Content $smoke -Raw) -replace "`r`n", "`n"
  $r = Run-Timeout 'docker.exe' "exec -i $cn bash -s" 900 ("KEY='$key'`n" + $body)
  $out = $r.Text.Replace($key, '<key>')
  "exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
  $out
  if ($out -match 'MESSAGES_RESULT=200 ') { $script:msgOk = $true }
}

Section 'Where the engine keeps state (files changed in the last 30 minutes)'
(Run-Timeout 'docker.exe' "exec $cn sh -c `"find /home/cco -xdev -type f -mmin -30 -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null | head -60`"" 30).Text
"--- ~/.unsloth/studio/share ---"
(Run-Timeout 'docker.exe' "exec $cn ls -la /home/cco/.unsloth/studio/share" 20).Text

Section 'Resources'
(Run-Timeout 'docker.exe' "stats --no-stream --format `"{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}`" $cn" 60).Text

Section 'Engine log (last 70 lines)'
$tail = (Run-Timeout 'docker.exe' "logs --tail 70 $cn" 30).Text
if ($key) { $tail = $tail.Replace($key, '<key>') }
$tail

if ($script:ready -and $script:keyOk -and $script:msgOk) { Finish 0 } else { Finish 1 }