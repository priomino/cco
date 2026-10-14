# build-claude.ps1 - build the Claude Code image (official native installer, tracks latest by default)
# Usage: powershell -ExecutionPolicy Bypass -File .\build-claude.ps1 [-Upgrade]
param([switch]$Upgrade)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')

$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
$ver = if ($cfg['CCO_CLAUDE_VERSION']) { $cfg['CCO_CLAUDE_VERSION'] } else { 'latest' }
$tag = "${img}:cli"
"Building $tag (Claude Code version requested: $ver)"
if ($ver -eq 'latest') {
  if ($Upgrade) { 'Tracking latest (-Upgrade: rebuilding without cache)' } else { 'Tracking latest (cached layers reused; use -Upgrade to pick up newer releases)' }
}

$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { "BUILD FAILED: docker daemon not answering: $($r.Text)"; exit 2 }
$freeGb = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
"C: free $freeGb GiB. Host memory: $(Mem)"
if ($freeGb -lt 3) { "BUILD FAILED: less than 3 GiB free on C:"; exit 4 }

$ctx = Join-Path $CcoRoot 'docker\claude'
$logBase = Join-Path $ctx 'build'
$parts = @('build', '--progress=plain')
if ($Upgrade) { $parts += @('--no-cache', '--pull') }
$parts += @('-f', "`"$ctx\Dockerfile`"", '-t', $tag, '--label', 'com.claude-code-offline.project=cco', '--build-arg', "CLAUDE_VERSION=$ver", "`"$ctx`"")
$argList = $parts -join ' '

$timeoutSec = 1500
$p = Start-Process -FilePath 'docker.exe' -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput "$logBase.out" -RedirectStandardError "$logBase.err"
$null = $p.Handle
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
if ($null -eq $code -or "$code" -eq '') { $code = if ((Get-Content $logFile -Raw) -match '(?m)^ERROR: failed to build') { 1 } else { 0 } }

if ($timedOut) { "BUILD FAILED: timed out after ${timeoutSec}s"; Get-Content $logFile -Tail 30; exit 1 }
if ($code -ne 0) {
  "BUILD FAILED: docker build exit code $code"
  Get-Content $logFile -Tail 40
  $txt = Get-Content $logFile -Raw
  if ($txt -match 'No space left') { 'HINT: out of disk space in the Docker VM or on C:.' }
  if ($txt -match 'curl: \(\d+\)') { 'HINT: a download failed (network, DNS or the installer URL); check the lines above.' }
  exit 1
}

$vf = Run-Docker "run --rm $tag cat /home/cco/.cco-versions" 60 $null 3
"--- recorded in image (/home/cco/.cco-versions) ---"
$vf.Text.Trim()
$resolved = 'unknown'
if ($vf.Text -match 'claude=\D*(\d+\.\d+\.\d+)') { $resolved = $Matches[1] }
if ($resolved -ne 'unknown') {
  Run-Docker "tag $tag ${img}:$resolved" 20 $null 2 | Out-Null
  "Snapshot tag: ${img}:$resolved"
}
$size = (Run-Docker "image inspect --format `"{{.Size}}`" $tag" 20 $null 2).Text.Trim()
$sizeGb = if ($size -match '^\d+$') { [math]::Round([double]$size / 1GB, 2) } else { 'unknown' }
$free = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
"BUILD OK image=$tag claude=$resolved size_gb=$sizeGb c_free_gb=$free"
exit 0