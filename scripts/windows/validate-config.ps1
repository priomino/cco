# validate-config.ps1 - check configuration, repository files, Docker state and safety settings.
# Usage: powershell -ExecutionPolicy Bypass -File .\validate-config.ps1 [-Deep]
#   -Deep also verifies the model file's SHA-256 against Hugging Face (reads 4.4 GB, needs internet).
# Exit code 0 when there is no FAIL (warnings are allowed), 1 otherwise.
param([switch]$Deep)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
. (Join-Path $here 'versions.ps1')
$script:nOk = 0; $script:nWarn = 0; $script:nFail = 0
function Res([string]$level, [string]$name, [string]$detail = '') {
  if ($level -eq 'OK') { $script:nOk++ } elseif ($level -eq 'WARN') { $script:nWarn++ } else { $script:nFail++ }
  "{0,-5} {1,-40} {2}" -f $level, $name, $detail
}
function Num([string]$s) {
  $d = 0.0
  if ([double]::TryParse($s, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) { return $d }
  return $null
}

Section 'Repository files'
$must = @('docker\compose.yaml', 'docker\engine\Dockerfile', 'docker\claude\Dockerfile', 'docker\claude\entrypoint.sh',
  'docker\claude\claude.env', 'docker\claude\mode-bare.env', 'docker\claude\mode-lean.env', 'docker\claude\mode-full.env',
  'config\.env.example', 'scripts\windows\common.ps1', 'scripts\windows\claude.ps1', 'scripts\windows\up.ps1', 'scripts\windows\down.ps1',
  'scripts\windows\build-engine.ps1', 'scripts\windows\build-claude.ps1', 'scripts\windows\download-model.ps1')
$missing = @($must | Where-Object { -not (Test-Path (Join-Path $CcoRoot $_)) })
if ($missing.Count -eq 0) { Res 'OK' 'repository files' "$($must.Count) present" } else { foreach ($m in $missing) { Res 'FAIL' "file $m" 'missing' } }

Section 'Configuration (config\.env)'
if (-not (Test-Path $CcoEnvFile)) { Res 'WARN' 'config\.env' 'missing; the build scripts create it from the example' }
$cfg = Load-CcoCfg
$known = @('COMPOSE_PROJECT_NAME', 'CCO_ENGINE_PROFILE', 'CCO_DIAG_PORT', 'CCO_UNSLOTH_VERSION', 'CCO_UNSLOTH_INSTALLER_SHA256', 'CCO_ENGINE_PYTHON',
  'CCO_ENGINE_IMAGE', 'CCO_MODEL_REPO', 'CCO_MODEL_FILE', 'CCO_MODEL_SHA256', 'CCO_ENGINE_CONTEXT', 'CCO_ENGINE_TEMPERATURE',
  'CCO_CLAUDE_VERSION', 'CCO_CLAUDE_IMAGE', 'CCO_CLAUDE_MODE', 'CCO_STUDIO_PASSWORD')
foreach ($k in $cfg.Keys) { if ($known -notcontains $k) { Res 'WARN' $k 'unknown key (typo?)' } }
$rules = @(
  @{ k = 'COMPOSE_PROJECT_NAME'; re = '^[a-z0-9][a-z0-9_-]*$'; hint = 'lowercase letters, digits, - and _' },
  @{ k = 'CCO_ENGINE_PROFILE'; re = '^(cpu|igpu)$'; hint = 'cpu or igpu' },
  @{ k = 'CCO_UNSLOTH_VERSION'; re = '^(latest|\d{4}\.\d+\.\d+)$'; hint = 'latest or a release such as 2026.9.14' },
  @{ k = 'CCO_UNSLOTH_INSTALLER_SHA256'; re = '^([0-9a-fA-F]{64})?$'; hint = 'empty or 64 hex characters' },
  @{ k = 'CCO_ENGINE_PYTHON'; re = '^3\.\d+$'; hint = 'a Python version such as 3.12' },
  @{ k = 'CCO_ENGINE_IMAGE'; re = '^[a-z0-9][a-z0-9._/-]*$'; hint = 'a lowercase image name' },
  @{ k = 'CCO_MODEL_REPO'; re = '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$'; hint = 'owner/repository on Hugging Face' },
  @{ k = 'CCO_MODEL_FILE'; re = '^[A-Za-z0-9._-]+\.gguf$'; hint = 'a .gguf file name' },
  @{ k = 'CCO_MODEL_SHA256'; re = '^([0-9a-fA-F]{64})?$'; hint = 'empty or 64 hex characters' },
  @{ k = 'CCO_CLAUDE_VERSION'; re = '^(latest|\d+\.\d+\.\d+)$'; hint = 'latest or a version such as 2.1.295' },
  @{ k = 'CCO_CLAUDE_IMAGE'; re = '^[a-z0-9][a-z0-9._/-]*$'; hint = 'a lowercase image name' },
  @{ k = 'CCO_CLAUDE_MODE'; re = '^(bare|lean|full)$'; hint = 'bare, lean or full' }
)
foreach ($rule in $rules) {
  if (-not $cfg.ContainsKey($rule.k)) { Res 'OK' $rule.k '(not set; the default applies)'; continue }
  if ($cfg[$rule.k] -match $rule.re) { Res 'OK' $rule.k $cfg[$rule.k] } else { Res 'FAIL' $rule.k ("'" + $cfg[$rule.k] + "' is invalid: " + $rule.hint) }
}
if ($cfg['CCO_ENGINE_PROFILE'] -eq 'igpu') { Res 'WARN' 'CCO_ENGINE_PROFILE=igpu' 'the igpu profile is not available in this version (see known limitations)' }
if ($cfg.ContainsKey('CCO_ENGINE_CONTEXT')) {
  $v = Num $cfg['CCO_ENGINE_CONTEXT']
  if ($null -eq $v -or $v -lt 2048) { Res 'FAIL' 'CCO_ENGINE_CONTEXT' "'$($cfg['CCO_ENGINE_CONTEXT'])' must be a number of at least 2048" }
  elseif ($v -gt 32768) { Res 'WARN' 'CCO_ENGINE_CONTEXT' "$v is above the model's native 32768 window" }
  else { Res 'OK' 'CCO_ENGINE_CONTEXT' $cfg['CCO_ENGINE_CONTEXT'] }
}
if ($cfg.ContainsKey('CCO_ENGINE_TEMPERATURE')) {
  $v = Num $cfg['CCO_ENGINE_TEMPERATURE']
  if ($null -eq $v -or $v -lt 0 -or $v -gt 2) { Res 'FAIL' 'CCO_ENGINE_TEMPERATURE' "'$($cfg['CCO_ENGINE_TEMPERATURE'])' must be between 0 and 2" } else { Res 'OK' 'CCO_ENGINE_TEMPERATURE' $cfg['CCO_ENGINE_TEMPERATURE'] }
}
if ($cfg.ContainsKey('CCO_DIAG_PORT')) {
  $v = Num $cfg['CCO_DIAG_PORT']
  if ($null -eq $v -or $v -lt 1 -or $v -gt 65535) { Res 'FAIL' 'CCO_DIAG_PORT' 'must be a port number' } else { Res 'OK' 'CCO_DIAG_PORT' $cfg['CCO_DIAG_PORT'] }
}
if ($cfg['CCO_STUDIO_PASSWORD']) { Res 'OK' 'CCO_STUDIO_PASSWORD' 'set (not shown)' } else { Res 'FAIL' 'CCO_STUDIO_PASSWORD' 'missing; compose needs it (a random value is generated by the install script)' }

Section 'Safety settings'
$gi = Join-Path $CcoRoot '.gitignore'
if ((Test-Path $gi) -and ((Get-Content $gi -Raw) -match '(?m)^\s*(\.env|config/\.env)\s*$')) { Res 'OK' '.env is git-ignored' '' } else { Res 'FAIL' '.env is git-ignored' 'add ".env" to .gitignore (it holds a password)' }
if ((Test-Path $gi) -and ((Get-Content $gi -Raw) -match '(?m)^\s*models/\s*$')) { Res 'OK' 'models/ is git-ignored' '' } else { Res 'WARN' 'models/ is git-ignored' 'add "models/" and "*.gguf" to .gitignore' }
$cy = Join-Path $CcoRoot 'docker\compose.yaml'
if (Test-Path $cy) {
  $ct = Get-Content $cy -Raw
  if ($ct -match '(?m)^\s+internal:\s*true') { Res 'OK' 'network cco_net is internal' '' } else { Res 'FAIL' 'network cco_net is internal' 'internal: true is missing in compose.yaml' }
  if ($ct -match '(?m)^\s+ports:') { Res 'FAIL' 'no published ports' 'compose.yaml publishes a port' } else { Res 'OK' 'no published ports' '' }
  if ($ct -match 'healthcheck:') { Res 'OK' 'engine health check present' '' } else { Res 'WARN' 'engine health check present' 'missing' }
  if ($ct -match '--disable-tools') { Res 'OK' 'server-side tools disabled' '' } else { Res 'FAIL' 'server-side tools disabled' '--disable-tools is missing in compose.yaml' }
}

Section 'Docker, images and model'
$dockerOk = $false
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { Res 'FAIL' 'Docker daemon' 'not answering (start Rancher Desktop, dockerd / moby engine)' } else { Res 'OK' 'Docker daemon' $r.Text.Trim(); $dockerOk = $true }
if ($dockerOk) {
  $eimg = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
  $cimg = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
  $file = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
  $engineOk = $false
  $x = Run-Docker "image inspect --format `"{{.Id}}`" ${eimg}:cpu" 20 $null 2
  if ($x.Exit -eq 0) { Res 'OK' "image ${eimg}:cpu" ''; $engineOk = $true } else { Res 'WARN' "image ${eimg}:cpu" 'missing; run build-engine.ps1' }
  $x = Run-Docker "image inspect --format `"{{.Id}}`" ${cimg}:cli" 20 $null 2
  if ($x.Exit -eq 0) { Res 'OK' "image ${cimg}:cli" '' } else { Res 'WARN' "image ${cimg}:cli" 'missing; run build-claude.ps1' }
  if ($engineOk) {
    $x = Run-Docker "run --rm -v cco_models:/models:ro ${eimg}:cpu stat -c %s /models/$file" 90 $null 2
    $sz = $x.Text.Trim()
    if ($sz -match '^\d{9,}$') { Res 'OK' 'model file in volume cco_models' "$file, $([math]::Round([double]$sz / 1GB, 2)) GiB" } else { Res 'WARN' 'model file in volume cco_models' "$file not found; run download-model.ps1" }
  }
  $x = Compose 'config -q' 60
  if ($x.Exit -eq 0) { Res 'OK' 'compose configuration' 'valid' } else { Res 'FAIL' 'compose configuration' (($x.Text.Trim() -split "`n")[0]) }
}

Section 'Resources'
$o = Get-CimInstance Win32_OperatingSystem
$freeC = (Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB
if ($freeC -lt 5) { Res 'FAIL' 'free disk on C:' ("{0:N1} GiB (a rebuild or model download needs more)" -f $freeC) }
elseif ($freeC -lt 10) { Res 'WARN' 'free disk on C:' ("{0:N1} GiB (upgrades keep old images; consider cleaning up)" -f $freeC) }
else { Res 'OK' 'free disk on C:' ("{0:N1} GiB" -f $freeC) }
$freeCommit = $o.FreeVirtualMemory / 1MB
if ($freeCommit -lt 9) { Res 'WARN' 'free Windows commit' ("{0:N1} GiB (the engine needs about 9 GiB while loading; close heavy applications)" -f $freeCommit) } else { Res 'OK' 'free Windows commit' ("{0:N1} GiB" -f $freeCommit) }

if ($Deep) {
  Section 'Deep: model checksum'
  $repo = if ($cfg['CCO_MODEL_REPO']) { $cfg['CCO_MODEL_REPO'] } else { 'bartowski/Qwen2.5-7B-Instruct-GGUF' }
  $file = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
  $eimg = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
  $exp = ''
  try {
    $tree = Invoke-RestMethod -Uri "https://huggingface.co/api/models/$repo/tree/main" -TimeoutSec 30
    $entry = @($tree | Where-Object { $_.path -eq $file }) | Select-Object -First 1
    if ($entry -and $entry.lfs) { $exp = $entry.lfs.oid.ToLower() }
  } catch { }
  if ($cfg['CCO_MODEL_SHA256']) { $exp = $cfg['CCO_MODEL_SHA256'].ToLower() }
  if (-not $exp) { Res 'WARN' 'model checksum' 'no expected checksum available (offline?); skipped' }
  else {
    $x = Run-Docker "run --rm -v cco_models:/models:ro ${eimg}:cpu sha256sum /models/$file" 900 $null 1
    $act = ($x.Text.Trim() -split '\s+')[0].ToLower()
    if ($act -eq $exp) { Res 'OK' 'model checksum' 'matches' } else { Res 'FAIL' 'model checksum' "expected $exp, got $act" }
  }
}

""
"SUMMARY: ok=$script:nOk warnings=$script:nWarn failures=$script:nFail"
"RESULT: CONFIG_VALID=$(if ($script:nFail -eq 0) { 'YES' } else { 'NO' })"
if ($script:nFail -eq 0) { exit 0 } else { exit 1 }