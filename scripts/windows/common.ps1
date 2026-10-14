# common.ps1 - shared helpers for scripts\windows. Dot-source it: . (Join-Path $here 'common.ps1')
$CcoRoot      = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$CcoEnvFile   = Join-Path $CcoRoot 'config\.env'
$CcoCompose   = Join-Path $CcoRoot 'docker\compose.yaml'
$CcoContainer = 'cco-engine-cpu'

function Section($t) { Write-Host ""; Write-Host "=== $t ===" }

function Run-Timeout([string]$exe, [string]$argline, [int]$sec, [string]$stdin = $null) {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = $argline
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.RedirectStandardInput = ($null -ne $stdin)
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if ($null -ne $stdin) { $p.StandardInput.Write($stdin); $p.StandardInput.Close() }
    if (-not $p.WaitForExit($sec * 1000)) {
      try { $p.Kill() } catch {}
      return [pscustomobject]@{ Exit = -1; TimedOut = $true; Secs = [int]$sw.Elapsed.TotalSeconds; Text = "TIMEOUT after ${sec}s" }
    }
    $p.WaitForExit()
    return [pscustomobject]@{ Exit = $p.ExitCode; TimedOut = $false; Secs = [int]$sw.Elapsed.TotalSeconds; Text = (($o.Result + $e.Result) -replace "`0", '') }
  } catch { return [pscustomobject]@{ Exit = -2; TimedOut = $false; Secs = 0; Text = "could not run ${exe}: $_" } }
}

function Mem {
  $o = Get-CimInstance Win32_OperatingSystem
  return ("free RAM {0:N1} GiB, free commit {1:N1} GiB" -f ($o.FreePhysicalMemory / 1MB), ($o.FreeVirtualMemory / 1MB))
}

# Runs docker.exe; retries when the Windows docker client itself crashed with a Go memory error.
function Run-Docker([string]$argline, [int]$sec, [string]$stdin = $null, [int]$tries = 4) {
  for ($i = 1; $i -le $tries; $i++) {
    $r = Run-Timeout 'docker.exe' $argline $sec $stdin
    $crashed = ($r.Text -match 'fatal error') -and ($r.Text -match 'goroutine|runtime\.')
    if (-not $crashed -or $i -eq $tries) { return $r }
    Write-Host "  (docker client crashed with a memory error; retry $i in 5 s; $(Mem))"
    Start-Sleep -Seconds 5
  }
}

function Compose([string]$sub, [int]$sec, [int]$tries = 3) {
  Run-Docker ("compose --project-directory `"$CcoRoot`" --env-file `"$CcoEnvFile`" -f `"$CcoCompose`" --profile cpu $sub") $sec $null $tries
}

