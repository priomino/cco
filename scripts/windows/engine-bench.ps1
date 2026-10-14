# engine-bench.ps1 (v2) - Step 12: start engine-cpu, wait for the model load, run the benchmark, stop.
# Tolerates transient docker client crashes (Go "cannot allocate memory" under host memory pressure).
# Usage: powershell -ExecutionPolicy Bypass -File .\engine-bench.ps1 [-Sizes "2000,8000,16000"] [-KeepRunning]
param([string]$Sizes = '2000,8000,16000', [switch]$KeepRunning)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path
Start-Transcript -Path (Join-Path $here 'engine-bench-report.txt') -Force | Out-Null
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

$script:minCommit = 999.0
function Mem {
  $o = Get-CimInstance Win32_OperatingSystem
  $ram = $o.FreePhysicalMemory / 1MB; $com = $o.FreeVirtualMemory / 1MB
  if ($com -lt $script:minCommit) { $script:minCommit = $com }
  return ("free RAM {0:N1} GiB, free commit {1:N1} GiB" -f $ram, $com)
}
# Retry a docker call when the Windows docker client itself crashed with a Go memory error.
function Run-Docker([string]$argline, [int]$sec, [string]$stdin = $null, [int]$tries = 5) {
  for ($i = 1; $i -le $tries; $i++) {
    $r = Run-Timeout 'docker.exe' $argline $sec $stdin
    $crashed = ($r.Text -match 'fatal error') -and ($r.Text -match 'goroutine|runtime\.')
    if (-not $crashed -or $i -eq $tries) { return $r }
    "  (docker client crashed with a memory error; retry $i of $($tries - 1) in 5 s; $(Mem))"
    Start-Sleep -Seconds 5
  }
}

$envFile = Join-Path $Root 'config\.env'
$compose = Join-Path $Root 'docker\compose.yaml'
$bench   = Join-Path $Root 'tests\engine-bench\bench.sh'
$cn = 'cco-engine-cpu'
$script:ready = $false; $script:done = $false

function Compose([string]$sub, [int]$sec, [int]$tries = 3) {
  Run-Docker ("compose --project-directory `"$Root`" --env-file `"$envFile`" -f `"$compose`" --profile cpu $sub") $sec $null $tries
}
function Finish([int]$code) {
  if (-not $KeepRunning) {
    "Stopping the stack (compose down)..."
    $d = Compose 'down' 120 3
    $d.Text
    $failed = ($d.Exit -ne 0) -or (($d.Text -match 'fatal error') -and ($d.Text -match 'goroutine|runtime\.'))
    if ($failed) {
      'compose down failed; removing our own container and network directly.'
      (Run-Docker "rm -f $cn" 60 $null 4).Text
      (Run-Docker 'network rm cco_net' 30 $null 4).Text
    }
  }
  Write-Host ""
  Write-Host ("RESULT: READY={0} BENCH_DONE={1} MIN_FREE_COMMIT_GIB={2:N1} EXIT={3}" -f $script:ready, $script:done, $script:minCommit, $code)
  Write-Host "=== ENGINE-BENCH COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Preconditions'
"Host memory: $(Mem)"
$o = Get-CimInstance Win32_OperatingSystem
if (($o.FreeVirtualMemory / 1MB) -lt 9.0) { 'WARNING: less than 9 GiB of free commit. Closing browser tabs and other heavy apps first makes this run more reliable. Continuing anyway.' }
if (-not (Test-Path $envFile)) { 'config\.env missing; run engine-first-run.ps1 first.'; Finish 3 }
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$sizeList = ($Sizes -split '[,\s]+' | Where-Object { $_ -match '^\d+$' }) -join ' '
if (-not $sizeList) { "No valid sizes in -Sizes '$Sizes'"; Finish 3 }
"Sizes (approximate tokens): $sizeList"

Section 'Start'
(Compose 'down' 120 3) | Out-Null
$r = Compose 'up -d' 180 4
$r.Text
if ($r.Exit -ne 0) { 'compose up failed'; Finish 1 }

Section 'Wait until the model is loaded (up to 300 s)'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 300) {
  $st = (Run-Docker "inspect -f `"{{.State.Status}}`" $cn" 20).Text.Trim()
  if ($st -ne 'running') { "container state: $st"; break }
  $logs = (Run-Docker "logs --tail 200 $cn" 60).Text
  if ($logs -match 'Loaded GGUF model via llama-server') { $script:ready = $true; break }
  "[{0,4}s] waiting for the model to load... ({1})" -f [int]$sw.Elapsed.TotalSeconds, (Mem)
  Start-Sleep -Seconds 10
}
if (-not $script:ready) {
  'Model did not load. Last 60 log lines:'
  (Run-Docker "logs --tail 60 $cn" 30).Text
  Finish 1
}
"Model loaded after about $([int]$sw.Elapsed.TotalSeconds) s. ($(Mem))"

Section 'API key'
$fileList = (Run-Docker "exec $cn sh -c `"find /home/cco -xdev -name '.cli_api_key*' 2>/dev/null`"" 30).Text.Trim()
$key = $null
if ($fileList) {
  $first = ($fileList -split "`n")[0].Trim()
  $c = (Run-Docker "exec $cn cat $first" 20).Text.Trim()
  if ($c -match 'sk-unsloth-[A-Za-z0-9_\-]+') { $key = $Matches[0] }
}
if (-not $key) { 'No API key found.'; Finish 1 }
'key found (not shown)'

Section 'Benchmark (up to 2400 s)'
$body = (Get-Content $bench -Raw) -replace "`r`n", "`n"
$r = Run-Docker "exec -i $cn bash -s" 2400 ("KEY='$key'`nSIZES='$sizeList'`n" + $body) 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$r.Text.Replace($key, '<key>')
if ($r.Text -match 'BENCH_DONE') { $script:done = $true }

Section 'Resources after the run'
(Run-Docker "stats --no-stream --format `"{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}`" $cn" 60).Text
"Host memory: $(Mem)"

if ($script:ready -and $script:done) { Finish 0 } else { Finish 1 }