# test-claude-entry.ps1 - Step 19: run claude.ps1 non-interactively on a bind-mounted demo folder and verify the result on Windows.
# Usage: powershell -ExecutionPolicy Bypass -File .\test-claude-entry.ps1 [-Keep]
param([switch]$Keep)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'test-claude-entry-report.txt') -Force | Out-Null
$demo = Join-Path (Split-Path $CcoRoot -Parent) 'cco-demo-project'
$script:result = 'NOT RUN'
function Finish([int]$code) {
  if (-not $Keep) { Remove-Item -LiteralPath $demo -Recurse -Force -ErrorAction SilentlyContinue }
  Write-Host ""
  Write-Host "RESULT: ENTRY_TEST=$script:result EXIT=$code"
  Write-Host "=== TEST-CLAUDE-ENTRY COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Demo project on Windows'
if (Test-Path -LiteralPath $demo) { Remove-Item -LiteralPath $demo -Recurse -Force }
New-Item -ItemType Directory -Force -Path $demo | Out-Null
[System.IO.File]::WriteAllText((Join-Path $demo 'package.json'), "{`"name`":`"demo2`",`"version`":`"2.0.1`"}`n")
[System.IO.File]::WriteAllText((Join-Path $demo 'notes.txt'), "foo is here. foo again.`n")
"Created $demo"

Section 'claude.ps1 -Prompt (up to 40 minutes)'
$prompt = 'Read package.json and tell me the version number. Then in notes.txt replace every word foo with bar, and finally show me notes.txt.'
$out = (& powershell -ExecutionPolicy Bypass -File (Join-Path $here 'claude.ps1') -Project $demo -Prompt $prompt -StopEngineOnExit | Out-String)
$rc = $LASTEXITCODE
$out
Section 'Verification on the Windows side'
$notes = ''
if (Test-Path (Join-Path $demo 'notes.txt')) { $notes = Get-Content (Join-Path $demo 'notes.txt') -Raw }
"notes.txt on Windows: $($notes.Trim())"
$editOk = ($notes -match 'bar') -and ($notes -notmatch 'foo')
$versionOk = $out -match '2\.0\.1'
"claude.ps1 exit code: $rc; edit visible on Windows: $editOk; version reported: $versionOk"
$script:result = if (($rc -eq 0) -and $editOk -and $versionOk) { 'PASS' } else { 'FAIL' }
if ($script:result -eq 'PASS') { Finish 0 } else { Finish 1 }