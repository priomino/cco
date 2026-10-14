# upgrade.ps1 - rebuild a component at the latest release, run the gate tests, roll back automatically if they fail.
# Usage: powershell -ExecutionPolicy Bypass -File .\upgrade.ps1 -Component engine|claude [-SkipGate] [-SimulateFailure]
#   -SimulateFailure skips the tests and treats the gate as failed (to exercise the rollback path).
param([Parameter(Mandatory = $true)][ValidateSet('engine', 'claude')][string]$Component, [switch]$SkipGate, [switch]$SimulateFailure)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
. (Join-Path $here 'versions.ps1')
Start-Transcript -Path (Join-Path $here "upgrade-$Component-report.txt") -Force | Out-Null
$script:result = 'NOT RUN'; $script:old = '?'; $script:new = '?'
function Finish([int]$code) {
  Write-Host ""
  Write-Host "UPGRADE_RESULT=$script:result component=$Component old=$script:old new=$script:new"
  Write-Host "=== UPGRADE COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}
function Run-Script([string]$name, [hashtable]$scriptArgs = @{}) {
  & (Join-Path $here $name) @scriptArgs | Out-Host
  return $LASTEXITCODE
}

Section 'Pre-checks'
$rc = Run-Script 'validate-config.ps1' @{}
if ($rc -ne 0) { 'The configuration check failed; fix the failures above first.'; $script:result = 'PRECHECK_FAILED'; Finish 1 }
$comp = Get-CcoComponent $Component
$cfg = Load-CcoCfg
if ($cfg[$comp.PinKey] -and $cfg[$comp.PinKey] -ne 'latest') { "Note: $($comp.PinKey) is pinned to $($cfg[$comp.PinKey]) in config\.env; the rebuild keeps that version. Edit .env to change it." }
$old = Get-ImageVersion $comp $comp.Floating
if (-not $old) { "Cannot read the current version of $($comp.Floating); build it first."; $script:result = 'NO_CURRENT_IMAGE'; Finish 1 }
$script:old = $old
"Current version: $old"
$snaps = @(Get-CcoSnapshots $comp)
$oldSnap = $comp.SnapPrefix + $old + $comp.SnapSuffix
if ($snaps -notcontains $old) {
  "No snapshot tag for the current version yet; creating $oldSnap so a rollback is possible."
  Run-Docker "tag $($comp.Floating) $oldSnap" 20 $null 2 | Out-Null
}

Section "Build ($($comp.Build) -Upgrade)"
$rc = Run-Script $comp.Build @{ Upgrade = $true }
if ($rc -ne 0) { 'The build failed; the previous image is still in place.'; $script:result = 'BUILD_FAILED'; Finish 1 }
$new = Get-ImageVersion $comp $comp.Floating
if (-not $new) { 'Cannot read the new version.'; $script:result = 'BUILD_FAILED'; Finish 1 }
$script:new = $new
"New version: $new"
if ($new -eq $old -and -not $SimulateFailure) { 'Already on the latest release; nothing changed.'; $script:result = 'UNCHANGED'; Finish 0 }

Section 'Gate tests'
$gateOk = $true
$gateNote = ''
if ($SimulateFailure) { 'Simulated failure: skipping the tests and treating the gate as failed.'; $gateOk = $false; $gateNote = 'simulated failure' }
elseif ($SkipGate) { 'WARNING: -SkipGate given; the new version is accepted without tests.'; $gateNote = 'gate skipped' }
elseif ($Component -eq 'engine') {
  $a = Run-Script 'conformance.ps1' @{ Repeat = 2 }
  $b = Run-Script 'test-file-creation.ps1' @{ Modes = @('bare') }
  $gateOk = ($a -eq 0 -and $b -eq 0)
  $gateNote = "conformance exit $a, file-creation exit $b"
} else {
  $a = Run-Script 'test-claude-entry.ps1' @{}
  $b = Run-Script 'test-file-creation.ps1' @{ Modes = @('bare') }
  $gateOk = ($a -eq 0 -and $b -eq 0)
  $gateNote = "entry test exit $a, file-creation exit $b"
}
"Gate: $(if ($gateOk) { 'PASSED' } else { 'FAILED' }) ($gateNote)"

if ($gateOk) {
  $log = Join-Path $CcoRoot 'docs\01-build-log\upgrades.md'
  $u8 = New-Object System.Text.UTF8Encoding($false)
  if (-not (Test-Path $log)) { [System.IO.File]::WriteAllText($log, "# Upgrade log`n`nOne line per upgrade made with scripts\windows\upgrade.ps1.`n`n", $u8) }
  [System.IO.File]::AppendAllText($log, "- $(Get-Date -Format 'yyyy-MM-dd') $Component`: $old -> $new ($gateNote)`n", $u8)
  "Logged in docs\01-build-log\upgrades.md"
  $script:result = 'UPGRADED'; Finish 0
}

Section 'Rolling back'
if (Set-CcoFloatingTag $comp $old) {
  $back = Get-ImageVersion $comp $comp.Floating
  "Floating tag $($comp.Floating) now holds version $back (expected $old)."
  if ($back -eq $old) { "The failed version's snapshot ($($comp.SnapPrefix)$new$($comp.SnapSuffix)) is kept for inspection; remove it with docker image rm when no longer needed." }
  $script:result = if ($back -eq $old) { 'ROLLED_BACK' } else { 'ROLLBACK_FAILED' }
} else { 'Could not restore the previous snapshot.'; $script:result = 'ROLLBACK_FAILED' }
Finish 1