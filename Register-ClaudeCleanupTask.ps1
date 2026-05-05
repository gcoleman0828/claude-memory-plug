# Register-ClaudeCleanupTask.ps1
# Run this ONCE as Administrator to set up automatic cleanup on Claude exit.
# Both scripts must be in the same folder.
#
# To remove the task later:
#   Unregister-ScheduledTask -TaskName "ClaudeDesktopCleanup" -Confirm:$false

#Requires -RunAsAdministrator

$TaskName   = "ClaudeDesktopCleanup"
$ScriptName = "Cleanup-ClaudeDesktop.ps1"
$ScriptPath = Join-Path $PSScriptRoot $ScriptName

if (-not (Test-Path $ScriptPath)) {
    Write-Host "ERROR: Cannot find $ScriptName at: $ScriptPath" -ForegroundColor Red
    Write-Host "Make sure both scripts are in the same folder and try again." -ForegroundColor Yellow
    exit 1
}

Write-Host "Cleanup script found at: $ScriptPath" -ForegroundColor Cyan

# Remove existing task if present
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Removing existing task '$TaskName'..." -ForegroundColor Yellow
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Enable process termination auditing so Event 4689 fires when Claude exits
Write-Host "Enabling Process Termination auditing..."
try {
    auditpol /set /subcategory:"Process Termination" /success:enable /failure:disable | Out-Null
    Write-Host "Process auditing enabled." -ForegroundColor Green
} catch {
    Write-Host "Could not set audit policy - you may need to enable it manually." -ForegroundColor Yellow
    Write-Host "Local Security Policy > Advanced Audit Policy > Detailed Tracking > Audit Process Termination" -ForegroundColor Yellow
}

# Build the action - runs cleanup silently in background
$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`" -Silent -Force"

# Trigger 1: On user logon (lightweight, always registers)
$TriggerLogon = New-ScheduledTaskTrigger -AtLogOn

# Trigger 2: Daily at 3 AM as a reliable fallback
$TriggerDaily = New-ScheduledTaskTrigger -Daily -At "03:00"

# Task settings
$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 10) `
    -MultipleInstances IgnoreNew `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries

# Principal - run as current user
$Principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Highest

# Register with logon + daily triggers
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $Action `
        -Trigger @($TriggerLogon, $TriggerDaily) `
        -Settings $Settings `
        -Principal $Principal `
        -Description "Cleans Claude Desktop VM bundles and cache. Preserves memory, settings, and credentials." `
        -Force | Out-Null

    Write-Host ""
    Write-Host "Task '$TaskName' registered successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Triggers configured:" -ForegroundColor Cyan
    Write-Host "  1. At logon - runs cleanup when you log into Windows"
    Write-Host "  2. Daily at 3:00 AM - catches anything missed"
    Write-Host ""
    Write-Host "To run manually anytime:"
    Write-Host "  .\Cleanup-ClaudeDesktop.ps1"
    Write-Host ""
    Write-Host "To view in Task Scheduler:"
    Write-Host "  taskschd.msc > Task Scheduler Library > $TaskName"
    Write-Host ""
    Write-Host "To remove this task:"
    Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false"

} catch {
    Write-Host "ERROR registering task: $_" -ForegroundColor Red
    Write-Host "Make sure you are running PowerShell as Administrator." -ForegroundColor Yellow
    exit 1
}