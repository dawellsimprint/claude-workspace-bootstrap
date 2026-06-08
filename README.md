# Claude Workspace Bootstrap

One-paste installer for the Imprint Digital Claude Code team workspace.

This is the **public installer** for the (private) team workspace at [dawellsimprint/claude-workspace](https://github.com/dawellsimprint/claude-workspace). The team workspace itself stays private. Only this tiny installer needs to be world-readable so teammates can `iwr | iex` it on a fresh machine.

## For team members

Open PowerShell on Windows and paste:

```powershell
iwr https://raw.githubusercontent.com/dawellsimprint/claude-workspace-bootstrap/main/setup.ps1 | iex
```

On macOS or Linux:

```bash
curl -fsSL https://raw.githubusercontent.com/dawellsimprint/claude-workspace-bootstrap/main/setup.sh | bash
```

The script will:

1. Check for `winget` (Windows) or your package manager (mac/linux)
2. Install Git if missing
3. Install Node.js LTS if missing (prompts first - needed for team MCPs)
4. Install the Claude Code CLI via npm
5. Clone the private team workspace to `~\Documents\claude-workspace` (Git Credential Manager will pop a browser for the first-time auth)
6. Prompt you for `TEAM_TOKEN` (DM Alex for the value) and set it as a User-scope env var
7. Drop a `cc team` launcher function into your PowerShell profile

Then close your terminal, open a new one, type `cc team`, and you're in.

## For maintainers

The canonical scripts live in the private team repo at [dawellsimprint/claude-workspace/scripts/](https://github.com/dawellsimprint/claude-workspace/tree/main/scripts). This public mirror should be updated whenever those change.

Manual sync until the auto-sync workflow lands:

```powershell
cp "C:\Users\dawel\claude-workspace-repo\scripts\setup.ps1" .\setup.ps1
cp "C:\Users\dawel\claude-workspace-repo\scripts\setup.sh" .\setup.sh
git add setup.ps1 setup.sh
git commit -m "Sync from claude-workspace@<short-sha>"
git push
```

## License

MIT
