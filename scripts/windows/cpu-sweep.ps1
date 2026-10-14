# cpu-sweep.ps1 (v2) - Step 13: start llama-server directly in a throwaway container per configuration
# (threads x flash attention), read its own timings; sample host CPU clocks; show power state.
# Usage: powershell -ExecutionPolicy Bypass -File .\cpu-sweep.ps1 [-PromptTokens 600] [-Threads "4 6 8 12"] [-FlashAttn "off on"]
param([int]$PromptTokens = 600, [string]$Threads = '4 6 8 12', [string]$FlashAttn = 'off on')
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path
Start-Transcript -Path (Join-Path $here 'cpu-sweep-report.txt') -Force | Out-Null
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
function Mem {
  $o = Get-CimInstance Win32_OperatingSystem
  return ("free RAM {0:N1} GiB, free commit {1:N1} GiB" -f ($o.FreePhysicalMemory / 1MB), ($o.FreeVirtualMemory / 1MB))
}
function Run-Docker([string]$argline, [int]$sec, [string]$stdin = $null, [int]$tries = 4) {
  for ($i = 1; $i -le $tries; $i++) {
    $r = Run-Timeout 'docker.exe' $argline $sec $stdin
    $crashed = ($r.Text -match 'fatal error') -and ($r.Text -match 'goroutine|runtime\.')
    if (-not $crashed -or $i -eq $tries) { return $r }
    "  (docker client crashed with a memory error; retry $i in 5 s; $(Mem))"
    Start-Sleep -Seconds 5
  }
}
function TopCpu {
  Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne '_Total' -and $_.Name -ne 'Idle' } |
    Sort-Object PercentProcessorTime -Descending | Select-Object -First 8 Name, PercentProcessorTime |
    Format-Table -AutoSize | Out-String
}

$envFile = Join-Path $Root 'config\.env'
$cfg = @{}
if (Test-Path $envFile) {
  foreach ($line in Get-Content $envFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img  = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
$file = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
$script:sweepDone = $false
function Finish([int]$code) {
  Run-Docker 'rm -f cco-sweep' 60 $null 2 | Out-Null
  Write-Host ""
  Write-Host "RESULT: SWEEP_DONE=$script:sweepDone EXIT=$code"
  Write-Host "=== CPU-SWEEP COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Host power and CPU state (before)'
"Host memory: $(Mem)"
"--- active power scheme ---"; (powercfg /getactivescheme) 2>&1
try {
  $ps = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes' -ErrorAction Stop
  "Power mode overlay (AC): $($ps.ActiveOverlayAcPowerScheme)  (battery): $($ps.ActiveOverlayDcPowerScheme)"
  "  from memory, to be verified: 00000000-0000-0000-0000-000000000000 = Balanced, ded574b5-45a0-4f42-8737-46345c09c238 = Best performance, 961cc777-2547-4f9d-8174-7d86181b8a7a = Best power efficiency"
} catch { "Power mode overlay: not readable ($($_.Exception.Message))" }
$bat = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($bat) { "Battery: status code $($bat.BatteryStatus) (1 = discharging, 2 = on AC), charge $($bat.EstimatedChargeRemaining)%" } else { 'Battery: none reported' }
Get-CimInstance Win32_Processor | ForEach-Object { "CPU: $($_.Name); load $($_.LoadPercentage)%" }
"Top CPU users right now (100 = one core):"; TopCpu

Section 'Preconditions'
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Docker 'ps -q --filter name=cco-engine-cpu' 20 $null 3
if ($r.Text.Trim()) { 'A leftover cco-engine-cpu container is running; removing it (it is ours).'; (Run-Docker 'rm -f cco-engine-cpu' 60 $null 3).Text }
$r = Run-Docker "run --rm -v cco_models:/models:ro ${img}:cpu stat -c %s /models/$file" 90 $null 3
"model file size in volume: $($r.Text.Trim())"
if ($r.Text.Trim() -notmatch '^\d{9,}$') { 'Model file not found in volume cco_models; run download-model.ps1.'; Finish 3 }
"Prompt about $PromptTokens tokens; threads: $Threads; flash attention: $FlashAttn"

Section 'Sweep (up to 2400 s); sampling CPU performance every 4 s in the background'
$sampleFile = Join-Path $env:TEMP 'cco-cpu-samples.csv'
Remove-Item $sampleFile -ErrorAction SilentlyContinue
$job = Start-Job -ScriptBlock {
  param($f)
  while ($true) {
    $perf = ''; $freq = ''; $util = ''
    try {
      $s = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation -Filter "Name='_Total'" -ErrorAction Stop
      $perf = $s.PercentProcessorPerformance; $freq = $s.ProcessorFrequency; $util = $s.PercentProcessorUtility
    } catch {}
    Add-Content -Path $f -Value ("{0},{1},{2},{3}" -f (Get-Date).ToString('HH:mm:ss'), $perf, $freq, $util)
    Start-Sleep -Seconds 4
  }
} -ArgumentList $sampleFile

$body = (Get-Content (Join-Path $Root 'tests\engine-bench\sweep.sh') -Raw) -replace "`r`n", "`n"
$dockerArgs = "run --rm -i --name cco-sweep -v cco_models:/models:ro -e MODEL=/models/$file -e PROMPT_TOKENS=$PromptTokens -e `"THREADS_LIST=$Threads`" -e `"FA_LIST=$FlashAttn`" ${img}:cpu bash -s"
$r = Run-Docker $dockerArgs 2400 $body 1
"exit=$($r.Exit) timedOut=$($r.TimedOut) secs=$($r.Secs)"
$r.Text
if ($r.Text -match 'SWEEP_DONE|NO_LLAMA_SERVER') { $script:sweepDone = $true }

Stop-Job $job -ErrorAction SilentlyContinue; Remove-Job $job -Force -ErrorAction SilentlyContinue

Section 'Host CPU performance samples during the sweep'
if (Test-Path $sampleFile) {
  $rows = @(Get-Content $sampleFile | ForEach-Object {
    $p = $_ -split ','
    if ($p.Count -ge 4 -and $p[1] -ne '') { [pscustomobject]@{ Time = $p[0]; Perf = [double]$p[1]; MHz = [double]$p[2]; Util = [double]$p[3] } }
  })
  "usable samples: $($rows.Count)"
  if ($rows.Count) {
    foreach ($m in 'Perf', 'MHz', 'Util') {
      $st = $rows | Measure-Object $m -Minimum -Maximum -Average
      "{0,-5} min {1,7:N0}  avg {2,7:N0}  max {3,7:N0}" -f $m, $st.Minimum, $st.Average, $st.Maximum
    }
    "first 5 and last 5 samples (time, % performance, MHz, % utility):"
    ($rows | Select-Object -First 5) | ForEach-Object { "{0}  {1,6:N0}  {2,6:N0}  {3,6:N0}" -f $_.Time, $_.Perf, $_.MHz, $_.Util }
    "..."
    ($rows | Select-Object -Last 5) | ForEach-Object { "{0}  {1,6:N0}  {2,6:N0}  {3,6:N0}" -f $_.Time, $_.Perf, $_.MHz, $_.Util }
  } else { '(the WMI processor counters returned nothing; clock data unavailable on this system)' }
} else { '(no sample file was written)' }

"Top CPU users now:"; TopCpu
"Host memory: $(Mem)"
if ($script:sweepDone) { Finish 0 } else { Finish 1 }