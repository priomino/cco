# versions.ps1 - helpers for upgrade.ps1 and rollback.ps1. Dot-source after common.ps1.
function Load-CcoCfg {
  $cfg = @{}
  if (Test-Path $CcoEnvFile) {
    foreach ($line in Get-Content $CcoEnvFile) {
      if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*([^#\s]*)') { $cfg[$Matches[1]] = $Matches[2] }
    }
  }
  return $cfg
}

# Describes an upgradable component: its floating tag, snapshot tag pattern, version regex and build script.
function Get-CcoComponent([string]$name) {
  $cfg = Load-CcoCfg
  if ($name -eq 'engine') {
    $img = if ($cfg['CCO_ENGINE_IMAGE']) { $cfg['CCO_ENGINE_IMAGE'] } else { 'cco-engine' }
    return @{ Name = 'engine'; Image = $img; Floating = "${img}:cpu"; SnapPrefix = "${img}:"; SnapSuffix = '-cpu'
              Regex = 'unsloth-([0-9][0-9A-Za-z._+-]*?)\.dist-info'; Build = 'build-engine.ps1'; PinKey = 'CCO_UNSLOTH_VERSION' }
  }
  $img = if ($cfg['CCO_CLAUDE_IMAGE']) { $cfg['CCO_CLAUDE_IMAGE'] } else { 'cco-claude' }
  return @{ Name = 'claude'; Image = $img; Floating = "${img}:cli"; SnapPrefix = "${img}:"; SnapSuffix = ''
            Regex = 'claude=\D*(\d+\.\d+\.\d+)'; Build = 'build-claude.ps1'; PinKey = 'CCO_CLAUDE_VERSION' }
}

# Reads the version recorded inside an image (/home/cco/.cco-versions). Returns the version string or $null.
function Get-ImageVersion($comp, [string]$tag) {
  $r = Run-Docker "run --rm $tag cat /home/cco/.cco-versions" 90 $null 2
  if ($r.Exit -eq 0 -and $r.Text -match $comp.Regex) { return $Matches[1] }
  return $null
}

# Versions for which a snapshot tag exists.
function Get-CcoSnapshots($comp) {
  $r = Run-Docker "images --format `"{{.Repository}}:{{.Tag}}`" $($comp.Image)" 30 $null 2
  $out = @()
  foreach ($l in ($r.Text -split "`n")) {
    $t = $l.Trim()
    $minLen = $comp.SnapPrefix.Length + $comp.SnapSuffix.Length
    if ($t.StartsWith($comp.SnapPrefix) -and $t.EndsWith($comp.SnapSuffix) -and $t.Length -gt $minLen) {
      $v = $t.Substring($comp.SnapPrefix.Length, $t.Length - $minLen)
      if ($v -match '^\d') { $out += $v }
    }
  }
  return @($out | Sort-Object -Unique)
}

# Points the floating tag at the snapshot of a version. Returns $true or $false.
function Set-CcoFloatingTag($comp, [string]$version) {
  $snap = $comp.SnapPrefix + $version + $comp.SnapSuffix
  $r = Run-Docker "image inspect --format `"{{.Id}}`" $snap" 20 $null 2
  if ($r.Exit -ne 0) { return $false }
  $t = Run-Docker "tag $snap $($comp.Floating)" 20 $null 2
  return ($t.Exit -eq 0)
}