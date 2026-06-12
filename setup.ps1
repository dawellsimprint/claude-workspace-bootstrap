<#
.SYNOPSIS
  One-paste Imprint Digital Claude Code team workspace bootstrap.

.DESCRIPTION
  Installs Git + Node.js (if missing), installs the Claude Code CLI, clones
  the dawellsimprint/claude-workspace repo, sets the TEAM_TOKEN env var, and
  drops a `cc team` launcher into the user's PowerShell profile.

  Designed to be invoked from a fresh PowerShell window with:

      iex (iwr -UseBasicParsing https://raw.githubusercontent.com/dawellsimprint/claude-workspace/main/scripts/setup.ps1).Content

  Or after cloning, from the repo root:

      .\scripts\setup.ps1

.PARAMETER DryRun
  Print every step but skip installs, clones, env-var writes, and profile edits.

.PARAMETER Token
  Pre-supply the team token (skips the interactive prompt). Prefer the prompt
  in normal use so the token never lives in shell history.

.PARAMETER CloneDir
  Override the clone target. Defaults to "$env:USERPROFILE\Documents\claude-workspace".

.NOTES
  Imprint Digital, claude-workspace v1.26.0+
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Token,
    [string]$CloneDir = (Join-Path $env:USERPROFILE 'Documents\claude-workspace')
)

$ErrorActionPreference = 'Stop'
$RepoUrl = 'https://github.com/dawellsimprint/claude-workspace.git'

