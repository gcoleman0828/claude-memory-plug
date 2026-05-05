# Cleanup-ClaudeDesktop.ps1
# Reclaims memory and disk space used by Claude Desktop / Cowork on Windows
# SAFE: Preserves all memory, settings, credentials, and session context

param(
    [switch]$Silent,
    [switch]$Force
)

$LogDir  = "$env:APPDATA\Claude\cleanup-logs"
$LogFile = "$LogDir\cleanup-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').log"

if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $line
    if (-not $Silent) {
        switch ($Level) {
            "INFO"    { Write-Host $line -ForegroundColor Cyan }
            "SUCCESS" { Write-Host $line -ForegroundColor Green }
            "WARN"    { Write-Host $line -ForegroundColor Yellow }
            "ERROR"   { Write-Host $line -ForegroundColor Red }
            default   { Write-Host $line }
        }
    }
}

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return "{0:N2} GB" -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return "{0:N2} MB" -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return "{0:N2} KB" -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        (Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
         Measure-Object -Property Length -Sum).Sum
    } catch { 0 }
}

function Remove-SafeFolder {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) {
        Write-Log "Skipping $Label - not found at: $Path" "WARN"
        return 0
    }
    $size = Get-FolderSize -Path $Path
    try {
        Remove-Item -Recurse -Force -Path $Path -ErrorAction Stop
        Write-Log "Removed $Label - freed $(Format-Bytes $size)" "SUCCESS"
        return $size
    } catch {
        Write-Log "Failed to remove $Label : $_" "ERROR"
        return 0
    }
}

Write-Log "===== Claude Desktop Cleanup Started ====="

$ClaudePaths = @()

$PathA = "$env:APPDATA\Claude"
if (Test-Path $PathA) {
    $ClaudePaths += $PathA
    Write-Log "Found EXE install path: $PathA"
}

$MsixBase = "$env:LOCALAPPDATA\Packages"
$MsixMatch = Get-ChildItem -Path $MsixBase -Filter "Claude_*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
if ($MsixMatch) {
    $PathB = "$($MsixMatch.FullName)\LocalCache\Roaming\Claude"
    if (Test-Path $PathB) {
        $ClaudePaths += $PathB
        Write-Log "Found MSIX install path: $PathB"
    }
}

$ClaudeCodeVM = "$env:LOCALAPPDATA\claude-code-vm"

if ($ClaudePaths.Count -eq 0 -and -not (Test-Path $ClaudeCodeVM)) {
    Write-Log "No Claude Desktop installation found. Nothing to clean." "WARN"
    exit 0
}

Write-Log "Calculating current disk usage..."
$totalBefore = 0
foreach ($base in $ClaudePaths) {
    $totalBefore += Get-FolderSize "$base\vm_bundles"
    $totalBefore += Get-FolderSize "$base\Cache"
    $totalBefore += Get-FolderSize "$base\Code Cache"
    $totalBefore += Get-FolderSize "$base\GPUCache"
}
$totalBefore += Get-FolderSize $ClaudeCodeVM
Write-Log "Total reclaimable space: $(Format-Bytes $totalBefore)"

if (-not $Force -and -not $Silent) {
    Write-Host ""
    Write-Host "This will delete Claude VM bundles, cache, and GPU cache." -ForegroundColor Yellow
    Write-Host "Your settings, memory, credentials, and session history will NOT be touched." -ForegroundColor Green
    Write-Host ""
    $confirm = Read-Host "Proceed? (Y/N)"
    if ($confirm -notmatch "^[Yy]") {
        Write-Log "Cleanup cancelled by user." "WARN"
        exit 0
    }
}

$claudeProcs = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($claudeProcs) {
    Write-Log "Claude Desktop is running - attempting graceful close..."
    $claudeProcs | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 3
    $still = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
    if ($still) {
        Write-Log "Force-stopping remaining Claude processes..." "WARN"
        $still | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
}

$svc = Get-Service -Name "CoworkVMService" -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq "Running") {
    Write-Log "Stopping CoworkVMService..."
    try {
        Stop-Service -Name "CoworkVMService" -Force -ErrorAction Stop
        Write-Log "CoworkVMService stopped." "SUCCESS"
    } catch {
        Write-Log "Could not stop CoworkVMService: $_" "WARN"
    }
}

$totalFreed = 0

foreach ($base in $ClaudePaths) {
    Write-Log "--- Cleaning: $base"
    $totalFreed += Remove-SafeFolder "$base\vm_bundles"  "VM Bundle (Cowork)"
    $totalFreed += Remove-SafeFolder "$base\Cache"       "Electron Cache"
    $totalFreed += Remove-SafeFolder "$base\Code Cache"  "V8 Code Cache"
    $totalFreed += Remove-SafeFolder "$base\GPUCache"    "GPU Cache"
}

if (Test-Path $ClaudeCodeVM) {
    $totalFreed += Remove-SafeFolder $ClaudeCodeVM "Claude Code VM folder"
}

$oldLogs = Get-ChildItem -Path $LogDir -Filter "cleanup-*.log" |
           Sort-Object LastWriteTime -Descending |
           Select-Object -Skip 10
foreach ($log in $oldLogs) { Remove-Item $log.FullName -Force -ErrorAction SilentlyContinue }

Write-Log "===== Cleanup Complete ====="
Write-Log "Total space reclaimed: $(Format-Bytes $totalFreed)" "SUCCESS"
Write-Log "Log saved to: $LogFile"

if (-not $Silent) {
    Write-Host ""
    Write-Host "Preserved (untouched):" -ForegroundColor Green
    Write-Host "  %APPDATA%\Claude\claude_desktop_config.json" -ForegroundColor Green
    Write-Host "  %USERPROFILE%\.claude\ (memory, skills, history)" -ForegroundColor Green
    Write-Host "  %USERPROFILE%\.claude.json (auth credentials)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Claude Desktop can now be restarted normally." -ForegroundColor Cyan
}