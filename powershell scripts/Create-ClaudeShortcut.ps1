# Create-ClaudeShortcut.ps1
# Run this ONCE to create a desktop shortcut that launches Claude via the wrapper.
# After running, use the new shortcut instead of the old Claude one.

$ScriptFolder  = $PSScriptRoot
$LaunchScript  = Join-Path $ScriptFolder "Launch-Claude.ps1"
$ShortcutPath  = "$env:USERPROFILE\Desktop\Claude Desktop.lnk"
$IconSearch    = "$env:LOCALAPPDATA\AnthropicClaude\Claude.exe"

# Verify wrapper script exists
if (-not (Test-Path $LaunchScript)) {
    Write-Host "ERROR: Launch-Claude.ps1 not found in $ScriptFolder" -ForegroundColor Red
    Write-Host "Make sure all three scripts are in the same folder." -ForegroundColor Yellow
    exit 1
}

# Find Claude.exe for the icon
$IconPath = $IconSearch
if (-not (Test-Path $IconPath)) {
    $msix = Get-ChildItem "$env:LOCALAPPDATA\Packages" -Filter "Claude_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($msix) {
        $found = Get-ChildItem $msix.FullName -Filter "Claude.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $IconPath = $found.FullName }
    }
}

# Build the shortcut
$WshShell  = New-Object -ComObject WScript.Shell
$Shortcut  = $WshShell.CreateShortcut($ShortcutPath)

$Shortcut.TargetPath      = "powershell.exe"
$Shortcut.Arguments       = "-ExecutionPolicy Bypass -WindowStyle Minimized -File `"$LaunchScript`""
$Shortcut.WorkingDirectory = $ScriptFolder
$Shortcut.Description     = "Launch Claude Desktop with automatic cleanup on exit"

# Use Claude's own icon if found, otherwise default PowerShell icon
if (Test-Path $IconPath) {
    $Shortcut.IconLocation = "$IconPath,0"
} else {
    Write-Host "Claude.exe not found for icon - shortcut will use default icon." -ForegroundColor Yellow
}

$Shortcut.Save()

Write-Host ""
Write-Host "Shortcut created on your Desktop: Claude Desktop.lnk" -ForegroundColor Green
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host "  1. Use the new 'Claude Desktop' shortcut on your desktop from now on"
Write-Host "  2. You can delete or rename the old Claude shortcut to avoid confusion"
Write-Host "  3. Cleanup will run automatically every time you close Claude"
Write-Host ""
Read-Host "Press Enter to close"
