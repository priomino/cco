# claude.ps1 - one-command entry point: starts the engine if needed, then opens Claude Code on a project folder.
# Usage:  powershell -ExecutionPolicy Bypass -File .\claude.ps1 [-Project "C:\path\to\project"] [-Mode bare|lean|full] [-Prompt "do something"] [-KeepEngine]
#   no -Prompt : interactive Claude Code in this terminal
#   -Prompt    : non-interactive (claude -p), prints the answer and exits
#   -Mode      : bare (default, about 1,000 tokens, tools Bash/Read/Edit), lean (about 3,000 tokens, adds Write), full (about 17,000 tokens)
#                the default can be set with CCO_CLAUDE_MODE in config\.env
#   -KeepEngine: leave the engine running afterwards (keeps its prompt cache, holds about 7 GiB of memory)
# The project folder defaults to the current directory. It is mounted read-write at /workspace in the container.
param([string]$Project, [string]$Prompt, [string]$Mode, [switch]$KeepEngine, [switch]$StopEngineOnExit)
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
. (Join-Path $here 'common.ps1')
$extra = @($args)

if (-not $Project) { $Project = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $Project -PathType Container)) { "Project folder not found: $Project"; exit 3 }
$Project = (Resolve-Path -LiteralPath $Project).ProviderPath
if ($Project.StartsWith('\\')) { 'Network (UNC) paths are not supported; use a local drive path.'; exit 3 }
if ($Project.Length -le 3) { 'Refusing to mount a whole drive; choose a project folder.'; exit 3 }

$cfg = @{}
if (Test-Path $CcoEnvFile) {
  foreach ($line in Get-Content $CcoEnvFile) {
    if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
  }
}
$img   = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
$file  = if ($cfg['CCO_MODEL_FILE']) { $cfg['CCO_MODEL_FILE'] } else { 'Qwen2.5-7B-Instruct-Q4_K_M.gguf' }
$model = [System.IO.Path]::GetFileNameWithoutExtension($file)
if (-not $Mode) { $Mode = if ($cfg['CCO_CLAUDE_MODE']) { $cfg['CCO_CLAUDE_MODE'] } else { 'bare' } }
if ($Mode -notin 'bare', 'lean', 'full') { "Unknown mode '$Mode' (use bare, lean or full)."; exit 3 }
$envFile  = Join-Path $CcoRoot 'docker\claude\claude.env'
$modeFile = Join-Path $CcoRoot "docker\claude\mode-$Mode.env"
if (-not (Test-Path $modeFile)) { "Mode file not found: $modeFile"; exit 3 }

switch ($Mode) {
  'bare' { $modeFlags = '--append-system-prompt "You work in /workspace. Create new files with the Bash tool (for example cat > name <<''EOF'' ... EOF) and change existing files with the Edit tool. Never only print file contents in your answer: save them, then tell the user the file path."'; $firstMsg = 'about a minute' }
  'lean' { $modeFlags = '--tools Bash,Read,Edit,Write --append-system-prompt "You work in /workspace. To create a new file you MUST call the Write tool, and to change an existing file you MUST call the Edit tool. Never only print file contents in your answer. After saving, tell the user the file path."'; $firstMsg = 'about three minutes' }
  'full' { $modeFlags = ''; $firstMsg = 'about fifteen minutes' }
}

"Project folder: $Project   Mode: $Mode"
$r = Run-Docker 'version --format "server={{.Server.Version}}"' 15 $null 3
if ($r.TimedOut -or $r.Exit -ne 0) { 'Docker is not answering. Start Rancher Desktop (dockerd / moby engine) and try again.'; exit 2 }
$r = Run-Docker "image inspect --format `"{{.Id}}`" ${img}:cli" 20 $null 2
if ($r.Exit -ne 0) { "Image ${img}:cli not found; run build-claude.ps1 first."; exit 3 }

"Host memory: $(Mem)"
if (-not (Ensure-CcoEngine 300)) { 'The engine is not ready; see the messages above.'; exit 1 }
$key = Get-CcoKey
if (-not $key) { 'Could not read the engine API key.'; exit 1 }

if ($Prompt) { "Running non-interactively (mode $Mode)." }
else { "Starting Claude Code (mode $Mode). The first message of a session needs $firstMsg of prompt processing when the engine was just started; later ones reuse the cache." }

$name = 'cco-claude-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
$tty = if ($Prompt) { '' } else { '-it' }
if ($Prompt) {
  $esc = $Prompt.Replace('"', '\"')
  $cmdArgs = "-p `"$esc`" $modeFlags --permission-mode acceptEdits --max-turns 12 --allowedTools Read Edit Write Bash"
} else {
  $userArgs = ($extra | ForEach-Object { if ($_ -match '\s') { "`"$_`"" } else { "$_" } }) -join ' '
  $cmdArgs = "$modeFlags $userArgs"
}
$createArgs = "create $tty --name $name --network cco_net --workdir /workspace " +
  "--mount `"type=bind,source=$Project,target=/workspace`" " +
  "--mount `"type=volume,source=cco_claude_home,target=/home/cco/.claude-cfg`" " +
  "--env-file `"$envFile`" --env-file `"$modeFile`" -e ANTHROPIC_BASE_URL=http://engine:8888 -e CLAUDE_CONFIG_DIR=/home/cco/.claude-cfg " +
  "-e ANTHROPIC_MODEL=$model -e ANTHROPIC_DEFAULT_HAIKU_MODEL=$model -e ANTHROPIC_DEFAULT_SONNET_MODEL=$model -e ANTHROPIC_DEFAULT_OPUS_MODEL=$model -e CLAUDE_CODE_SUBAGENT_MODEL=$model " +
  "--label com.claude-code-offline.project=cco ${img}:cli cco-claude-entry $cmdArgs"
$r = Run-Docker $createArgs 60 $null 2
if ($r.Exit -ne 0) { "Could not create the Claude Code container:`n$($r.Text)"; exit 1 }

$kf = Join-Path $env:TEMP ('cco-key-' + [guid]::NewGuid().ToString('N'))
try {
  [System.IO.File]::WriteAllText($kf, $key)
  $r = Run-Docker "cp `"$kf`" ${name}:/tmp/cco-engine-key" 30 $null 2
  if ($r.Exit -ne 0) { "Could not copy the key into the container:`n$($r.Text.Replace($key, '<key>'))"; Run-Docker "rm -f $name" 30 $null 2 | Out-Null; exit 1 }
} finally { Remove-Item -LiteralPath $kf -Force -ErrorAction SilentlyContinue }

$rc = 1
try {
  if ($Prompt) { & cmd.exe /c "docker.exe start -a $name 2>&1" | Where-Object { $_ -notmatch '^\[claude-code:unrecognized_model\]' } } else { & docker.exe start -ai $name }
  $rc = $LASTEXITCODE
} finally {
  Run-Docker "rm -f $name" 30 $null 2 | Out-Null
  if ($KeepEngine) {
    'Engine kept running (-KeepEngine, about 7 GiB of memory). Stop it with down.ps1.'
  } else {
    $others = (Run-Docker 'ps -q --filter name=cco-claude-' 20 $null 2).Text.Trim()
    if ($others) { 'Another Claude Code session is still running, so the engine is left running.' }
    else { 'Claude Code has exited; stopping the engine (use -KeepEngine to keep it warm next time).'; Stop-CcoEngine }
  }
}
exit $rc