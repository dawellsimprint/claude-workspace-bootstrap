#!/usr/bin/env bash
# Imprint Digital - Claude Code team workspace bootstrap (macOS / Linux)
#
# Installs Git + Node.js (if missing), installs the Claude Code CLI, clones the
# dawellsimprint/claude-workspace repo, sets the TEAM_TOKEN env var, and drops
# a `cc team` launcher into the user's shell rc.
#
# Designed to be invoked from a fresh terminal with:
#
#     curl -fsSL https://raw.githubusercontent.com/dawellsimprint/claude-workspace/main/scripts/setup.sh | bash
#
# Or after cloning:
#
#     ./scripts/setup.sh
#
# Flags:
#   --dry-run         Print every step but skip installs, clones, env writes.
#   --token <VALUE>   Pre-supply the team token (skips the interactive prompt).
#   --clone-dir <DIR> Override the clone target. Default: ~/Documents/claude-workspace
#
# Imprint Digital, claude-workspace v1.26.0+

set -euo pipefail

REPO_URL='https://github.com/dawellsimprint/claude-workspace.git'
CLONE_DIR="${HOME}/Documents/claude-workspace"
DRY_RUN=0
TOKEN=''

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)   DRY_RUN=1; shift ;;
        --token)     TOKEN="$2"; shift 2 ;;
        --clone-dir) CLONE_DIR="$2"; shift 2 ;;
        *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
done

# ---------------- pretty printers ----------------
c_cyan='\033[0;36m'; c_green='\033[0;32m'; c_yel='\033[0;33m'
c_red='\033[0;31m';  c_dim='\033[2m';      c_off='\033[0m'

step() { printf "${c_cyan}==> %s${c_off}\n" "$*"; }
ok()   { printf "    ${c_green}ok${c_off}  %s\n" "$*"; }
skip() { printf "    ${c_dim}--  %s${c_off}\n" "$*"; }
warn() { printf "    ${c_yel}!!${c_off}  %s\n" "$*"; }
fail() { printf "    ${c_red}XX${c_off}  %s\n" "$*"; }

run() {
    local label="$1"; shift
    if [[ $DRY_RUN -eq 1 ]]; then
        skip "[dry-run] would: $label"
        return 0
    fi
    "$@"
}

has() { command -v "$1" >/dev/null 2>&1; }

# ---------------- banner ----------------
echo
echo "+----------------------------------------------------------------+"
echo "|  Imprint Digital  -  Claude Code team workspace bootstrap      |"
echo "+----------------------------------------------------------------+"
[[ $DRY_RUN -eq 1 ]] && printf "    ${c_yel}DRY RUN - no changes will be made${c_off}\n"
echo

# ---------------- detect package manager ----------------
PKG=''
if [[ "$OSTYPE" == darwin* ]]; then
    if ! has brew; then
        fail "Homebrew not found. Install it first: https://brew.sh"
        exit 1
    fi
    PKG=brew
elif has apt-get; then
    PKG=apt
else
    fail "Unsupported platform. Supported: macOS (brew) or Debian/Ubuntu (apt)."
    exit 1
fi

# ---------------- Step 1: Git ----------------
step "Checking for Git"
if has git; then
    ok "Git present ($(git --version))"
else
    warn "Git not found - installing via $PKG"
    if [[ "$PKG" == brew ]]; then
        run "brew install git" brew install git
    else
        run "sudo apt-get install -y git" sudo apt-get update -qq
        run "sudo apt-get install -y git" sudo apt-get install -y git
    fi
    has git && ok "Git installed" || { fail "Git install failed"; exit 1; }
fi

# ---------------- Step 2: Node.js LTS ----------------
step "Checking for Node.js"
if has node; then
    ok "Node present ($(node -v))"
else
    warn "Node.js not found."
    printf "    Node.js LTS is required for the team MCP servers (meta-marketing, google-workspace, gbp, etc).\n"
    printf "    Without Node, those MCPs cannot start and the related skills will silently fail.\n"
    read -r -p "    Install Node.js LTS via $PKG now? [Y/n] " reply
    reply="${reply:-y}"
    if [[ "$reply" =~ ^[Yy] ]]; then
        if [[ "$PKG" == brew ]]; then
            run "brew install node" brew install node
        else
            run "install Node via NodeSource" bash -c '
                curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
                sudo apt-get install -y nodejs
            '
        fi
        has node && ok "Node.js installed" || { fail "Node install failed"; exit 1; }
    else
        warn "Skipping Node install. Team MCPs and the Claude Code CLI install will not work until Node is on PATH."
        printf "    Install later from https://nodejs.org/en/download then re-run this script.\n"
        echo
        printf "    Stopping here. The clone + TEAM_TOKEN + cc launcher steps still need Node first.\n"
        exit 0
    fi
