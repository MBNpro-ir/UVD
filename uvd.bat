@echo off
title UVD - Universal Video Downloader
color 0A
cls

echo.
echo ========================================
echo    Universal Video Downloader (UVD)
echo            by MBNPRO
echo ========================================
echo.
echo Starting UVD...
echo.

REM Create UVD folder if it doesn't exist
if not exist "UVD" mkdir "UVD"

REM Set URLs and file paths
set "SCRIPT_URL=https://github.com/MBNpro-ir/UVD/raw/refs/heads/master/uvd.ps1"
set "LOCAL_SCRIPT_NAME=UVD\uvd_latest.ps1"
set "LOGO_URL=https://github.com/MBNpro-ir/UVD/raw/refs/heads/master/logo.ico"
set "LOCAL_LOGO_NAME=UVD\logo.ico"

REM Use the script beside this launcher when running from a source checkout.
if exist "%~dp0uvd.ps1" (
    set "LOCAL_SCRIPT_NAME=%~dp0uvd.ps1"
    echo Using local script...
) else (
    echo Downloading latest script...
    curl.exe -fL -s -o "%LOCAL_SCRIPT_NAME%.new" "%SCRIPT_URL%"
    if errorlevel 1 (
        if exist "%LOCAL_SCRIPT_NAME%.new" del /Q "%LOCAL_SCRIPT_NAME%.new"
        echo Retrying with PowerShell...
        powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_SCRIPT_NAME%.new' -UseBasicParsing -TimeoutSec 30"
        if errorlevel 1 if exist "%LOCAL_SCRIPT_NAME%.new" del /Q "%LOCAL_SCRIPT_NAME%.new"
    )
    if exist "%LOCAL_SCRIPT_NAME%.new" move /Y "%LOCAL_SCRIPT_NAME%.new" "%LOCAL_SCRIPT_NAME%" >nul
)

REM Check if script file exists after download
if not exist "%LOCAL_SCRIPT_NAME%" (
    echo Critical Error: Script file not found after download.
    echo Please check your internet connection and try again.
    pause
    exit /b 1
)

echo Script ready!

REM Download logo if missing
if not exist "%LOCAL_LOGO_NAME%" (
    echo Downloading logo...
    curl.exe -L -s -o "%LOCAL_LOGO_NAME%" "%LOGO_URL%"
)

REM Refresh shortcut on every launch so its icon path stays absolute and valid
echo Updating desktop shortcut...
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { $ws = New-Object -ComObject WScript.Shell; $desktop = [Environment]::GetFolderPath('DesktopDirectory'); $shortcut = $ws.CreateShortcut((Join-Path $desktop 'UVD - Universal Video Downloader.lnk')); $shortcut.TargetPath = '%~f0'; $shortcut.WorkingDirectory = '%~dp0'; $shortcut.Description = 'Universal Video Downloader'; $icon = Join-Path '%~dp0' 'UVD\logo.ico'; if (Test-Path -LiteralPath $icon) { $shortcut.IconLocation = $icon + ',0' }; $shortcut.Save(); Write-Host 'Desktop shortcut updated!' -ForegroundColor Green } catch { Write-Host ('Failed to update shortcut: ' + $_.Exception.Message) -ForegroundColor Yellow } }"

REM Launch the PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCAL_SCRIPT_NAME%"

echo.
echo Script execution finished.
echo Thank you for using Universal Video Downloader (UVD)!
echo Visit: https://github.com/MBNpro-ir/UVD
echo.
pause
exit
