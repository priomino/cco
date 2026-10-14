# rollback.ps1 - list or switch the kept snapshot versions of the engine or Claude Code image.
# Usage: powershell -ExecutionPolicy Bypass -File .\rollback.ps1 -Component engine|claude [-List] [-Version <version>]
# The floating tag (cco-engine:cpu / cco-claude:cli) is pointed at the snapshot of that version; nothing is rebuilt.
param([Parameter(Mandatory = $true)][ValidateSet('engine', 'claude')][string]$Component, [string]$Version, [switch]$List)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
. (Join-Path $here 'versions.ps1')
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering.'; exit 2 }
$comp = Get-CcoComponent $Component
$cur = Get-ImageVersion $comp $comp.Floating
"Component: $Component. The floating tag $($comp.Floating) currently holds version: $(if ($cur) { $cur } else { 'unknown (image missing?)' })"
$snaps = @(Get-CcoSnapshots $comp)
"Snapshots kept: $(if ($snaps.Count) { $snaps -join ', ' } else { '(none)' })"
if ($List -or -not $Version) {
  if (-not $List) { 'Give -Version <one of the snapshots> to switch.' }
  exit 0
}
if ($Version -notmatch '^[0-9A-Za-z._+-]+$') { 'Invalid version text.'; exit 3 }
if ($snaps -notcontains $Version) { "No snapshot for version $Version."; exit 3 }
if ($Component -eq 'engine') {
  $st = Run-Docker "inspect -f `"{{.State.Status}}`" $CcoContainer" 20 $null 2
  if ($st.Exit -eq 0 -and $st.Text.Trim() -eq 'running') { 'Note: the engine is running; the change takes effect at its next start (run down.ps1 first).' }
}
if (-not (Set-CcoFloatingTag $comp $Version)) { 'Could not retag the image.'; exit 1 }
$now = Get-ImageVersion $comp $comp.Floating
"Now: $($comp.Floating) holds version $now"
if ($now -eq $Version) { 'ROLLBACK_OK'; exit 0 } else { 'ROLLBACK_VERIFY_FAILED'; exit 1 }