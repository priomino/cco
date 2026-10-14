# test-tool-reliability.ps1 - Step 24: how often does Claude Code really create/edit files per mode and temperature?
# Usage (normal PowerShell window): powershell -ExecutionPolicy Bypass -File .\test-tool-reliability.ps1 [-Runs 5] [-Modes bare,lean] [-Temperatures 0.7,0.2]
param([int]$Runs = 5, [string[]]$Modes = @('bare', 'lean'), [string[]]$Temperatures = @('0.7', '0.2'))
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'test-tool-reliability-report.txt') -Force | Out-Null
$dir = Join-Path (Split-Path $CcoRoot -Parent) 'cco-reliability'
$prompt = 'Create a file named hello.py that prints hello world. Then in notes.txt replace every word foo with bar.'
$summary = New-Object System.Collections.ArrayList
function Reset-Dir {
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'notes.txt'), "foo is here. foo again.`n")
}
function Finish([int]$code) {
  Remove-Item Env:CCO_ENGINE_TEMPERATURE -ErrorAction SilentlyContinue
  & (Join-Path $here 'down.ps1') | Out-Null
  Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host ""
  Write-Host "=== SUMMARY ==="
  $summary | ForEach-Object { Write-Host $_ }
  Write-Host "RESULT: RELIABILITY_TEST=DONE EXIT=$code"
  Write-Host "=== TEST-TOOL-RELIABILITY COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Preconditions'
"Host memory: $(Mem)"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering.'; Finish 2 }
$env:CCO_ENGINE_TEMPERATURE = $Temperatures[0]
$r = Compose 'config -q' 60
if ($r.Exit -ne 0) { "compose config check failed (is the --temperature patch applied?):"; $r.Text; Finish 1 }
'compose config OK'

foreach ($T in $Temperatures) {
  $env:CCO_ENGINE_TEMPERATURE = $T
  Section "Engine with temperature $T"
  & (Join-Path $here 'down.ps1') | Out-Null
  & (Join-Path $here 'up.ps1')
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 4) { "The engine did not start for temperature $T."; [void]$summary.Add("T=$T : ENGINE_FAILED"); continue }
  $cmdText = (Run-Docker "inspect -f `"{{.Config.Cmd}}`" $CcoContainer" 20 $null 2).Text.Trim()
  "unsloth run arguments: $cmdText"
  foreach ($mode in $Modes) {
    $pass = 0; $secsTotal = 0
    for ($i = 1; $i -le $Runs; $i++) {
      Reset-Dir
      $sw = [System.Diagnostics.Stopwatch]::StartNew()
      $out = (& (Join-Path $here 'claude.ps1') -Project $dir -Prompt $prompt -Mode $mode -KeepEngine | Out-String)
      $secs = [int]$sw.Elapsed.TotalSeconds; $secsTotal += $secs
      $hello = Join-Path $dir 'hello.py'; $notes = Join-Path $dir 'notes.txt'
      $helloOk = (Test-Path $hello) -and ((Get-Content $hello -Raw) -match 'print')
      $nt = ''; if (Test-Path $notes) { $nt = Get-Content $notes -Raw }
      $editOk = ($nt -match 'bar') -and ($nt -notmatch 'foo')
      $ok = $helloOk -and $editOk
      if ($ok) { $pass++ }
      "run $i  mode=$mode  T=${T}:  $(if ($ok) { 'PASS' } else { 'FAIL' })  ${secs}s  hello.py=$helloOk  notes edited=$editOk"
      if (-not $ok) {
        $ans = (($out -split "`n") | Where-Object { $_.Trim() -and $_ -notmatch '^(Engine|Project folder|Host memory|Running non-interactively|Engine kept running)' } | Select-Object -First 12) -join ' | '
        if ($ans.Length -gt 600) { $ans = $ans.Substring(0, 600) }
        "    model said: $ans"
      }
    }
    [void]$summary.Add(("T={0} mode={1}: {2}/{3} passed, average {4} s per run" -f $T, $mode, $pass, $Runs, [int]($secsTotal / [Math]::Max(1, $Runs))))
  }
}
Finish 0