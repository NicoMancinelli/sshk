@echo off
setlocal enabledelayedexpansion

echo ====================================================
echo    sshk: Kindle SSH Client - 1-Click Installer (Windows)
echo ====================================================
echo.

set SCRIPT_DIR=%~dp0
set EXT_SOURCE=%SCRIPT_DIR%extensions\sshk

if not exist "%EXT_SOURCE%" (
    echo Error: extensions\sshk directory not found.
    pause
    exit /b 1
)

set KINDLE_DRIVE=

:: Check drive letters D through Z for Kindle indicators
for %%D in (D E F G H I J K L M N O P Q R S T U V W X Y Z) do (
    if exist "%%D:\" (
        if exist "%%D:\documents" (
            set KINDLE_DRIVE=%%D:
            goto :found_kindle
        )
        if exist "%%D:\system" (
            set KINDLE_DRIVE=%%D:
            goto :found_kindle
        )
    )
)

:prompt_user
echo Kindle drive was not automatically detected.
echo Please ensure your Kindle is connected via USB in drive mode.
set /p KINDLE_DRIVE="Enter Kindle drive letter (e.g. E: or E:\): "

if not exist "%KINDLE_DRIVE%\" (
    echo Drive %KINDLE_DRIVE% does not exist. Aborting.
    pause
    exit /b 1
)

:found_kindle
echo [+] Found Kindle at %KINDLE_DRIVE%\
echo.

set TARGET_DIR=%KINDLE_DRIVE%\extensions\sshk

if not exist "%KINDLE_DRIVE%\extensions" mkdir "%KINDLE_DRIVE%\extensions"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"

echo [*] Copying sshk files to Kindle...
xcopy /E /I /Y "%EXT_SOURCE%\*" "%TARGET_DIR%\" >nul

echo [+] Copied sshk to %TARGET_DIR%

set KTERM_SH=%KINDLE_DRIVE%\extensions\kterm\bin\kterm.sh
if exist "%KTERM_SH%" (
    findstr /C:"extensions/sshk/bin" "%KTERM_SH%" >nul
    if errorlevel 1 (
        echo [*] Pre-configuring kterm PATH...
        copy "%KTERM_SH%" "%KTERM_SH%.orig" >nul
        (
            echo #!/bin/sh
            echo export PATH=/mnt/us/extensions/sshk/bin:$PATH
            more +1 "%KTERM_SH%.orig"
        ) > "%KTERM_SH%"
        echo [+] Pre-patched kterm.sh PATH
    ) else (
        echo [+] kterm is already configured for sshk
    )
) else (
    echo [i] Note: kterm not found at extensions\kterm. Make sure kterm is installed.
)

echo.
echo ====================================================
echo    Installation Complete! Next Steps:
echo ====================================================
echo 1. Safely eject your Kindle.
echo 2. Open KUAL on Kindle -^> tap 'sshk: SSH Client' -^> '1-Tap Setup'.
echo 3. Open kterm and run 'ssh user@host'!
echo.
pause
