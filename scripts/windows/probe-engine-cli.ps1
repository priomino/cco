# probe-engine-cli.ps1 - Step 8: full CLI help, API-key handling, offline switches (read-only, --network none)
$ErrorActionPreference = 'Continue'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Start-Transcript -Path (Join-Path $dir 'probe-engine-cli-report.txt') -Force | Out-Null
$IMAGE = 'cco-engine:cpu'
function Section($t) { Write-Host ""; Write-Host "=== $t ===" }

function Run-Timeout([string]$exe, [string]$argline, [int]$sec, [string]$stdin = $null) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argline
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding  = [System.Text.Encoding]::UTF8
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
function Finish($code) {
  Run-Timeout 'docker.exe' 'rm -f cco-engine-probe2' 20 | Out-Null
  Write-Host ""; Write-Host "RESULT: CLI_PROBE=$script:res EXIT=$code"
  Write-Host "=== PROBE-ENGINE-CLI COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}
$script:res = 'NOT RUN'

Section 'Daemon and image check'
$r = Run-Timeout 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
$r.Text
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Timeout 'docker.exe' "image inspect --format `"{{.Id}}`" $IMAGE" 20
if ($r.Exit -ne 0) { "Image $IMAGE not found; run build-engine.ps1 first."; Finish 3 }

Section 'Inside the image (no network, 300s timeout)'
$inner = @'
export PATH="$HOME/.local/bin:$PATH" COLUMNS=200 NO_COLOR=1
SITE=$(find "$HOME/.unsloth/studio/unsloth_studio/lib" -maxdepth 3 -type d -name site-packages 2>/dev/null | head -1)
echo "--- unsloth run --help (full) ---";    timeout 60 unsloth run --help 2>&1
echo "--- unsloth studio --help (full) ---"; timeout 60 unsloth studio --help 2>&1
echo "--- unsloth start --help (full) ---";  timeout 60 unsloth start --help 2>&1
echo "--- ~/.unsloth/studio layout ---"; ls -la "$HOME/.unsloth/studio" | head -30; du -sh "$HOME"/.unsloth/studio/* 2>/dev/null | sort -h
echo "--- UNSLOTH_* switches (DISABLE/OFFLINE/STAT/TELEMETRY/PUBLIC/PASSWORD/KEY/HOME) ---"
grep -rhoE --include='*.py' 'UNSLOTH_[A-Z0-9_]*(DISABLE|OFFLINE|STAT|TELEMETRY|PUBLIC|PASSWORD|KEY|HOME)[A-Z0-9_]*' "$SITE/studio" "$SITE/unsloth" "$SITE/unsloth_zoo" 2>/dev/null | sort -u | head -60
echo "--- ANTHROPIC_ / CLAUDE_CODE_ settings used by Unsloth ---"
grep -rnE --include='*.py' 'ANTHROPIC_[A-Z_]+|CLAUDE_CODE_[A-Z_]+|DISABLE_AUTOUPDATER|DISABLE_TELEMETRY' "$SITE/studio" 2>/dev/null | sed 's#.*/site-packages/##' | cut -c1-200 | head -40
echo "--- API key handling in run.py ---"
grep -nE 'api[_-]?key|sk-unsloth' "$SITE/studio/backend/run.py" 2>/dev/null | cut -c1-200 | head -30
echo "--- analytics libraries referenced ---"
grep -rlE --include='*.py' 'posthog|sentry_sdk|mixpanel|amplitude|segment\.io' "$SITE/studio" "$SITE/unsloth" "$SITE/unsloth_zoo" 2>/dev/null | sed 's#.*/site-packages/##' | head -20; echo "(end of list)"
echo "--- hosts referenced in code (static, not proof of calls) ---"
grep -rhoE --include='*.py' 'https?://[A-Za-z0-9.-]+' "$SITE/studio/backend" "$SITE/unsloth" 2>/dev/null | sed -E 's#https?://##' | sort | uniq -c | sort -rn | head -40
echo CLI_PROBE_OK
'@ -replace "`r`n", "`n"
$r = Run-Timeout 'docker.exe' "run --rm -i --network none --name cco-engine-probe2 $IMAGE bash -s" 300 $inner
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
if ($r.Text -match 'CLI_PROBE_OK') { $script:res = 'OK' } else { $script:res = if ($r.TimedOut) { 'TIMEOUT' } else { 'FAIL' } }
if ($script:res -ne 'OK') { Finish 1 }
Finish 0