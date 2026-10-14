# down.ps1 - stop the engine and remove its container and network (volumes and the model are kept).
# Usage: powershell -ExecutionPolicy Bypass -File .\down.ps1
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Section 'Stopping'
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering; nothing to stop.'; exit 2 }
Stop-CcoEngine
'Done.'
exit 0