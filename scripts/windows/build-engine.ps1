# build-engine.ps1 - build the engine image (Unsloth, GGUF-only)
# Usage: powershell -ExecutionPolicy Bypass -File .\build-engine.ps1 [-Profile cpu|igpu] [-Upgrade] [-ShowInstallerSha]
param(
  [ValidateSet('cpu','igpu')][string]$Profile,
  [switch]$Upgrade,
  [switch]$ShowInstallerSha
)
$ErrorActionPreference = 'Stop'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path

function Run-Quick([string]$exe, [string]$argline, [int]$sec) {
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argline
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($sec * 1000)) { try { $p.Kill() } catch {}; return @{ Exit = -1; Text = "TIMEOUT after ${sec}s" } }
    $p.WaitForExit()
    return @{ Exit = $p.ExitCode; Text = ($o.Result + $e.Result) }
  } catch { return @{ Exit = -2; Text = "could not run ${exe}: $_" } }
}

if ($ShowInstallerSha) {
  $tmp = Join-Path $env:TEMP 'unsloth-install.sh'
  Invoke-WebRequest -Uri 'https://unsloth.ai/install.sh' -OutFile $tmp -UseBasicParsing -TimeoutSec 60
  "Installer SHA-256: " + (Get-FileHash $tmp -Algorithm SHA256).Hash.ToLower()
  "Optional: set CCO_UNSLOTH_INSTALLER_SHA256 in config\.env to this value to make builds fail if the installer changes."
  exit 0
}

$envFile = Join-Path $Root 'config\.env'
if (-not (Test-Path $envFile)) {
  Copy-Item (Join-Path $Root 'config\.env.example') $envFile
  "Created config\.env from .env.example"
}
$cfg = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
}
$need = 'CCO_ENGINE_PYTHON','CCO_ENGINE_IMAGE','CCO_ENGINE_PROFILE'
$missing = $need | Where-Object { -not $cfg.ContainsKey($_) -or -not $cfg[$_] }
if ($missing) { "BUILD FAILED: missing in config\.env: $($missing -join ', ') (see config\.env.example)"; exit 1 }

$ver = if ($cfg.ContainsKey('CCO_UNSLOTH_VERSION') -and $cfg['CCO_UNSLOTH_VERSION']) { $cfg['CCO_UNSLOTH_VERSION'] } else { 'latest' }
$sha = if ($cfg.ContainsKey('CCO_UNSLOTH_INSTALLER_SHA256')) { $cfg['CCO_UNSLOTH_INSTALLER_SHA256'] } else { '' }
if (-not $Profile) { $Profile = $cfg['CCO_ENGINE_PROFILE'] }
if ($Profile -notin 'cpu','igpu') { "BUILD FAILED: CCO_ENGINE_PROFILE must be cpu or igpu"; exit 1 }
$variant = if ($Profile -eq 'igpu') { 'vulkan' } else { 'cpu' }
$tag = '{0}:{1}' -f $cfg['CCO_ENGINE_IMAGE'], $variant

"Building $tag (profile=$Profile, llama.cpp backend=$variant)"
if ($ver -eq 'latest') {
  if ($Upgrade) { "Unsloth: tracking latest (-Upgrade: rebuilding without cache)" }
  else { "Unsloth: tracking latest (cached layers reused; use -Upgrade to pick up newer releases)" }
} else { "Unsloth: version requested = $ver" }
if ($sha) { "Installer hash check: on" } else { "Installer hash check: off" }

$r = Run-Quick 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
if ($r.Exit -ne 0) { "BUILD FAILED: docker daemon not answering: $($r.Text)"; exit 2 }
"Daemon OK: $($r.Text.Trim())"

