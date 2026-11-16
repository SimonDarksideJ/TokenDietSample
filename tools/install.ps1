<#
.SYNOPSIS
  Installs the agents, CLAUDE.md snippet, settings and usage tools from this repo for the current Windows user.

.DESCRIPTION
  Every source file is read from the repo that holds this script, which is the parent of its tools folder.
  Nothing is downloaded, extracted or read from the user profile.

  Makes these changes (all under %USERPROFILE%\.claude):
    agents\*.md                -> .claude\agents\                (every agent file in the repo)
    CLAUDE-md-snippet.md       -> appended to .claude\CLAUDE.md  (once; skipped if its first heading, '## Delegation policy', is already there)
    settings.example.json      -> its env keys merged into .claude\settings.json (backup written first)
    tools\analyze_usage_v3.py  -> .claude\tools\analyze_usage_v3.py
    tools\PLAYBOOK.md          -> .claude\tools\PLAYBOOK.md

  Run from any folder (cmd, PowerShell, or the VS Code terminal):
    <repo>\tools\install.cmd
    powershell -NoProfile -ExecutionPolicy Bypass -File <repo>\tools\install.ps1

  Options:
    -SubagentModel sonnet|haiku|none   override CLAUDE_CODE_SUBAGENT_MODEL from settings.example.json; 'none' leaves settings.json untouched
    -NoClaudeMd                        leave CLAUDE.md untouched (install and uninstall)
    -Uninstall                         remove the repo's agents, the snippet sections, the example env keys and the tools copies
