# igpu-probe2.ps1 - Claude Code Offline: Step 1b iGPU passthrough probe (hang-proof)
# Safe to re-run. Throwaway named containers, removed before and after.
# Run: powershell -ExecutionPolicy Bypass -File .\igpu-probe2.ps1
$ErrorActionPreference = 'Continue'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
Start-Transcript -Path (Join-Path $dir 'igpu-probe2-report.txt') -Force | Out-Null

$IMAGE  = 'ubuntu:24.04'
$script:stageA = 'NOT RUN'
$script:stageB = 'NOT RUN'

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
      return [pscustomobject]@{ Exit = -1; TimedOut = $true; Secs = [int]$sw.Elapsed.TotalSeconds; Text = "TIMEOUT after ${sec}s: $exe $argline" }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ Exit = $p.ExitCode; TimedOut = $false; Secs = [int]$sw.Elapsed.TotalSeconds; Text = (($o.Result + $e.Result) -replace "`0", '') }
  } catch {
    return [pscustomobject]@{ Exit = -2; TimedOut = $false; Secs = 0; Text = "could not run ${exe}: $_" }
  }
}

function Cleanup { foreach ($n in 'cco-igpu-a','cco-igpu-b') { Run-Timeout 'docker.exe' "rm -f $n" 20 | Out-Null } }

function Finish($code) {
  Cleanup
  Write-Host ""
  Write-Host "RESULT: STAGE_A=$script:stageA STAGE_B=$script:stageB EXIT=$code"
  Write-Host "=== PROBE2 COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Daemon check (15s timeout each)'
$r = Run-Timeout 'docker.exe' 'version --format "server={{.Server.Version}}"' 15
"docker version -> exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
if ($r.TimedOut -or $r.Exit -ne 0) {
  'Daemon not answering. If it timed out, the Windows-side docker proxy is likely wedged:'
  'quit Rancher Desktop fully (tray icon > Quit), run "wsl --shutdown", start Rancher again, wait 2 minutes, re-run.'
  Finish 2
}
$r = Run-Timeout 'docker.exe' 'info --format "cpus={{.NCPU}} mem_bytes={{.MemTotal}} cgroup={{.CgroupVersion}}"' 20
"docker info    -> exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text

Cleanup

Section "Pull $IMAGE (300s timeout)"
$r = Run-Timeout 'docker.exe' "pull $IMAGE" 300
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; ($r.Text -split "`n" | Select-Object -Last 4) -join "`n"
if ($r.TimedOut -or $r.Exit -ne 0) { 'Image pull failed (network or registry). Not a GPU result.'; Finish 3 }

$run = "run --rm -i --device /dev/dxg:/dev/dxg -v /usr/lib/wsl:/usr/lib/wsl -e LD_LIBRARY_PATH=/usr/lib/wsl/lib"

Section 'Stage A: /dev/dxg and WSL libraries visible inside a container (60s timeout)'
$innerA = @'
ls -l /dev/dxg
ls /usr/lib/wsl/lib
if [ -c /dev/dxg ] && [ -e /usr/lib/wsl/lib/libdxcore.so ]; then echo STAGE_A_PASS; else echo STAGE_A_FAIL; fi
'@ -replace "`r`n", "`n"
$r = Run-Timeout 'docker.exe' "$run --name cco-igpu-a $IMAGE bash -s" 60 $innerA
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
if ($r.Text -match 'STAGE_A_PASS') { $script:stageA = 'PASS' } else { $script:stageA = if ($r.TimedOut) { 'TIMEOUT' } else { 'FAIL' } }
if ($script:stageA -ne 'PASS') { Finish 1 }

Section 'Stage B: Intel OpenCL sees the GPU (installs packages inside the container; 600s timeout)'
$innerB = @'
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq 2>&1 | tail -3
apt-get install -y -qq clinfo intel-opencl-icd 2>&1 | tail -3
echo apt_done
clinfo -l 2>&1
clinfo 2>&1 | grep -iE 'Device Name|Device Type|Max compute units|Global memory size' | head -12
if clinfo -l 2>/dev/null | grep -qE 'Device #[0-9]+: .*(Intel|Iris)'; then echo STAGE_B_PASS; else echo STAGE_B_FAIL; ls -l /etc/OpenCL/vendors 2>&1; fi
'@ -replace "`r`n", "`n"
$r = Run-Timeout 'docker.exe' "$run --name cco-igpu-b $IMAGE bash -s" 600 $innerB
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"; $r.Text
if ($r.Text -match 'STAGE_B_PASS') { $script:stageB = 'PASS' } else { $script:stageB = if ($r.TimedOut) { 'TIMEOUT' } else { 'FAIL' } }
if ($script:stageB -ne 'PASS') { Finish 1 }
Finish 0