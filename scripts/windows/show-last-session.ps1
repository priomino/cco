# show-last-session.ps1 - summarize Claude Code's own session transcript(s) from the cco_claude_home volume.
# Usage (normal PowerShell window): powershell -ExecutionPolicy Bypass -File .\show-last-session.ps1 [-Sessions 1] [-MaxLines 80]
# The output contains the first 240 characters of messages, tool inputs and tool results: review it before sharing.
param([int]$Sessions = 1, [int]$MaxLines = 80)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering.'; exit 2 }
$py = (Get-Content (Join-Path $CcoRoot 'tests\transcript\summarize.py') -Raw) -replace "`r`n", "`n"
$r = Run-Docker "run --rm -i --mount type=volume,source=cco_claude_home,target=/cfg,readonly ${img}:cli python3 - $Sessions $MaxLines" 120 $py 2
$r.Text
exit $r.Exit