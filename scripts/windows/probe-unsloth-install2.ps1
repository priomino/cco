# probe-unsloth-install2.ps1 - Step 5: read specific install.sh sections + disk accounting (read-only)
$ErrorActionPreference = 'Continue'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Start-Transcript -Path (Join-Path $dir 'probe-unsloth-install2-report.txt') -Force | Out-Null
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
  } catch {
    return [pscustomobject]@{ Exit = -2; TimedOut = $false; Secs = 0; Text = "could not run ${exe}: $_" }
  }
}
function Finish($code) {
  Run-Timeout 'docker.exe' 'rm -f cco-unsloth-probe2' 20 | Out-Null
  Write-Host ""; Write-Host "RESULT: INSTALLSH=$script:ish EXIT=$code"
  Write-Host "=== PROBE-UNSLOTH2 COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}
$script:ish = 'NOT RUN'

Section 'Disk (C:)'
$c = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
"C: free {0:N1} GB of {1:N1} GB" -f ($c.FreeSpace/1GB), ($c.Size/1GB)
Get-ChildItem "$env:LOCALAPPDATA\rancher-desktop" -Recurse -Filter *.vhdx -ErrorAction SilentlyContinue |
  ForEach-Object { "VHDX: {0}  {1:N1} GB" -f $_.FullName, ($_.Length/1GB) }

Section 'Daemon check'
$r = Run-Timeout 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
"exit=$($r.Exit) timedOut=$($r.TimedOut)"; $r.Text
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }

Section 'docker system df (read-only)'
$r = Run-Timeout 'docker.exe' 'system df' 60
$r.Text

Section 'Read install.sh sections (not executed), 300s timeout'
$inner = @'
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq curl ca-certificates >/dev/null 2>&1
curl -fsSL --max-time 60 https://unsloth.ai/install.sh -o /tmp/install.sh
F=/tmp/install.sh
echo "SHA256=$(sha256sum $F | cut -d' ' -f1) LINES=$(wc -l < $F)"
echo "--- lines 30-70 ---";  sed -n '30,70p' $F | cut -c1-200
echo "--- lines 480-540 ---"; sed -n '480,540p' $F | cut -c1-200
echo "--- UNSLOTH_PYPI_JSON_URL ---"; grep -n 'UNSLOTH_PYPI_JSON_URL' $F | cut -c1-220 | head -10
echo "--- installing the package itself ---"; grep -nE 'install.*(PACKAGE_NAME|unsloth\[|studio)' $F | cut -c1-220 | head -25
echo "--- SKIP_TORCH ---"; grep -n 'SKIP_TORCH' $F | cut -c1-200 | head -25
echo "--- llama.cpp acquisition ---"; grep -nE 'llama\.cpp|llama-server|LLAMA_CPP|releases/download|api\.github\.com' $F | cut -c1-200 | head -40
echo "--- Vulkan ---"; grep -niE 'vulkan' $F | cut -c1-200 | head -30
echo "--- system packages / toolchain ---"; grep -nE 'apt-get|apt install|dnf |build-essential|cmake|gcc|nodejs|npm ' $F | cut -c1-200 | head -40
echo PROBE2_READ_OK
'@ -replace "`r`n", "`n"
$r = Run-Timeout 'docker.exe' 'run --rm -i --name cco-unsloth-probe2 ubuntu:24.04 bash -s' 300 $inner
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
if ($r.Text -match 'PROBE2_READ_OK') { $script:ish = 'OK' } else { $script:ish = if ($r.TimedOut) { 'TIMEOUT' } else { 'FAIL' } }
if ($script:ish -ne 'OK') { Finish 1 }
Finish 0