fi

# ---------------- Step 3: Claude Code CLI ----------------
step "Checking for Claude Code CLI"
if has claude; then
    ok "Claude Code CLI present"
else
    warn "Claude Code CLI not found - installing via npm"
    run "npm install -g @anthropic-ai/claude-code" npm install -g '@anthropic-ai/claude-code'
    has claude && ok "Claude Code CLI installed" || { fail "Claude install failed"; exit 1; }
fi

# ---------------- Step 4: Clone team workspace ----------------
step "Setting up the team workspace clone at $CLONE_DIR"
if [[ -d "$CLONE_DIR" ]]; then
    if [[ -d "$CLONE_DIR/.git" ]]; then
        remote=$(git -C "$CLONE_DIR" config --get remote.origin.url 2>/dev/null || echo '')
        if [[ "$remote" == *dawellsimprint/claude-workspace* ]]; then
            ok "Existing clone detected - pulling latest"
            run "git -C $CLONE_DIR pull --ff-only" git -C "$CLONE_DIR" pull --ff-only >/dev/null 2>&1 || warn "pull failed - leaving as is"
        else
            warn "$CLONE_DIR is a git repo but not the team workspace (remote: $remote)"
            warn "Leaving it alone. Pass --clone-dir <other-path> to clone elsewhere."
        fi
    else
        warn "$CLONE_DIR exists but is not a git repo. Leaving it alone."
    fi
else
    mkdir -p "$(dirname "$CLONE_DIR")"
    run "git clone $REPO_URL $CLONE_DIR" git clone "$REPO_URL" "$CLONE_DIR" >/dev/null 2>&1
    ok "Cloned"
fi

# ---------------- Step 5: TEAM_TOKEN ----------------
RC=''
case "${SHELL:-}" in
    *zsh*)  RC="$HOME/.zshrc"  ;;
    *bash*) RC="$HOME/.bashrc" ;;
    *)      RC="$HOME/.zshrc"  ;;   # zsh is the macOS default
esac

step "Setting TEAM_TOKEN env var (used by meta-marketing, google-workspace, gbp MCPs)"
if grep -q '^export TEAM_TOKEN=' "$RC" 2>/dev/null; then
    skip "TEAM_TOKEN already in $RC - leaving as is"
else
    if [[ -z "$TOKEN" ]]; then
        printf "    Paste the TEAM_TOKEN value from Alex (Bitwarden 'Imprint Digital - Overall').\n"
        printf "    Input is hidden. Press Enter when done.\n"
        read -rs -p "    TEAM_TOKEN: " TOKEN
        echo
    fi
    if [[ -z "$TOKEN" ]]; then
        warn "No token provided. Skipping. Add later: echo 'export TEAM_TOKEN=<value>' >> $RC"
    else
        run "append TEAM_TOKEN export to $RC" bash -c "echo 'export TEAM_TOKEN=\"$TOKEN\"' >> '$RC'"
        ok "TEAM_TOKEN saved to $RC (visible to NEW terminals only)"
    fi
fi

# ---------------- Step 6: cc team launcher ----------------
step "Wiring up the 'cc team' launcher function"
if grep -q '# >>> claude-workspace cc launcher >>>' "$RC" 2>/dev/null; then
    skip "cc launcher already in $RC - leaving alone"
else
    LAUNCHER=$(cat <<EOF

# >>> claude-workspace cc launcher >>>
# Added by claude-workspace setup.sh - do not edit between the >>> / <<< markers
cc() {
    local target="\${1:-team}"
    local path=""
    case "\$target" in
        team) path="$CLONE_DIR" ;;
        *) echo "Unknown workspace: '\$target'. Known: team" >&2; return 1 ;;
    esac
    if [[ ! -d "\$path" ]]; then
        echo "Path not found: \$path" >&2; return 1
    fi
    shift || true
    cd "\$path" && echo "-> \$target workspace (\$path)" && claude "\$@"
}
# <<< claude-workspace cc launcher <<<
EOF
)
    run "append cc launcher to $RC" bash -c "printf '%s\n' \"\$LAUNCHER\" >> '$RC'"
    ok "cc launcher added to $RC"
fi

# ---------------- Done ----------------
echo
echo "+----------------------------------------------------------------+"
printf "${c_green}|  Setup complete                                                |${c_off}\n"
echo "+----------------------------------------------------------------+"
echo
echo "Next steps:"
echo "  1. Close this terminal."
echo "  2. Open a new terminal (so the env var + cc launcher load)."
echo "  3. Type:  cc team"
echo "  4. Inside Claude, run:  /mcp"
echo "     You should see meta-marketing, google-workspace, gbp showing 'connected'."
echo
printf "${c_dim}Stuck? DM Alex on Slack or post in #claude-code.${c_off}\n"
echo
