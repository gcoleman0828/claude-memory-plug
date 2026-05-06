# Launch-Claude.ps1
# Launches Claude Desktop (MSIX/Store version) and runs cleanup when it closes.

$AppID         = "Claude_pzs8sxrjxfjjc!Claude"
$CleanupScript = Join-Path $PSScriptRoot "Cleanup-ClaudeDesktop.ps1"

if (-not (Test-Path $CleanupScript)) {
    Write-Host "ERROR: Cleanup-ClaudeDesktop.ps1 not found in $PSScriptRoot" -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "Starting Claude Desktop..." -ForegroundColor Cyan
Write-Host "Cleanup will run automatically when you close Claude." -ForegroundColor Gray

# Launch Claude via the Store app launcher
Start-Process "explorer.exe" -ArgumentList "shell:appsFolder\$AppID"

# Wait for the main Claude window to appear
Write-Host "Waiting for Claude to start..." -ForegroundColor Gray
$mainProc = $null
$attempts = 0
while ($attempts -lt 20) {
    Start-Sleep -Seconds 2
    $mainProc = Get-Process -Name "claude" -ErrorAction SilentlyContinue | 
                Where-Object { $_.MainWindowTitle -eq "Claude" -and $_.MainWindowHandle -ne 0 } |
                Select-Object -First 1
    if ($mainProc) { break }
    $attempts++
}

if (-not $mainProc) {
    Write-Host "Could not detect Claude main window - cleanup will run anyway." -ForegroundColor Yellow
} else {
    Write-Host "Claude is running (PID $($mainProc.Id), window handle $($mainProc.MainWindowHandle))." -ForegroundColor Gray
    Write-Host "Waiting for you to close it..." -ForegroundColor Gray

    # Poll every 3 seconds watching for the window handle to drop to 0
    while ($true) {
        Start-Sleep -Seconds 3
        $check = Get-Process -Id $mainProc.Id -ErrorAction SilentlyContinue
        if (-not $check) {
            Write-Host "Claude process exited." -ForegroundColor Gray
            break
        }
        if ($check.MainWindowHandle -eq 0) {
            Write-Host "Claude main window closed." -ForegroundColor Gray
            break
        }
    }
}

# Brief pause to let Claude finish cleanup of its own before we run ours
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "Running cleanup..." -ForegroundColor Yellow

& $CleanupScript -Force

Write-Host ""
Write-Host "Done. This window will close in 5 seconds." -ForegroundColor Green
Start-Sleep -Seconds 5
