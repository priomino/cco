# audit2.ps1 - Claude Code Offline: Step 1 re-run (read-only)
# Run: powershell -ExecutionPolicy Bypass -File .\audit2.ps1
$ErrorActionPreference = 'Continue'
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$report = Join-Path $dir 'audit2-report.txt'
Start-Transcript -Path $report -Force | Out-Null
function Section($t) { Write-Host ""; Write-Host "=== $t ===" }
function Clean($s)   { ($s | Out-String) -replace "`0", '' }

Section 'Runtime install detection'
"Docker Desktop exe:   " + (Test-Path "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe")
"Rancher Desktop exe:  " + ((Test-Path "$env:ProgramFiles\Rancher Desktop\Rancher Desktop.exe") -or (Test-Path "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe"))
"Running processes:"
Get-Process | Where-Object { $_.ProcessName -match 'docker|rancher|rdctl|dockerd|containerd|vmmem|wslservice' } |
  Select-Object ProcessName, Id | Format-Table -AutoSize | Out-String

Section 'rdctl (Rancher Desktop CLI) - verify availability'
if (Get-Command rdctl.exe -ErrorAction SilentlyContinue) {
  "--- rdctl version ---";        Clean (rdctl version 2>$null)
  "--- rdctl list-settings ---";  Clean (rdctl list-settings 2>$null)
} else { 'rdctl.exe not on PATH' }

Section 'Rancher settings file candidates - verify path'
@("$env:APPDATA\rancher-desktop\settings.json",
  "$env:LOCALAPPDATA\rancher-desktop\settings.json") | ForEach-Object {
  if (Test-Path $_) { "FOUND: $_"; Get-Content $_ -Raw } else { "absent: $_" }
}

Section 'docker CLI and contexts'
Clean (docker --version 2>$null)
"--- contexts ---"; Clean (docker context ls 2>$null)
"DOCKER_HOST = $env:DOCKER_HOST"
"Pipes: "; Get-ChildItem '\\.\pipe\' -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'docker|rancher|containerd' } | ForEach-Object Name

Section 'docker daemon (JSON)'
$raw = docker info --format '{{json .}}' 2>$null
if ($LASTEXITCODE -eq 0 -and $raw) {
  $j = $raw | ConvertFrom-Json
  "OS:           $($j.OperatingSystem)"
  "Kernel:       $($j.KernelVersion)"
  "VM CPUs:      $($j.NCPU)"
  "VM Mem (GB):  {0:N1}" -f ($j.MemTotal / 1GB)
  "Server:       $($j.ServerVersion)"
  "RootDir:      $($j.DockerRootDir)"
  "Runtimes:     $(($j.Runtimes.PSObject.Properties.Name) -join ', ')"
} else { 'Daemon NOT reachable (exit code ' + $LASTEXITCODE + ')' }

Section 'WSL distros and sizes'
Clean (wsl.exe -l -v 2>&1)
Get-ChildItem "$env:LOCALAPPDATA\rancher-desktop","$env:LOCALAPPDATA\Docker" -Recurse -Filter *.vhdx -ErrorAction SilentlyContinue |
  ForEach-Object { "VHDX: {0}  {1:N1} GB" -f $_.FullName, ($_.Length/1GB) }

Section 'Disk'
Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
  "{0}  free {1:N1} GB of {2:N1} GB" -f $_.DeviceID, ($_.FreeSpace/1GB), ($_.Size/1GB) }

Write-Host "=== AUDIT2 COMPLETE ==="
try { Stop-Transcript | Out-Null } catch {}
exit 0