function Stop-CcoEngine {
  # Claude Code containers left behind (for example by an interrupted session) keep the network "in use": remove them first.
  $left = @((Run-Docker 'ps -aq --filter name=cco-claude-' 20 $null 2).Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($id in $left) { Write-Host "Removing leftover Claude Code container $id"; Run-Docker "rm -f $id" 30 $null 2 | Out-Null }
  Write-Host "Stopping the stack (compose down)..."
  $d = Compose 'down' 120 3
  Write-Host $d.Text
  $failed = ($d.Exit -ne 0) -or (($d.Text -match 'fatal error') -and ($d.Text -match 'goroutine|runtime\.'))
  if ($failed) {
    Write-Host 'compose down failed; removing our own container and network directly.'
    Write-Host (Run-Docker "rm -f $CcoContainer" 60 $null 4).Text
    Write-Host (Run-Docker 'network rm cco_net' 30 $null 4).Text
  }
}

# Starts the stack and waits until the model is loaded. Returns $true or $false.
function Start-CcoEngine([int]$WaitSec = 300) {
  Ensure-CcoEnv | Out-Null
  Compose 'down' 120 3 | Out-Null
  $r = Compose 'up -d' 180 4
  Write-Host $r.Text
  if ($r.Exit -ne 0) { Write-Host 'compose up failed'; return $false }
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
    $st = (Run-Docker "inspect -f `"{{.State.Status}}`" $CcoContainer" 20).Text.Trim()
    if ($st -ne 'running') { Write-Host "container state: $st"; break }
    $logs = (Run-Docker "logs --tail 200 $CcoContainer" 60).Text
    if ($logs -match 'Loaded GGUF model via llama-server') {
      Write-Host ("Model loaded after about {0} s. ({1})" -f [int]$sw.Elapsed.TotalSeconds, (Mem))
      return $true
    }
    Write-Host ("[{0,4}s] waiting for the model to load... ({1})" -f [int]$sw.Elapsed.TotalSeconds, (Mem))
    Start-Sleep -Seconds 10
  }
  Write-Host 'Model did not load. Last 60 log lines:'
  Write-Host (Run-Docker "logs --tail 60 $CcoContainer" 30).Text
  return $false
}

# Returns the engine API key (string) or $null. Never prints it.
function Get-CcoKey {
  $fileList = (Run-Docker "exec $CcoContainer sh -c `"find /home/cco -xdev -name '.cli_api_key*' 2>/dev/null`"" 30).Text.Trim()
  if (-not $fileList) { return $null }
  $first = ($fileList -split "`n")[0].Trim()
  $c = (Run-Docker "exec $CcoContainer cat $first" 20).Text.Trim()
  if ($c -match 'sk-unsloth-[A-Za-z0-9_\-]+') { return $Matches[0] }
  return $null
}

# Starts the engine only if it is not already running with the model loaded. Returns $true or $false.
function Ensure-CcoEngine([int]$WaitSec = 300) {
  $st = Run-Docker "inspect -f `"{{.State.Status}}`" $CcoContainer" 20 $null 2
  if ($st.Exit -eq 0 -and $st.Text.Trim() -eq 'running') {
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $WaitSec) {
      $logs = (Run-Docker "logs --tail 5000 $CcoContainer" 90).Text
      if ($logs -match 'Loaded GGUF model via llama-server') { Write-Host 'Engine is running with the model loaded.'; return $true }
      Write-Host ("[{0,4}s] engine is running, waiting for the model to load..." -f [int]$sw.Elapsed.TotalSeconds)
      Start-Sleep -Seconds 10
    }
    Write-Host 'Engine is running but the model did not finish loading.'
    return $false
  }
  return (Start-CcoEngine $WaitSec)
}

# Returns the engine container's health status: starting, healthy, unhealthy, none (no check) or the docker error text.
function Get-CcoHealth {
  $r = Run-Docker "inspect -f `"{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}`" $CcoContainer" 20 $null 2
  return $r.Text.Trim()
}

# Creates config\.env from the example when missing and generates CCO_STUDIO_PASSWORD when absent. Returns $true if anything was created.
function Ensure-CcoEnv {
  $changed = $false
  if (-not (Test-Path $CcoEnvFile)) {
    $ex = Join-Path $CcoRoot 'config\.env.example'
    if (-not (Test-Path $ex)) { Write-Host 'config\.env.example is missing.'; return $false }
    Copy-Item $ex $CcoEnvFile
    Write-Host 'Created config\.env from .env.example'
    $changed = $true
  }
  $raw = Get-Content $CcoEnvFile -Raw
  if ($raw -notmatch '(?m)^\s*CCO_STUDIO_PASSWORD\s*=\s*\S+') {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes)).Replace('+', 'A').Replace('/', 'B').Replace('=', '')
    $prefix = if ($raw.Length -eq 0 -or $raw.EndsWith("`n")) { '' } else { "`n" }
    [System.IO.File]::AppendAllText($CcoEnvFile, $prefix + "CCO_STUDIO_PASSWORD=$pw`n", (New-Object System.Text.UTF8Encoding($false)))
    Write-Host 'Generated CCO_STUDIO_PASSWORD in config\.env (value not shown; the file is git-ignored).'
    $changed = $true
  }
  return $changed
}