$ctx = Join-Path $Root 'docker\engine'
$logBase = Join-Path $ctx "build-$variant"
$parts = @('build','--progress=plain')
if ($Upgrade) { $parts += @('--no-cache','--pull') }
$parts += @(
  '-f',"`"$ctx\Dockerfile`"",
  '-t',$tag,
  '--label','com.claude-code-offline.project=cco',
  '--build-arg',"UNSLOTH_VERSION=$ver",
  '--build-arg',"UNSLOTH_INSTALLER_SHA256=$sha",
  '--build-arg',"ENGINE_PYTHON=$($cfg['CCO_ENGINE_PYTHON'])",
  '--build-arg',"LLAMA_BACKEND=$variant",
  "`"$ctx`""
)
$argList = $parts -join ' '

$timeoutSec = 1800
$p = Start-Process -FilePath 'docker.exe' -ArgumentList $argList -NoNewWindow -PassThru `
       -RedirectStandardOutput "$logBase.out" -RedirectStandardError "$logBase.err"
$null = $p.Handle   # ExitCode-fix: cache the process handle so ExitCode is readable in Windows PowerShell 5.1
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$timedOut = $false
while (-not $p.HasExited) {
  if ($sw.Elapsed.TotalSeconds -gt $timeoutSec) { try { $p.Kill() } catch {}; $timedOut = $true; break }
  Start-Sleep -Seconds 20
  $last = ''
  try { $last = [string](Get-Content "$logBase.err" -Tail 1 -ErrorAction SilentlyContinue) } catch {}
  if ($last.Length -gt 130) { $last = $last.Substring(0, 130) }
  "[{0,4}s] {1}" -f [int]$sw.Elapsed.TotalSeconds, $last
}
$p.WaitForExit()
$code = if ($timedOut) { -1 } else { $p.ExitCode }

$logFile = "$logBase.log"
(Get-Content "$logBase.out", "$logBase.err" -ErrorAction SilentlyContinue) | Set-Content $logFile
Remove-Item "$logBase.out", "$logBase.err" -ErrorAction SilentlyContinue
"Full build log: $logFile"

# ExitCode-fix (fallback): if the exit code is still unreadable, judge by the log
if ($null -eq $code -or "$code" -eq '') { $code = if ((Get-Content $logFile -Raw) -match '(?m)^ERROR: failed to build') { 1 } else { 0 } }
$free = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
if ($timedOut) { "BUILD FAILED: timed out after ${timeoutSec}s"; Get-Content $logFile -Tail 30; exit 1 }
if ($code -ne 0) {
  "BUILD FAILED: docker build exit code $code (C: free ${free} GB)"
  Get-Content $logFile -Tail 40
  $txt = Get-Content $logFile -Raw
  if ($txt -match 'did NOT match') { "HINT: the installer no longer matches CCO_UNSLOTH_INSTALLER_SHA256. Run .\build-engine.ps1 -ShowInstallerSha, review it, update the value (or clear it to skip the check)." }
  if ($txt -match 'No space left') { "HINT: out of disk space in the Docker VM or on C:." }
  exit 1
}

$vf = Run-Quick 'docker.exe' "run --rm $tag cat /home/cco/.cco-versions" 60
$resolved = 'unknown'
if ($vf.Exit -eq 0 -and $vf.Text -match 'unsloth-([0-9][0-9A-Za-z._+-]*?)\.dist-info') { $resolved = $Matches[1] }
"--- recorded in image (/home/cco/.cco-versions) ---"
$vf.Text.Trim()
if ($resolved -ne 'unknown') {
  $snap = '{0}:{1}-{2}' -f $cfg['CCO_ENGINE_IMAGE'], $resolved, $variant
  Run-Quick 'docker.exe' "tag $tag $snap" 20 | Out-Null
  "Snapshot tag: $snap"
}
$size = (Run-Quick 'docker.exe' "image inspect --format `"{{.Size}}`" $tag" 20).Text.Trim()
$sizeGb = if ($size -match '^\d+$') { [math]::Round([double]$size / 1GB, 2) } else { 'unknown' }
"BUILD OK image=$tag unsloth=$resolved size_gb=$sizeGb c_free_gb=$free"
exit 0