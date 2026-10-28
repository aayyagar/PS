# Contributing

Thanks for helping make the toolkit better for everyone.

## Reporting a problem
Open an issue with:
- what you ran (cmdlet, menu option or app page),
- Windows and PowerShell versions (`$PSVersionTable`),
- what you expected and what happened, and the relevant lines from `Documents\ADDnsToolkit\Logs`.

Remove domain names, user names and IP addresses you don't want to make public.

## Making a change
1. Fork and create a branch.
2. Keep to these rules:
   - **Read-only by default.** Any command that changes AD or DNS uses `[CmdletBinding(SupportsShouldProcess)]`, returns a result row per object (`Created`, `WouldCreate`, `Failed`...), and logs the change with `Write-ADTLog ... Change`.
   - **Windows PowerShell 5.1 compatible.** No `??`, `?.`, ternaries or `ForEach-Object -Parallel`. Source files stay ASCII.
   - **No new dependencies** beyond the RSAT modules.
   - New public commands get comment-based help (`.SYNOPSIS`, `.EXAMPLE`) and go in `FunctionsToExport` in the manifest.
3. Add or update tests in `tests/` (stub any AD/DNS cmdlet you call), then run:
   ```powershell
   Invoke-Pester ./tests
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   ```
4. Open a pull request describing the change and how you tested it.

## Adding an app page
Pages are built in `Initialize-ADTGuiPages` (`ADDnsToolkit/GUI/ToolkitGui.ps1`) with `New-ADTGuiPage` and the `Add-ADTGui*` helpers. Run AD/DNS work through `Start-ADTGuiJob`, so it happens in a background runspace, and show results with `Set-ADTGuiGrid`. Ask with `Confirm-ADTGui` before any change.
