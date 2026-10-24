$ErrorActionPreference = "Stop"
# install-to-kindle.ps1 - 1-Click Desktop Installer for sshk (Windows PowerShell)

Write-Host ""
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   sshk: Kindle SSH Client - 1-Click Installer      " -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExtSource = Join-Path $ScriptDir "extensions\sshk"

if (-not (Test-Path $ExtSource)) {
    Write-Host "Error: extensions\sshk directory not found in $ScriptDir" -ForegroundColor Red
    Pause
    exit 1
}

# Step 1: Detect Kindle drive
$KindleDrive = $null
$Drives = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -notlike "C:\" }

foreach ($drive in $Drives) {
    $root = $drive.Root
    if ((Test-Path (Join-Path $root "documents")) -or (Test-Path (Join-Path $root "system")) -or (Test-Path (Join-Path $root "extensions"))) {
        $KindleDrive = $root
        break
    }
}

if (-not $KindleDrive) {
    Write-Host "Kindle drive was not automatically detected." -ForegroundColor Yellow
    Write-Host "Please connect your Kindle via USB in drive mode."
    Write-Host ""
    $KindleDrive = Read-Host "Enter Kindle drive letter (e.g. E: or E:\)"
    if (-not (Test-Path $KindleDrive)) {
        Write-Host "Drive '$KindleDrive' does not exist. Aborting." -ForegroundColor Red
        Pause
        exit 1
    }
}

Write-Host "[+] Found Kindle at $KindleDrive" -ForegroundColor Green
Write-Host ""

# Step 2: Copy extensions/sshk
$TargetDir = Join-Path $KindleDrive "extensions\sshk"
Write-Host "[*] Copying sshk to $TargetDir..." -ForegroundColor Blue

if (-not (Test-Path (Join-Path $KindleDrive "extensions"))) {
    New-Item -ItemType Directory -Path (Join-Path $KindleDrive "extensions") -Force | Out-Null
}
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
}

# Overlay release files; preserve user configuration, keys, logs and state.
function Copy-Release($Source, $Destination) {
    if ((Get-Item -LiteralPath $Destination).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw "Refusing to overwrite linked directory: $Destination"
    }
    foreach ($Item in Get-ChildItem -LiteralPath $Source -Force) {
        $Name = $Item.Name
        if ($Name -in @('.ssh', 'state', 'logs', 'tailscaled.state', 'tailscaled.sock') -or
            $Name -like 'kindle_*_key*' -or $Name -like '*.log' -or $Name -like '*.pid') { continue }
        $Dest = Join-Path $Destination $Name
        if ($Name -eq 'hosts.conf' -and (Test-Path -LiteralPath $Dest)) { continue }
        if (Test-Path -LiteralPath $Dest) {
            if ((Get-Item -LiteralPath $Dest -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Refusing to overwrite link: $Dest"
            }
        }
        if ($Item.PSIsContainer) {
            New-Item -ItemType Directory -Path $Dest -Force | Out-Null
            Copy-Release $Item.FullName $Dest
        } else {
            Copy-Item -LiteralPath $Item.FullName -Destination $Dest -Force
        }
    }
}
Copy-Release $ExtSource $TargetDir
Write-Host "[+] Copied release files; existing configuration retained" -ForegroundColor Green
# Device Install / Repair performs kterm integration after USB eject.

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "   Installation Complete! Next Steps:               " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "1. Safely eject your Kindle."
Write-Host "2. Open KUAL on Kindle -> tap 'sshk: SSH Client' -> 'Setup & Maintenance' -> 'Install / Repair'."
Write-Host "3. Open kterm and run 'ssh user@host'!"
Write-Host ""
Pause
