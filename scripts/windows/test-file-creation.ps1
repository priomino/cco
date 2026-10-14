# test-file-creation.ps1 - Step 22: can Claude Code create new files in each mode? Real engine, bind-mounted Windows folders.
# Usage: powershell -ExecutionPolicy Bypass -File .\test-file-creation.ps1 [-Keep] [-Modes "bare","lean"]
param([switch]$Keep, [string[]]$Modes = @('bare', 'lean'))
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'test-file-creation-report.txt') -Force | Out-Null
$base = Split-Path $CcoRoot -Parent
$prompt = 'Create a file named hello.py that prints hello world. Then create a file named todo.md with three bullet points about learning Python.'
$results = [ordered]@{}
function Finish([int]$code) {
  & (Join-Path $here 'down.ps1') | Out-Null
  if (-not $Keep) { foreach ($m in $Modes) { Remove-Item -LiteralPath (Join-Path $base "cco-filetest-$m") -Recurse -Force -ErrorAction SilentlyContinue } }
  Write-Host ""
  Write-Host ("RESULT: " + (($results.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ') + " EXIT=$code")
  Write-Host "=== TEST-FILE-CREATION COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Engine'
& (Join-Path $here 'up.ps1')
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 4) { 'The engine did not start; see above.'; Finish 1 }

foreach ($mode in $Modes) {
  $dir = Join-Path $base "cco-filetest-$mode"
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  Section "Mode $mode (up to 40 minutes)"
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  $out = (& (Join-Path $here 'claude.ps1') -Project $dir -Prompt $prompt -Mode $mode -KeepEngine | Out-String)
  $secs = [int]$sw.Elapsed.TotalSeconds
  $out
  $hello = Join-Path $dir 'hello.py'; $todo = Join-Path $dir 'todo.md'
  $helloOk = (Test-Path $hello) -and ((Get-Content $hello -Raw) -match 'print')
  $bullets = 0
  if (Test-Path $todo) { $bullets = @(Select-String -Path $todo -Pattern '^\s*[-*]\s+\S').Count }
  $todoOk = $bullets -ge 3
  "Files on Windows: hello.py exists=$(Test-Path $hello) contains print=$helloOk; todo.md exists=$(Test-Path $todo) bullet lines=$bullets"
  $results[$mode] = if ($helloOk -and $todoOk) { "PASS(${secs}s)" } else { "FAIL(${secs}s)" }
  "Mode ${mode}: $($results[$mode])"
  "--- llama-server prompt timings so far (last 6) ---"
  (Run-Docker "exec $CcoContainer sh -c `"grep -hE 'prompt eval time' /home/cco/.unsloth/studio/logs/llama-server/*.log | cut -c1-190 | tail -6`"" 60 $null 2).Text
}

$anyPass = $false
foreach ($v in $results.Values) { if ($v -like 'PASS*') { $anyPass = $true } }
if ($anyPass) { Finish 0 } else { Finish 1 }