#>
param(
  [ValidateSet('sonnet','haiku','none')][string]$SubagentModel,
  [switch]$NoClaudeMd,
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$claudeDir = Join-Path $env:USERPROFILE '.claude'
$agentsDir = Join-Path $claudeDir 'agents'
$toolsDir  = Join-Path $claudeDir 'tools'
$claudeMd  = Join-Path $claudeDir 'CLAUDE.md'
$settings  = Join-Path $claudeDir 'settings.json'
$toolFiles = @('analyze_usage_v3.py','PLAYBOOK.md')

function Read-Utf8($path) { [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8) }
function Write-Utf8($path, $text) { [System.IO.File]::WriteAllText($path, $text, $utf8NoBom) }

function Resolve-RepoRoot($start) {
  # The repo root is the parent of the tools folder that holds this script.
  # Only this repo is used: no zip extraction and no fallback to the user profile.
  $root = [System.IO.Path]::GetFullPath((Join-Path $start '..')).TrimEnd('\')
  if ($root -ieq [System.IO.Path]::GetFullPath($claudeDir).TrimEnd('\')) {
    throw "This copy of install.ps1 runs from $claudeDir. Run the install.ps1 in the repo's tools folder instead."
  }
  $required = @('agents','CLAUDE-md-snippet.md','settings.example.json') + ($toolFiles | ForEach-Object { "tools\$_" })
  $missing = @($required | Where-Object { -not (Test-Path (Join-Path $root $_)) })
  if ($missing.Count) { throw "Repo at $root is incomplete. Missing: $($missing -join ', ')" }
  return $root
}

function Load-Settings {
  if (-not (Test-Path $settings)) { return [pscustomobject]@{} }
  $raw = Read-Utf8 $settings
  if (-not $raw.Trim()) { return [pscustomobject]@{} }
  return ($raw | ConvertFrom-Json)
}
function Save-Settings($obj) {
  if (Test-Path $settings) {
    Copy-Item $settings ("$settings.bak-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  }
  Write-Utf8 $settings ($obj | ConvertTo-Json -Depth 50)
}
function Find-Heading($text, $heading) {
  [regex]::Match($text, '(?m)^' + [regex]::Escape($heading) + '[ \t]*\r?$')
}

# Everything the script installs or removes is defined by the repo files.
$repo = Resolve-RepoRoot $scriptDir
Write-Host "repo root: $repo"
$agentFiles = @(Get-ChildItem -LiteralPath (Join-Path $repo 'agents') -Filter '*.md' -File | Where-Object { $_.Extension -eq '.md' })
if (-not $agentFiles.Count) { throw "No agent files in $repo\agents" }
$snippet = Read-Utf8 (Join-Path $repo 'CLAUDE-md-snippet.md')
$snippetHeadings = @([regex]::Matches($snippet, '(?m)^## (.+?)[ \t]*\r?$') | ForEach-Object { $_.Groups[1].Value })
if (-not $snippetHeadings.Count) { throw "CLAUDE-md-snippet.md has no '## ' heading" }
$marker = '## ' + $snippetHeadings[0]
$example = (Read-Utf8 (Join-Path $repo 'settings.example.json')) | ConvertFrom-Json
$envKeys = [ordered]@{}
if ($example.env) { foreach ($p in $example.env.PSObject.Properties) { $envKeys[$p.Name] = $p.Value } }
if ($SubagentModel -and $SubagentModel -ne 'none') { $envKeys['CLAUDE_CODE_SUBAGENT_MODEL'] = $SubagentModel }

if ($Uninstall) {
  foreach ($f in $agentFiles) {
    $p = Join-Path $agentsDir $f.Name
    if (Test-Path $p) { Remove-Item $p; Write-Host "removed agent: $($f.Name)" }
  }
  if (-not $NoClaudeMd -and (Test-Path $claudeMd)) {
    $txt = Read-Utf8 $claudeMd
    $m = Find-Heading $txt $marker
    if ($m.Success) {
      # Remove from the marker through the last snippet section, up to the next other '## ' heading or EOF.
      $rest = $txt.Substring($m.Index)
      $names = ($snippetHeadings | ForEach-Object { [regex]::Escape($_) }) -join '|'
      $next = [regex]::Match($rest, "(?m)^## (?!(?:$names)[ \t]*\r?$)")
      $cut = if ($next.Success) { $rest.Substring($next.Index) } else { '' }
      $nl = if ($txt.Contains("`r`n")) { "`r`n" } else { "`n" }
      Write-Utf8 $claudeMd (($txt.Substring(0, $m.Index) + $cut).TrimEnd() + $nl)
      Write-Host "CLAUDE.md: removed sections $($snippetHeadings -join ', ')"
    }
  }
  if ($SubagentModel -ne 'none' -and (Test-Path $settings)) {
    $obj = Load-Settings
    $removed = @()
    if ($obj.PSObject.Properties.Name -contains 'env' -and $obj.env) {
      foreach ($k in @($envKeys.Keys)) {
        if ($obj.env.PSObject.Properties.Name -contains $k) { $obj.env.PSObject.Properties.Remove($k); $removed += $k }
      }
    }
    if ($removed.Count) {
      Save-Settings $obj
      Write-Host "settings.json: removed env $($removed -join ', ') (backup written)"
    }
  }
  foreach ($f in $toolFiles) {
    $p = Join-Path $toolsDir $f
    if (Test-Path $p) { Remove-Item $p; Write-Host "removed: $p" }
  }
  Write-Host 'Uninstall complete. Restart Claude Code.'
  exit 0
}

New-Item -ItemType Directory -Force -Path $agentsDir, $toolsDir | Out-Null

# 1. agents
foreach ($f in $agentFiles) {
  Copy-Item $f.FullName -Destination (Join-Path $agentsDir $f.Name) -Force
  Write-Host "agent installed: $agentsDir\$($f.Name)"
}

# 2. CLAUDE.md
if (-not $NoClaudeMd) {
  $existing = if (Test-Path $claudeMd) { Read-Utf8 $claudeMd } else { '' }
  if ((Find-Heading $existing $marker).Success) {
    Write-Host "CLAUDE.md already contains '$marker' - left unchanged (edit by hand to update)"
  } else {
    $nl  = if ($existing -and -not $existing.Contains("`r`n")) { "`n" } else { "`r`n" }
    $sep = if ($existing.Trim()) { $nl + $nl } else { '' }
    $body = $snippet.Trim().Replace("`r`n", "`n").Replace("`n", $nl)
    Write-Utf8 $claudeMd ($existing.TrimEnd() + $sep + $body + $nl)
    Write-Host "CLAUDE.md updated: $claudeMd"
  }
}

# 3. settings.json env
if ($SubagentModel -eq 'none') {
  Write-Host 'settings.json: untouched (-SubagentModel none)'
} elseif (-not $envKeys.Count) {
  Write-Host 'settings.json: untouched (settings.example.json has no env keys)'
} else {
  $obj = Load-Settings
  if (-not ($obj.PSObject.Properties.Name -contains 'env') -or -not $obj.env) {
    $obj | Add-Member -Force -NotePropertyName env -NotePropertyValue ([pscustomobject]@{})
  }
  foreach ($k in $envKeys.Keys) {
    if ($obj.env.PSObject.Properties.Name -contains $k) { $obj.env.$k = $envKeys[$k] }
    else { $obj.env | Add-Member -NotePropertyName $k -NotePropertyValue $envKeys[$k] }
    Write-Host "settings.json: env.$k = $($envKeys[$k])"
  }
  Save-Settings $obj
  Write-Host 'settings.json: saved (backup written alongside)'
}

# 4. tools
foreach ($f in $toolFiles) {
  Copy-Item (Join-Path (Join-Path $repo 'tools') $f) -Destination (Join-Path $toolsDir $f) -Force
  Write-Host "installed: $toolsDir\$f"
}

Write-Host ''
Write-Host 'Done. Next:'
Write-Host '  1. Restart Claude Code / VS Code (a brand-new agents directory needs one restart; env changes need a new session).'
Write-Host "  2. Check the $($agentFiles.Count) agents are listed: run /agents in Claude Code, or  dir `"$agentsDir`""
Write-Host '  3. Test:  Use the scout agent to find where <symbol> is defined.   The transcript should name scout, not general-purpose.'
Write-Host "  4. Baseline now:  py `"$toolsDir\analyze_usage_v3.py`" --days 7"
