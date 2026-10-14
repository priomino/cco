# probe-bind-mount.ps1 - Step 18: which Windows path notation does the engine accept for bind mounts?
# Usage: powershell -ExecutionPolicy Bypass -File .\probe-bind-mount.ps1 [-Path "C:\some\project"] [-KeepTestFolder]
param([string]$Path, [switch]$KeepTestFolder)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'probe-bind-mount-report.txt') -Force | Out-Null
$script:best = 'NONE'
function Finish([int]$code) {
  Write-Host ""
  Write-Host "RESULT: BINDMOUNT_BEST=$script:best EXIT=$code"
  Write-Host "=== PROBE-BIND-MOUNT COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

function To-Forms([string]$p) {
  $full = (Resolve-Path -LiteralPath $p).Path
  $drive = $full.Substring(0, 1).ToLower()
  $rest = $full.Substring(2).Replace('\', '/')
  return [ordered]@{ windows = $full; wsl = "/mnt/$drive$rest"; double_slash = "//$drive$rest"; single_slash = "/$drive$rest" }
}

$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }

Section 'Preconditions'
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Daemon not answering (see troubleshooting: docker CLI hangs).'; Finish 2 }
$r = Run-Docker "image inspect --format `"{{.Id}}`" ${img}:cli" 20 $null 2
if ($r.Exit -ne 0) { "Image ${img}:cli not found; run build-claude.ps1 first."; Finish 3 }

$testDir = Join-Path (Split-Path $CcoRoot -Parent) 'cco-bind-test'
New-Item -ItemType Directory -Force -Path $testDir | Out-Null
Remove-Item (Join-Path $testDir 'from-container.txt') -ErrorAction SilentlyContinue
[System.IO.File]::WriteAllText((Join-Path $testDir 'hello.txt'), "hello from windows`n")
"Test folder: $testDir"

$sh = 'ls -ld /ws; id -u; cat /ws/hello.txt; echo written-by-container > /ws/from-container.txt; echo WRITE_RC=$?'
$forms = To-Forms $testDir
$working = @()
Section 'Writable bind mount, four path notations (uid 1000, up to 60 s each)'
foreach ($name in $forms.Keys) {
  $src = $forms[$name]
  Remove-Item (Join-Path $testDir 'from-container.txt') -ErrorAction SilentlyContinue
  "--- $name : $src ---"
  $r = Run-Docker "run --rm --user 1000:1000 --mount `"type=bind,source=$src,target=/ws`" ${img}:cli sh -c `"$sh`"" 60 $null 2
  $txt = $r.Text.Trim(); if ($txt.Length -gt 500) { $txt = $txt.Substring(0, 500) }
  "exit=$($r.Exit)"; $txt
  $seen = Test-Path (Join-Path $testDir 'from-container.txt')
  $readOk = $r.Text -match 'hello from windows'
  $writeOk = ($r.Text -match 'WRITE_RC=0') -and $seen
  "read=$readOk write=$writeOk appears_on_windows=$seen"
  if ($readOk -and $writeOk) { $working += $name }
}

Section 'Summary'
if ($working.Count) { $script:best = $working[0]; "Working notation(s): $($working -join ', ')" } else { 'No notation allowed both reading and writing.' }

if ($Path) {
  Section "Read-only listing of your folder: $Path"
  if (-not (Test-Path -LiteralPath $Path)) { "Path not found: $Path" }
  elseif (-not $working.Count) { 'Skipped: no working notation found above.' }
  else {
    $f2 = To-Forms $Path
    $src = $f2[$script:best]
    "Using notation '$($script:best)': $src"
    $r = Run-Docker "run --rm --user 1000:1000 --mount `"type=bind,source=$src,target=/ws,readonly`" ${img}:cli sh -c `"ls -la /ws | head -25`"" 60 $null 2
    "exit=$($r.Exit)"; $r.Text
  }
}

if (-not $KeepTestFolder) { Remove-Item -LiteralPath $testDir -Recurse -Force -ErrorAction SilentlyContinue; "Test folder removed." }
if ($working.Count) { Finish 0 } else { Finish 1 }