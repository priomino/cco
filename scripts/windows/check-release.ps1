# check-release.ps1 - pre-publication checks: secrets, personal data, large files, ignore rules, required files.
# Usage: powershell -ExecutionPolicy Bypass -File .\check-release.ps1
# Exit code 0 when there is no FAIL (warnings are allowed), 1 otherwise.
$ErrorActionPreference = 'Continue'
$here = if ($PSScriptRoot) { $PSScriptRoot } else { 'C:\projects\claude-code-offline\scripts\windows' }
$Root = (Resolve-Path (Join-Path $here '..\..')).Path
$script:fail = 0; $script:warn = 0; $script:ok = 0
function Res([string]$level, [string]$name, [string]$detail = '') {
  if ($level -eq 'OK') { $script:ok++ } elseif ($level -eq 'WARN') { $script:warn++ } else { $script:fail++ }
  "{0,-5} {1,-44} {2}" -f $level, $name, $detail
}

"=== Required files ==="
foreach ($f in 'README.md', 'LICENSE', 'CHANGELOG.md', 'VERSION', 'THIRD-PARTY-NOTICES.md', '.gitignore', 'config\.env.example', 'docs\00-architecture.md', 'docs\02-usage.md', 'docs\03-configuration.md', 'docs\04-upgrading.md', 'docs\05-troubleshooting.md', 'docs\06-known-limitations.md', 'docs\07-roadmap.md') {
  if (Test-Path (Join-Path $Root $f)) { Res 'OK' $f } elseif ($f -eq 'LICENSE') { Res 'WARN' $f 'missing: choose a licence before publishing' } else { Res 'FAIL' $f 'missing' }
}

"=== .gitignore rules ==="
$gi = ''; if (Test-Path (Join-Path $Root '.gitignore')) { $gi = Get-Content (Join-Path $Root '.gitignore') -Raw }
foreach ($rule in @(@('\.env', '.env'), @('models/', 'models/'), @('\*\.gguf', '*.gguf'), @('\*\.log', '*.log'), @('\*-report\.txt', '*-report.txt'))) {
  if ($gi -match ('(?m)^\s*' + $rule[0] + '\s*$')) { Res 'OK' "ignored: $($rule[1])" } else { Res 'FAIL' "ignored: $($rule[1])" 'add it to .gitignore' }
}

"=== Scan for secrets and personal data ==="
$skipNames = @('.env')
$files = @(Get-ChildItem $Root -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object {
  $_.FullName -notmatch '\\\.git\\' -and $skipNames -notcontains $_.Name -and $_.Extension -ne '.log' -and $_.Name -notlike '*-report.txt' -and $_.Extension -ne '.part' })
"files scanned: $($files.Count)"
$big = @($files | Where-Object { $_.Length -gt 5MB })
if ($big.Count) { foreach ($b in $big) { Res 'FAIL' 'large file' "$($b.FullName.Substring($Root.Length + 1)) ($([math]::Round($b.Length / 1MB, 1)) MB)" } } else { Res 'OK' 'no file larger than 5 MB' }
$textExt = '.ps1', '.md', '.yaml', '.yml', '.sh', '.py', '.txt', '.json', '.example', '.env', '.cfg', '.toml'
$secretPatterns = @(
  @('Unsloth API key', 'sk-unsloth-[A-Za-z0-9_\-]{8,}'),
  @('password value', 'CCO_STUDIO_PASSWORD\s*=\s*[A-Za-z0-9]{12,}'),
  @('private key', '-----BEGIN [A-Z ]*PRIVATE KEY-----'),
  @('token', 'ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}'))
$personal = @('C:\\Users\\[A-Za-z0-9._-]{2,}', [regex]::Escape($env:USERNAME), [regex]::Escape($env:COMPUTERNAME)) | Where-Object { $_ -and $_.Length -gt 3 }
$secretHits = 0; $personalHits = 0
foreach ($f in $files) {
  if ($textExt -notcontains $f.Extension -and $f.Name -ne '.gitignore' -and $f.Name -ne 'VERSION' -and $f.Name -ne 'LICENSE') { continue }
  if ($f.Length -gt 2MB) { continue }
  $txt = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $txt) { continue }
  $rel = $f.FullName.Substring($Root.Length + 1)
  foreach ($p in $secretPatterns) { if ($txt -match $p[1]) { $secretHits++; Res 'FAIL' "secret: $($p[0])" $rel } }
  foreach ($p in $personal) { if ($txt -match "(?i)$p") { $personalHits++; Res 'WARN' 'personal data or path' "$rel (matches $p)" } }
}
if ($secretHits -eq 0) { Res 'OK' 'no secrets found' }
if ($personalHits -eq 0) { Res 'OK' 'no personal paths or names found' }
if (Test-Path (Join-Path $Root 'config\.env')) { Res 'OK' 'config\.env exists but is git-ignored (it holds the engine password)' }

"=== Git ==="
$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) { Res 'OK' 'git is installed' } else { Res 'WARN' 'git is installed' 'not found; install Git for Windows to publish' }

""
"SUMMARY: ok=$script:ok warnings=$script:warn failures=$script:fail"
"RESULT: RELEASE_CHECK=$(if ($script:fail -eq 0) { 'PASS' } else { 'FAIL' })"
if ($script:fail -eq 0) { exit 0 } else { exit 1 }