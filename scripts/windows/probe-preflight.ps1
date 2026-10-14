# probe-preflight.ps1 - Step 9: HF repo check + disk arithmetic (host), exact switch names (container, no network)
$ErrorActionPreference = 'Continue'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Start-Transcript -Path (Join-Path $dir 'probe-preflight-report.txt') -Force | Out-Null
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
$script:hfOk = $false; $script:ctr = 'NOT RUN'
function Finish($code) {
  Run-Timeout 'docker.exe' 'rm -f cco-engine-probe3' 20 | Out-Null
  Write-Host ""; Write-Host "RESULT: HF_CHECK=$(if ($script:hfOk) {'OK'} else {'FAILED'}) CONTAINER=$script:ctr EXIT=$code"
  Write-Host "=== PROBE-PREFLIGHT COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Disk (C:)'
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$freeGb = [math]::Round($c.FreeSpace / 1GB, 1)
"C: free $freeGb GB of $([math]::Round($c.Size/1GB,1)) GB"

Section 'Hugging Face repo check (host, non-fatal)'
foreach ($repo in 'unsloth/Qwen2.5-7B-Instruct-GGUF', 'bartowski/Qwen2.5-7B-Instruct-GGUF') {
  "--- $repo ---"
  try {
    $tree = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$repo/tree/main" -TimeoutSec 30
    $g = @($tree | Where-Object { $_.path -match '\.gguf$' })
    if (-not $g.Count) { "no .gguf files listed"; continue }
    foreach ($f in $g) {
      $sz = if ($f.lfs -and $f.lfs.size) { [double]$f.lfs.size } else { [double]$f.size }
      $sha = if ($f.lfs) { $f.lfs.oid } else { '' }
      "{0,-52} {1,7:N3} GB  sha256={2}" -f $f.path, ($sz / 1GB), $sha
    }
    $q = $g | Where-Object { $_.path -match 'Q4_K_M' } | Select-Object -First 1
    if ($q) {
      $szq = if ($q.lfs -and $q.lfs.size) { [double]$q.lfs.size } else { [double]$q.size }
      $needGb = [math]::Round($szq / 1GB, 2)
      $after = [math]::Round($freeGb - $needGb - 1.0, 1)
      "ARITHMETIC ($repo / $($q.path)): file $needGb GB; free now $freeGb GB; free after download with ~1 GB safety margin: $after GB"
      $script:hfOk = $true
    } else { "no Q4_K_M file in this repo" }
  } catch { "HF API query failed: $_" }
}

Section 'Daemon and image check'
$r = Run-Timeout 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
$r.Text
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Timeout 'docker.exe' "image inspect --format `"{{.Id}}`" $IMAGE" 20
if ($r.Exit -ne 0) { "Image $IMAGE not found; run build-engine.ps1 first."; Finish 3 }

Section 'Inside the image (no network, 300s timeout)'
$inner = @'
export PATH="$HOME/.local/bin:$PATH"
SITE=$(find "$HOME/.unsloth/studio/unsloth_studio/lib" -maxdepth 3 -type d -name site-packages 2>/dev/null | head -1)
echo "--- unsloth-related packages in site-packages ---"; ls "$SITE" | grep -iE '^unsloth|^studio' | head -20
echo "--- switch names: UNSLOTH_STUDIO_* / *PUBLIC* / *HOME* / *CACHE_DIR* / *DATA_DIR* (no cap below 60) ---"
grep -rhoE --include='*.py' 'UNSLOTH_STUDIO_[A-Z0-9_]+|UNSLOTH_[A-Z0-9_]*PUBLIC[A-Z0-9_]*|UNSLOTH_[A-Z0-9_]*(HOME|CACHE_DIR|DATA_DIR)[A-Z0-9_]*' "$SITE" 2>/dev/null | sort -u | head -60
echo "--- files mentioning ANTHROPIC_BASE_URL ---"
grep -rl --include='*.py' 'ANTHROPIC_BASE_URL' "$SITE" 2>/dev/null | sed 's#.*/site-packages/##' | head -5
for f in $(grep -rl --include='*.py' 'ANTHROPIC_BASE_URL' "$SITE" 2>/dev/null | head -2); do
  echo "--- context in ${f##*/site-packages/} ---"; grep -n -B6 -A30 'ANTHROPIC_BASE_URL' "$f" | cut -c1-180 | head -90
done
echo "--- files mentioning sk-unsloth ---"
grep -rl --include='*.py' 'sk-unsloth' "$SITE" 2>/dev/null | sed 's#.*/site-packages/##' | head -8
echo "--- API key wording in the CLI (first 20) ---"
grep -rn --include='*.py' -i 'api key' "$SITE/unsloth_cli" "$SITE/studio/backend/run.py" 2>/dev/null | sed 's#.*/site-packages/##' | cut -c1-200 | head -20
echo "--- STUDIO_HOME usage (counts) ---"
grep -rhoE --include='*.py' 'STUDIO_HOME[A-Za-z_]*' "$SITE/studio" 2>/dev/null | sort | uniq -c | sort -rn | head -10
echo "--- UNSLOTH_HELPER_MODEL_DISABLE context ---"
grep -rn --include='*.py' -B2 -A6 'UNSLOTH_HELPER_MODEL_DISABLE' "$SITE/studio" 2>/dev/null | sed 's#.*/site-packages/##' | cut -c1-180 | head -30
echo "--- UNSLOTH_OFFLINE usage ---"
grep -rn --include='*.py' 'UNSLOTH_OFFLINE' "$SITE/studio" "$SITE/unsloth" 2>/dev/null | sed 's#.*/site-packages/##' | cut -c1-180 | head -12
echo "--- hidden venv sizes ---"
du -sh "$HOME"/.unsloth/studio/.venv_t5_* 2>/dev/null
echo PREFLIGHT_OK
'@ -replace "`r`n", "`n"
$r = Run-Timeout 'docker.exe' "run --rm -i --network none --name cco-engine-probe3 $IMAGE bash -s" 300 $inner
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
$script:ctr = if ($r.Text -match 'PREFLIGHT_OK') { 'OK' } elseif ($r.TimedOut) { 'TIMEOUT' } else { 'FAIL' }
if ($script:ctr -ne 'OK' -or -not $script:hfOk) { Finish 1 }
Finish 0