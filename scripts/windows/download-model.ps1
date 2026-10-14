# download-model.ps1 - download the GGUF model into the docker volume cco_models and verify its SHA-256
# Usage: powershell -ExecutionPolicy Bypass -File .\download-model.ps1 [-Force]
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path

function Run-Quick([string]$exe, [string]$argline, [int]$sec) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argline
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($sec * 1000)) { try { $p.Kill() } catch {}; return @{ Exit = -1; Text = "TIMEOUT after ${sec}s" } }
    $p.WaitForExit()
    return @{ Exit = $p.ExitCode; Text = ($o.Result + $e.Result) }
  } catch { return @{ Exit = -2; Text = "could not run ${exe}: $_" } }
}
function Fail([string]$msg, [int]$code) { "MODEL FAILED: $msg"; exit $code }

# ---- settings (defaults apply when config\.env lacks the keys) ----
$cfg = @{}
$envFile = Join-Path $Root 'config\.env'
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$repo   = if ($cfg['CCO_MODEL_REPO']) { $cfg['CCO_MODEL_REPO'] } else { 'bartowski/Qwen2.5-7B-Instruct-GGUF' }
$file   = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
$cfgSha = $cfg['CCO_MODEL_SHA256']
$engineImg = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
$image = "${engineImg}:cpu"
$vol = 'cco_models'; $cn = 'cco-model-dl'; $timeoutSec = 3600
if ($repo -notmatch '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$') { Fail "CCO_MODEL_REPO has unexpected characters: $repo" 1 }
if ($file -notmatch '^[A-Za-z0-9._-]+$') { Fail "CCO_MODEL_FILE has unexpected characters: $file" 1 }
"Model: $repo / $file"

# ---- docker ----
$r = Run-Quick 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
if ($r.Exit -ne 0) { Fail "docker daemon not answering: $($r.Text)" 2 }
$r = Run-Quick 'docker.exe' "image inspect --format `"{{.Id}}`" $image" 20
if ($r.Exit -ne 0) { Fail "image $image not found; run build-engine.ps1 first" 3 }

# ---- expected size and checksum from Hugging Face ----
try { $tree = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$repo/tree/main" -TimeoutSec 30 }
catch { Fail "Hugging Face API query failed for ${repo}: $_" 5 }
$entry = @($tree | Where-Object { $_.path -eq $file }) | Select-Object -First 1
if (-not $entry) { Fail "file $file not found in $repo" 5 }
$expSize = if ($entry.lfs -and $entry.lfs.size) { [double]$entry.lfs.size } else { [double]$entry.size }
$hfSha = if ($entry.lfs -and $entry.lfs.oid) { $entry.lfs.oid.ToLower() } else { '' }
if ($cfgSha -and $hfSha -and ($cfgSha.ToLower() -ne $hfSha)) { Fail "CCO_MODEL_SHA256 does not match the checksum published by Hugging Face ($hfSha)" 5 }
$expSha = if ($cfgSha) { $cfgSha.ToLower() } else { $hfSha }
if (-not $expSha) { Fail "no checksum available; set CCO_MODEL_SHA256 in config\.env" 5 }
"Expected: {0:N3} GiB, sha256 {1}" -f ($expSize / 1GB), $expSha

# ---- volume and existing file ----
$r = Run-Quick 'docker.exe' "volume create --label com.claude-code-offline.project=cco $vol" 30
if ($r.Exit -ne 0) { Fail "could not create volume ${vol}: $($r.Text)" 1 }
$chk = Run-Quick 'docker.exe' "run --rm -v ${vol}:/models:ro $image sh -c `"stat -c %s /models/$file 2>/dev/null || echo 0`"" 60
$have = 0.0
if ($chk.Text.Trim() -match '^\d+$') { $have = [double]$chk.Text.Trim() }
$skip = ($have -eq $expSize) -and (-not $Force)

if ($skip) { "File already in volume with the expected size; skipping download (use -Force to re-download)." }
else {
  $freeGb = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
  $needGb = ($expSize / 1GB) + 1.0
  "C: free {0:N1} GiB; need about {1:N1} GiB (file plus 1 GiB margin)" -f $freeGb, $needGb
  if ($freeGb -lt $needGb) { Fail ("not enough free disk space on C: ({0:N1} GiB free, {1:N1} GiB needed)" -f $freeGb, $needGb) 4 }

  Run-Quick 'docker.exe' "rm -f $cn" 30 | Out-Null
  $payload = "set -e; curl -fL --retry 5 --retry-delay 5 -C - -sS -o /models/$file.part https://huggingface.co/$repo/resolve/main/${file}?download=true; mv /models/$file.part /models/$file; chown 1000:1000 /models /models/$file; echo DL_DONE"
  $r = Run-Quick 'docker.exe' "run -d --name $cn --user 0:0 --label com.claude-code-offline.project=cco -v ${vol}:/models $image bash -c `"$payload`"" 60
  if ($r.Exit -ne 0) { Fail "could not start the download container: $($r.Text)" 1 }
  "Download started (container $cn). Progress every 20 s; re-running this script resumes a partial download."

  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($true) {
    $st = (Run-Quick 'docker.exe' "inspect -f `"{{.State.Running}}`" $cn" 20).Text.Trim()
    if ($st -ne 'true') { break }
    if ($sw.Elapsed.TotalSeconds -gt $timeoutSec) {
      Run-Quick 'docker.exe' "rm -f $cn" 30 | Out-Null
      Fail "timed out after ${timeoutSec}s (partial file kept; re-run to resume)" 1
    }
    Start-Sleep -Seconds 20
    $szTxt = (Run-Quick 'docker.exe' "exec $cn sh -c `"stat -c %s /models/$file.part 2>/dev/null || echo 0`"" 20).Text.Trim()
    if ($szTxt -match '^\d+$') {
      $pct = [math]::Round(100 * [double]$szTxt / $expSize, 1)
      "[{0,5}s] {1:N2} GiB of {2:N2} GiB ({3}%)" -f [int]$sw.Elapsed.TotalSeconds, ([double]$szTxt / 1GB), ($expSize / 1GB), $pct
    }
  }
  $ec = (Run-Quick 'docker.exe' "inspect -f `"{{.State.ExitCode}}`" $cn" 20).Text.Trim()
  $logs = (Run-Quick 'docker.exe' "logs --tail 20 $cn" 30).Text
  Run-Quick 'docker.exe' "rm -f $cn" 30 | Out-Null
  if ($ec -ne '0') { Fail "download container exited with code $ec`n$logs" 1 }
  "Download finished."
}

# ---- verify ----
"Verifying SHA-256 (reads the whole file; about a minute)..."
$v = Run-Quick 'docker.exe' "run --rm -v ${vol}:/models:ro $image sha256sum /models/$file" 900
if ($v.Exit -ne 0) { Fail "could not hash the file: $($v.Text)" 1 }
$actual = ($v.Text.Trim() -split '\s+')[0].ToLower()
if ($actual -ne $expSha) { Fail "SHA-256 mismatch: expected $expSha, got $actual (use -Force to download again)" 1 }
$free = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
"MODEL OK file=$file bytes=$([int64]$expSize) sha256=$actual verified=yes volume=$vol c_free_gb=$free"
exit 0