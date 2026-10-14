# probe-igpu-vulkan.ps1 - Step 14: does Mesa dzn (Vulkan over D3D12 via /dev/dxg) work in a container on this machine?
# Usage: powershell -ExecutionPolicy Bypass -File .\probe-igpu-vulkan.ps1
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path
Start-Transcript -Path (Join-Path $here 'probe-igpu-vulkan-report.txt') -Force | Out-Null
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
function Run-Docker([string]$argline, [int]$sec, [string]$stdin = $null, [int]$tries = 4) {
  for ($i = 1; $i -le $tries; $i++) {
    $r = Run-Timeout 'docker.exe' $argline $sec $stdin
    $crashed = ($r.Text -match 'fatal error') -and ($r.Text -match 'goroutine|runtime\.')
    if (-not $crashed -or $i -eq $tries) { return $r }
    "  (docker client crashed with a memory error; retry $i in 5 s)"
    Start-Sleep -Seconds 5
  }
}
$script:ok = $false
function Finish([int]$code) {
  Run-Docker 'rm -f cco-vkprobe' 30 $null 2 | Out-Null
  Write-Host ""
  Write-Host "RESULT: PROBE_RAN=$script:ok EXIT=$code"
  Write-Host "=== PROBE-IGPU-VULKAN COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Preconditions'
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Docker 'image inspect --format "{{.Id}}" ubuntu:24.04' 20 $null 2
if ($r.Exit -ne 0) { 'ubuntu:24.04 not present; pulling it...'; (Run-Docker 'pull ubuntu:24.04' 300 $null 2).Text | Select-Object -Last 3 }

Section 'Vulkan probe in a throwaway container (up to 600 s)'
$body = (Get-Content (Join-Path $Root 'tests\igpu-probe\vulkan-probe.sh') -Raw) -replace "`r`n", "`n"
$args = 'run --rm -i --name cco-vkprobe --device /dev/dxg:/dev/dxg -v /usr/lib/wsl:/usr/lib/wsl -e LD_LIBRARY_PATH=/usr/lib/wsl/lib ubuntu:24.04 bash -s'
$r = Run-Docker $args 600 $body 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$r.Text
if ($r.Text -match 'VKPROBE_OK') { $script:ok = $true }
if ($script:ok) { Finish 0 } else { Finish 1 }