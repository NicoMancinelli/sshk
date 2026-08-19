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

Copy-Item -Path "$ExtSource\*" -Destination $TargetDir -Recurse -Force
Write-Host "[+] Copied sshk files to Kindle" -ForegroundColor Green

# Step 3: Check and auto-patch kterm if present
$KtermSh = Join-Path $KindleDrive "extensions\kterm\bin\kterm.sh"
if (Test-Path $KtermSh) {
    $content = Get-Content $KtermSh -Raw
    if ($content -notmatch "extensions/sshk/bin") {
        Write-Host "[*] Pre-configuring kterm PATH..." -ForegroundColor Blue
        $orig = Join-Path $KindleDrive "extensions\kterm\bin\kterm.sh.orig"
        if (-not (Test-Path $orig)) {
            Copy-Item $KtermSh $orig
        }
        $patched = "#!/bin/sh`nexport PATH=/mnt/us/extensions/sshk/bin:`$PATH`n" + ($content -replace "^#!/bin/sh`r?`n", "")
        [System.IO.File]::WriteAllText($KtermSh, $patched)
        Write-Host "[+] Pre-patched kterm.sh PATH" -ForegroundColor Green
    } else {
        Write-Host "[+] kterm PATH is already configured for sshk" -ForegroundColor Green
    }
} else {
    Write-Host "[i] Note: kterm not found at extensions\kterm. Make sure kterm is installed." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor Green
Write-Host "   Installation Complete! Next Steps:               " -ForegroundColor Green
Write-Host "====================================================" -ForegroundColor Green
Write-Host "1. Safely eject your Kindle."
Write-Host "2. Open KUAL on Kindle -> tap 'sshk: SSH Client' -> '1-Tap Setup'."
Write-Host "3. Open kterm and run 'ssh user@host'!"
Write-Host ""
Pause
