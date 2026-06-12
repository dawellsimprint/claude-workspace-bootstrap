<#
.SYNOPSIS
  One-paste patch: register the Matador usage-telemetry hook for an existing
  claude-workspace install.

.DESCRIPTION
  Plugin.json SessionEnd hooks don't fire on Claude Code for Windows, so the
  usage hook has to live in ~/.claude/settings.json instead. This script finds
  your existing claude-workspace clone (wherever it is), pulls the latest, and
  runs the idempotent registration script. Safe to run more than once.

  Run with:
      iex (iwr -UseBasicParsing https://raw.githubusercontent.com/dawellsimprint/claude-workspace-bootstrap/main/patch-telemetry.ps1).Content
#>

$ErrorActionPreference = 'Stop'
function Say  ($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok   ($m) { Write-Host "    ok  $m" -ForegroundColor Green }
function Fail ($m) { Write-Host "    XX  $m" -ForegroundColor Red }

Say "Locating your claude-workspace clone"
$candidates = New-Object System.Collections.Generic.List[string]

# 1) Paths recorded in Claude's own config (most reliable - it's where the plugin loads from)
$cj = Join-Path $env:USERPROFILE '.claude.json'
if (Test-Path $cj) {
    try {
        $txt = Get-Content $cj -Raw
        foreach ($m in [regex]::Matches($txt, '"([^"]*claude-workspace[^"]*)"')) {
            $candidates.Add(($m.Groups[1].Value -replace '\\\\', '\'))
        }
    } catch {}
}
# 2) Common clone locations
$candidates.Add((Join-Path $env:USERPROFILE 'Documents\claude-workspace'))
$candidates.Add((Join-Path $env:USERPROFILE 'claude-workspace-repo'))
$candidates.Add((Join-Path $env:USERPROFILE 'claude-workspace'))

$dir = $null
foreach ($c in $candidates) {
    if ($c -and (Test-Path (Join-Path $c '.git')) -and (Test-Path (Join-Path $c '.claude-plugin'))) { $dir = $c; break }
}

if (-not $dir) {
    Fail "Couldn't find your claude-workspace clone."
    Write-Host "    Find it (the folder you 'cc team' into), then run, replacing the path:" -ForegroundColor DarkGray
    Write-Host '        node "C:\path\to\claude-workspace\scripts\register-telemetry-hook.mjs"' -ForegroundColor DarkGray
    return
}
Ok "Found: $dir"

Say "Pulling the latest"
try { & git -C $dir pull --ff-only 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray } }
catch { Write-Host "    (pull skipped: $($_.Exception.Message))" -ForegroundColor DarkGray }

$register = Join-Path $dir 'scripts\register-telemetry-hook.mjs'
if (-not (Test-Path $register)) {
    Fail "register-telemetry-hook.mjs not found after pull. Ping Alex in #claude-code."
    return
}

Say "Registering the telemetry hook"
& node $register 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }

Write-Host ""
Write-Host "Done. Restart Claude Code (close it, open a fresh 'cc team')." -ForegroundColor Green
Write-Host "Your usage records on a CLEAN exit - type /exit when done, don't just close the window." -ForegroundColor Green
Write-Host ""
