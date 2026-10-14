# probe-engine-image.ps1 - Step 7: inspect cco-engine:cpu (read-only, container runs with --network none)
$ErrorActionPreference = 'Continue'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Start-Transcript -Path (Join-Path $dir 'probe-engine-image-report.txt') -Force | Out-Null
$IMAGE = 'cco-engine:cpu'
function Section($t) { Write-Host ""; Write-Host "=== $t ===" }

function Run-Timeout([string]$exe, [string]$argline, [int]$sec, [string]$stdin = $null) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argline
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
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
  Run-Timeout 'docker.exe' 'rm -f cco-engine-probe' 20 | Out-Null
  Write-Host ""; Write-Host "RESULT: UNSLOTH=$script:u LLAMA_SERVER=$script:l EXIT=$code"
  Write-Host "=== PROBE-ENGINE-IMAGE COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}
$script:u = 'NOT RUN'; $script:l = 'NOT RUN'

Section 'Daemon and image check'
$r = Run-Timeout 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
$r.Text
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Timeout 'docker.exe' "image inspect --format `"{{.Id}} {{.Size}}`" $IMAGE" 20
"image inspect exit=$($r.Exit): $($r.Text.Trim())"
if ($r.Exit -ne 0) { "Image $IMAGE not found; run build-engine.ps1 first."; Finish 3 }

Section 'Inside the image (no network, 240s timeout)'
$inner = @'
export PATH="$HOME/.local/bin:$PATH"
echo "--- identity and PATH ---"; id; echo "PATH=$PATH"
echo "--- ~/.local/bin ---"; ls -l "$HOME/.local/bin" 2>&1 | head -20
UB=$(command -v unsloth || true); echo "UNSLOTH_BIN=${UB:-NONE}"
echo "--- unsloth --help ---";        timeout 60 unsloth --help 2>&1 | head -50
echo "--- unsloth run --help ---";    timeout 60 unsloth run --help 2>&1 | head -90
echo "--- unsloth studio --help ---"; timeout 60 unsloth studio --help 2>&1 | head -60
LS=$(find "$HOME/.unsloth" -type f -name llama-server 2>/dev/null | head -1); echo "LLAMA_SERVER=${LS:-NONE}"
if [ -n "$LS" ]; then
  echo "--- llama-server libraries ---"; ldd "$LS" 2>&1 | grep -E 'not found|libgomp' || echo "(no missing libs)"
  echo "--- llama-server --version ---"; timeout 30 "$LS" --version 2>&1 | head -6
fi
echo "--- disk use under ~/.unsloth ---"; du -sh "$HOME"/.unsloth/* "$HOME"/.unsloth/studio/* 2>/dev/null | sort -h | tail -12
SITE=$(find "$HOME/.unsloth/studio/unsloth_studio/lib" -maxdepth 3 -type d -name site-packages 2>/dev/null | head -1)
echo "SITE=$SITE"
echo "--- UNSLOTH_* variables in studio sources ---"
if [ -d "$SITE/studio" ]; then grep -rhoE --include='*.py' 'UNSLOTH_[A-Z0-9_]+' "$SITE/studio" 2>/dev/null | sort -u | head -80; else echo "no studio dir under SITE"; ls "$SITE" 2>/dev/null | head -40; fi
echo "--- possible outbound-contact spots (py files, first 30 hits) ---"
grep -rnoiE --include='*.py' '.{0,50}(posthog|sentry|telemetry|ifconfig\.me|check-host\.net|mixpanel).{0,50}' "$SITE/studio" 2>/dev/null | head -30
echo ENGINE_PROBE_OK
'@ -replace "`r`n", "`n"
$r = Run-Timeout 'docker.exe' "run --rm -i --network none --name cco-engine-probe $IMAGE bash -s" 240 $inner
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
if ($r.Text -match 'UNSLOTH_BIN=(\S+)' -and $Matches[1] -ne 'NONE') { $script:u = 'FOUND' } else { $script:u = 'MISSING' }
if ($r.Text -match 'LLAMA_SERVER=(\S+)' -and $Matches[1] -ne 'NONE') { $script:l = 'FOUND' } else { $script:l = 'MISSING' }
if ($r.Text -notmatch 'ENGINE_PROBE_OK' -or $script:u -ne 'FOUND' -or $script:l -ne 'FOUND') { Finish 1 }
Finish 0