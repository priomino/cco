# verify-offline.ps1 - Step 23: full session with the host network switched off.
# Usage (network OFF): powershell -ExecutionPolicy Bypass -File .\verify-offline.ps1 [-Mode bare|lean|full] [-AllowOnline]
# Exit codes: 0 pass; 1 session failed; 2 Docker not answering; 5 the host network is not off (use -AllowOnline to run anyway).
param([string]$Mode, [switch]$AllowOnline)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
Start-Transcript -Path (Join-Path $here 'verify-offline-report.txt') -Force | Out-Null
$demo = Join-Path (Split-Path $CcoRoot -Parent) 'cco-offline-demo'
$script:result = 'NOT RUN'
function Finish([int]$code) {
  & (Join-Path $here 'down.ps1') | Out-Null
  Remove-Item -LiteralPath $demo -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host ""
  Write-Host "RESULT: OFFLINE_TEST=$script:result EXIT=$code"
  Write-Host "=== VERIFY-OFFLINE COMPLETE ==="
  try { Stop-Transcript | Out-Null } catch {}
  exit $code
}

Section 'Is the host network really off?'
$dns = $false; try { [System.Net.Dns]::GetHostAddresses('example.com') | Out-Null; $dns = $true } catch {}
$tcp = $false
try { $c = New-Object System.Net.Sockets.TcpClient; $iar = $c.BeginConnect('1.1.1.1', 443, $null, $null); $tcp = ($iar.AsyncWaitHandle.WaitOne(3000) -and $c.Connected); $c.Close() } catch {}
$web = $false; try { Invoke-WebRequest 'https://example.com' -UseBasicParsing -TimeoutSec 5 | Out-Null; $web = $true } catch {}
"DNS lookup works: $dns; TCP to 1.1.1.1:443 works: $tcp; HTTPS to example.com works: $web"
if ($dns -or $tcp -or $web) {
  if (-not $AllowOnline) { 'The network is NOT off. Switch off Wi-Fi and Ethernet (Airplane mode) and run again, or pass -AllowOnline.'; $script:result = 'NETWORK_NOT_OFF'; Finish 5 }
  'WARNING: -AllowOnline given; the host network is still reachable, so this is not a strict offline test.'
} else { 'OK: no DNS, no TCP, no HTTPS from this PC.' }

Section 'Docker and prerequisites'
"Host memory: $(Mem)"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
$r.Text.Trim()
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering with the network off (see troubleshooting: docker CLI hangs).'; $script:result = 'DOCKER_DOWN'; Finish 2 }

Section 'Demo project'
if (Test-Path -LiteralPath $demo) { Remove-Item -LiteralPath $demo -Recurse -Force }
New-Item -ItemType Directory -Force -Path $demo | Out-Null
[System.IO.File]::WriteAllText((Join-Path $demo 'package.json'), "{`"name`":`"offline-demo`",`"version`":`"3.1.4`"}`n")
[System.IO.File]::WriteAllText((Join-Path $demo 'notes.txt'), "foo is here. foo again.`n")
"Created $demo"

Section 'Engine (offline)'
& (Join-Path $here 'up.ps1')
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 4) { 'The engine did not start offline; see above.'; $script:result = 'ENGINE_FAILED'; Finish 1 }

Section 'Claude Code session (offline, up to 40 minutes)'
$prompt = 'Read package.json and tell me the version number. Then in notes.txt replace every word foo with bar, and finally show me notes.txt.'
$args2 = @('-Project', $demo, '-Prompt', $prompt, '-KeepEngine')
if ($Mode) { $args2 += @('-Mode', $Mode) }
$out = (& (Join-Path $here 'claude.ps1') @args2 | Out-String)
$out
$notes = ''
if (Test-Path (Join-Path $demo 'notes.txt')) { $notes = Get-Content (Join-Path $demo 'notes.txt') -Raw }
$editOk = ($notes -match 'bar') -and ($notes -notmatch 'foo')
$versionOk = $out -match '3\.1\.4'
"notes.txt on Windows: $($notes.Trim()); edit ok: $editOk; version reported: $versionOk"

Section 'Engine log: attempts to reach the internet or warnings about being offline'
$lg = (Run-Docker "logs --tail 6000 $CcoContainer" 90 $null 2).Text -replace 'sk-unsloth-[A-Za-z0-9_\-]+', '<key>'
$pat = 'ifconfig\.me|check-host|huggingface\.co|github\.com|pypi\.org|ollama\.com|Name or service not known|Temporary failure in name resolution|getaddrinfo|ConnectError|ConnectionError|offline|unreachable'
$hits = @($lg -split "`n" | Where-Object { $_ -match $pat })
"matching lines: $($hits.Count)"
$hits | Select-Object -First 15 | ForEach-Object { if ($_.Length -gt 220) { $_.Substring(0, 220) } else { $_ } }

$script:result = if ($editOk -and $versionOk) { 'PASS' } else { 'FAIL' }
if ($script:result -eq 'PASS') { Finish 0 } else { Finish 1 }