function Write-Step  ($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok    ($msg) { Write-Host "    ok  $msg" -ForegroundColor Green }
function Write-Skip  ($msg) { Write-Host "    --  $msg" -ForegroundColor DarkGray }
function Write-Warn2 ($msg) { Write-Host "    !!  $msg" -ForegroundColor Yellow }
function Write-Fail  ($msg) { Write-Host "    XX  $msg" -ForegroundColor Red }

function Test-CommandExists {
    param([string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-OrDryRun {
    param([string]$Label, [scriptblock]$Action)
    if ($DryRun) {
        Write-Skip "[dry-run] would: $Label"
        return
    }
    & $Action
}

Write-Host ""
Write-Host "+----------------------------------------------------------------+" -ForegroundColor Cyan
Write-Host "|  Imprint Digital  -  Claude Code team workspace bootstrap      |" -ForegroundColor Cyan
Write-Host "+----------------------------------------------------------------+" -ForegroundColor Cyan
if ($DryRun) {
    Write-Host "    DRY RUN - no changes will be made"                          -ForegroundColor Yellow
}
Write-Host ""

# ---------------------------------------------------------------------------
# Step 1: Ensure winget is available (Windows 11 ships with it; Windows 10 may not)
# ---------------------------------------------------------------------------
Write-Step "Checking for winget (Windows package manager)"
if (-not (Test-CommandExists 'winget')) {
    Write-Fail "winget not found. Install 'App Installer' from the Microsoft Store, then re-run this script."
    Write-Host "    Direct link: https://apps.microsoft.com/detail/9NBLGGH4NNS1" -ForegroundColor DarkGray
    exit 1
}
Write-Ok "winget present"

# ---------------------------------------------------------------------------
# Step 2: Install Git if missing
# ---------------------------------------------------------------------------
Write-Step "Checking for Git"
if (Test-CommandExists 'git') {
    Write-Ok "Git present ($((git --version) 2>&1))"
} else {
    Write-Warn2 "Git not found - installing via winget"
    Invoke-OrDryRun "winget install Git.Git" {
        winget install -e --id Git.Git --silent --accept-source-agreements --accept-package-agreements | Out-Null
    }
    # PATH refresh - new processes will see git, but this session may not.
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                [System.Environment]::GetEnvironmentVariable('Path','User')
    if ($DryRun -or (Test-CommandExists 'git')) {
        Write-Ok "Git installed"
    } else {
        Write-Fail "Git install reported success but 'git' still not on PATH. Open a new PowerShell window and re-run this script."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 3: Install Node.js LTS if missing (required for npx / mcp-remote)
# ---------------------------------------------------------------------------
Write-Step "Checking for Node.js"
if (Test-CommandExists 'node') {
    $nodeVer = (node -v) 2>&1
    Write-Ok "Node present ($nodeVer)"
} else {
    Write-Warn2 "Node.js not found."
    Write-Host "    Node.js LTS is required for the team MCP servers (meta-marketing, google-workspace, gbp, etc)." -ForegroundColor DarkGray
    Write-Host "    Without Node, those MCPs cannot start and the related skills will silently fail." -ForegroundColor DarkGray
    $reply = Read-Host "    Install Node.js LTS via winget now? [Y/n]"
    if ([string]::IsNullOrWhiteSpace($reply)) { $reply = 'y' }
    if ($reply -match '^[Yy]') {
        Invoke-OrDryRun "winget install OpenJS.NodeJS.LTS" {
            winget install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements | Out-Null
        }
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' +
                    [System.Environment]::GetEnvironmentVariable('Path','User')
        if ($DryRun -or (Test-CommandExists 'node')) {
            Write-Ok "Node.js installed"
        } else {
            Write-Fail "Node install reported success but 'node' still not on PATH. Open a new PowerShell window and re-run this script."
            exit 1
        }
    } else {
        Write-Warn2 "Skipping Node install. Team MCPs and the Claude Code CLI install will not work until Node is on PATH."
        Write-Host "    Install later from https://nodejs.org/en/download/prebuilt-installer then re-run this script." -ForegroundColor DarkGray
        # Skip downstream steps that depend on Node
        Write-Host ""
        Write-Host "    Stopping here. The clone + TEAM_TOKEN + cc launcher steps still need Node first." -ForegroundColor DarkGray
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Step 4: Install the Claude Code CLI globally if missing
# ---------------------------------------------------------------------------
Write-Step "Checking for Claude Code CLI"
if (Test-CommandExists 'claude') {
    Write-Ok "Claude Code CLI present"
} else {
    Write-Warn2 "Claude Code CLI not found - installing via npm"
    Invoke-OrDryRun "npm install -g @anthropic-ai/claude-code" {
        npm install -g '@anthropic-ai/claude-code' 2>&1 | Out-Null
    }
    if ($DryRun -or (Test-CommandExists 'claude')) {
        Write-Ok "Claude Code CLI installed"
    } else {
        Write-Fail "Claude Code install reported success but 'claude' still not on PATH. Open a new PowerShell window and re-run this script."
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Step 5: Clone the team workspace repo
# ---------------------------------------------------------------------------
Write-Step "Setting up the team workspace clone at $CloneDir"
if (Test-Path $CloneDir) {
    # Already exists - check it's actually a git checkout of the right repo
    $isGit = Test-Path (Join-Path $CloneDir '.git')
    if ($isGit) {
        $remoteUrl = & git -C $CloneDir config --get remote.origin.url 2>$null
        if ($remoteUrl -match 'dawellsimprint/claude-workspace') {
            Write-Ok "Existing clone detected - pulling latest"
            Invoke-OrDryRun "git -C $CloneDir pull --ff-only" {
                & git -C $CloneDir pull --ff-only 2>&1 | Out-Null
            }
        } else {
            Write-Warn2 "$CloneDir is a git repo but not the team workspace (remote: $remoteUrl)"
            Write-Warn2 "Leaving it alone. Pass -CloneDir <other-path> to clone elsewhere."
        }
    } else {
        Write-Warn2 "$CloneDir exists but is not a git repo. Leaving it alone."
        Write-Warn2 "Move or delete it and re-run, or pass -CloneDir <other-path>."
    }
} else {
    Invoke-OrDryRun "git clone $RepoUrl $CloneDir" {
        $parent = Split-Path -Parent $CloneDir
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        & git clone $RepoUrl $CloneDir 2>&1 | Out-Null
    }
    Write-Ok "Cloned"
}

# ---------------------------------------------------------------------------
# Step 5b: Register the Matador usage-telemetry hook in settings.json
# Plugin.json SessionEnd hooks do NOT fire on Claude Code for Windows; the
# settings.json hook chain does. This self-locating script adds it idempotently.
# ---------------------------------------------------------------------------
Write-Step "Registering Matador usage telemetry (SessionEnd hook)"
$registerScript = Join-Path $CloneDir 'scripts\register-telemetry-hook.mjs'
if (Test-Path $registerScript) {
    Invoke-OrDryRun "node register-telemetry-hook.mjs" {
        & node $registerScript 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    }
    Write-Ok "Telemetry registered (usage appears in Matador after a clean /exit)"
} else {
    Write-Skip "register-telemetry-hook.mjs not in clone yet - pull the repo and re-run"
}

# ---------------------------------------------------------------------------
# Step 6: Set TEAM_TOKEN as a User-scope env var
# ---------------------------------------------------------------------------
Write-Step "Setting TEAM_TOKEN env var (used by meta-marketing, google-workspace, gbp MCPs)"
$existing = [System.Environment]::GetEnvironmentVariable('TEAM_TOKEN','User')
if ($existing) {
    Write-Skip "TEAM_TOKEN already set at User scope - leaving as is (delete it manually if you need to rotate)"
} else {
    if (-not $Token) {
        Write-Host "    Paste the TEAM_TOKEN value from Alex (Bitwarden 'Imprint Digital - Overall')." -ForegroundColor DarkGray
        Write-Host "    Input is hidden. Press Enter when done." -ForegroundColor DarkGray
        $secure = Read-Host -AsSecureString "    TEAM_TOKEN"
        $Token = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
        )
    }
    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Warn2 "No token provided. Skipping. Set it later with:"
        Write-Host  "        [System.Environment]::SetEnvironmentVariable('TEAM_TOKEN','<value>','User')" -ForegroundColor DarkGray
    } else {
        Invoke-OrDryRun "set User env var TEAM_TOKEN" {
            [System.Environment]::SetEnvironmentVariable('TEAM_TOKEN', $Token, 'User')
        }
        Write-Ok "TEAM_TOKEN saved (visible to new PowerShell windows only - this one still doesn't see it)"
    }
}

# ---------------------------------------------------------------------------
# Step 7: Ensure a `cc team` launcher function in the user's PS profile
# ---------------------------------------------------------------------------
Write-Step "Wiring up the 'cc team' PowerShell launcher"
$profilePath = $PROFILE.CurrentUserAllHosts
if (-not (Test-Path $profilePath)) {
    Invoke-OrDryRun "create $profilePath" {
        New-Item -ItemType File -Path $profilePath -Force | Out-Null
    }
    Write-Ok "Created PowerShell profile"
}
$profileContent = if (Test-Path $profilePath) { Get-Content $profilePath -Raw } else { '' }
if ($profileContent -match '(?ms)^# >>>\s*claude-workspace cc launcher\s*>>>') {
    Write-Skip "cc launcher already in profile - leaving it alone"
} else {
    $launcher = @"

# >>> claude-workspace cc launcher >>>
# Added by claude-workspace setup.ps1 - do not edit between the >>> / <<< markers
function cc {
    param([string]`$Target = 'team')
    `$paths = @{
        'team' = '$($CloneDir -replace "'", "''")'
    }
    `$key = `$Target.ToLower()
    if (-not `$paths.ContainsKey(`$key)) {
        Write-Host "Unknown workspace: '`$Target'. Known: `$(`$paths.Keys -join ', ')" -ForegroundColor Yellow
        return
    }
    `$path = `$paths[`$key]
    if (-not (Test-Path `$path)) {
        Write-Host "Path not found: `$path" -ForegroundColor Red
        return
    }
    Set-Location -LiteralPath `$path
    Write-Host "-> `$Target workspace (`$path)" -ForegroundColor Cyan
    claude @args
}
# <<< claude-workspace cc launcher <<<
"@
    Invoke-OrDryRun "append cc launcher to $profilePath" {
        Add-Content -Path $profilePath -Value $launcher
    }
    Write-Ok "cc launcher added (will be available in new PowerShell windows)"
}

# ---------------------------------------------------------------------------
# Step 8: Clean up an empty claude-workspace-inline plugin dir if present
# This is the half-installed marketplace plugin that caused Cody + Alicia grief.
# ---------------------------------------------------------------------------
Write-Step "Checking for a broken 'claude-workspace-inline' marketplace plugin"
$pluginRoots = @(
    (Join-Path $env:USERPROFILE '.claude\plugins\claude-workspace-inline'),
    (Join-Path $env:USERPROFILE '.config\claude\plugins\claude-workspace-inline')
)
$cleaned = $false
foreach ($p in $pluginRoots) {
    if (Test-Path $p) {
        $entries = Get-ChildItem $p -Force -ErrorAction SilentlyContinue
        if (-not $entries -or $entries.Count -eq 0) {
            Invoke-OrDryRun "remove empty $p" {
                Remove-Item $p -Recurse -Force
            }
            Write-Ok "Removed empty $p"
            $cleaned = $true
        } else {
            Write-Skip "$p has content - leaving alone (may be a working install)"
        }
    }
}
if (-not $cleaned) { Write-Skip "No empty marketplace plugin dir found" }

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "+----------------------------------------------------------------+" -ForegroundColor Green
Write-Host "|  Setup complete                                                |" -ForegroundColor Green
Write-Host "+----------------------------------------------------------------+" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Close this PowerShell window."
Write-Host "  2. Open a NEW PowerShell window (so the env var + cc launcher load)."
Write-Host "  3. Type:  cc team"
Write-Host "  4. Inside Claude, run:  /mcp"
Write-Host "     You should see meta-marketing, google-workspace, gbp showing 'connected'."
Write-Host ""
Write-Host "Stuck? DM Alex on Slack or post in #claude-code." -ForegroundColor DarkGray
Write-Host ""
