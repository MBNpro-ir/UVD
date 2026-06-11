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

echo Downloading latest script...

REM Download script directly (always get latest)
curl.exe -L -s -o "%LOCAL_SCRIPT_NAME%" "%SCRIPT_URL%"
if %errorlevel% neq 0 (
    echo Retrying with PowerShell...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_SCRIPT_NAME%' -UseBasicParsing -TimeoutSec 30"
)

REM Check if script file exists after download
if not exist %LOCAL_SCRIPT_NAME% (
    echo Critical Error: Script file not found after download.
    echo Please check your internet connection and try again.
    pause
    exit /b 1
)

echo Script downloaded successfully!

REM Download logo if missing
if not exist "%LOCAL_LOGO_NAME%" (
    echo Downloading logo...
    curl.exe -L -s -o "%LOCAL_LOGO_NAME%" "%LOGO_URL%"
)

REM Create desktop shortcut if missing
if not exist "%USERPROFILE%\Desktop\UVD - Universal Video Downloader.lnk" (
    echo Creating desktop shortcut...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { $ws = New-Object -ComObject WScript.Shell; $shortcut = $ws.CreateShortcut('%USERPROFILE%\Desktop\UVD - Universal Video Downloader.lnk'); $shortcut.TargetPath = '%~f0'; $shortcut.WorkingDirectory = '%~dp0'; $shortcut.Description = 'Universal Video Downloader'; if (Test-Path '%LOCAL_LOGO_NAME%') { $shortcut.IconLocation = '%LOCAL_LOGO_NAME%,0' }; $shortcut.Save(); Write-Host 'Desktop shortcut created!' -ForegroundColor Green } catch { Write-Host 'Failed to create shortcut' -ForegroundColor Yellow } }"
)

REM Launch the PowerShell script
powershell -NoProfile -ExecutionPolicy Bypass -File %LOCAL_SCRIPT_NAME%

echo.
echo Script execution finished.
echo Thank you for using Universal Video Downloader (UVD)!
echo Visit: https://github.com/MBNpro-ir/UVD
echo.
pause
exit
