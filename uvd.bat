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
set "VERSION_FILE=UVD\version_cache.txt"

echo Checking for updates...

REM Smart update check using PowerShell
powershell -NoProfile -ExecutionPolicy Bypass -Command "& { try { $needsUpdate = $false; $needsShortcut = $false; $scriptDir = '%~dp0'; $logoPath = Join-Path $scriptDir '%LOCAL_LOGO_NAME%'; $shortcutPath = Join-Path $env:USERPROFILE 'Desktop\UVD - Universal Video Downloader.lnk'; Write-Host 'Checking script version...' -ForegroundColor Yellow; try { $headers = Invoke-WebRequest -Uri '%SCRIPT_URL%' -Method Head -UseBasicParsing -TimeoutSec 10; $remoteETag = $headers.Headers['ETag'] -replace '""', ''; $remoteSize = $headers.Headers['Content-Length']; $versionFile = Join-Path $scriptDir 'UVD\version_cache.txt'; if (Test-Path '%LOCAL_SCRIPT_NAME%') { $localFile = Get-Item '%LOCAL_SCRIPT_NAME%'; $localSize = $localFile.Length.ToString(); if (Test-Path $versionFile) { $cachedInfo = Get-Content $versionFile -Raw | ConvertFrom-Json; $cachedETag = $cachedInfo.ETag; $cachedSize = $cachedInfo.Size; } else { $cachedETag = ''; $cachedSize = ''; }; if (($remoteETag -ne $cachedETag) -or ($remoteSize -ne $cachedSize) -or ($remoteSize -ne $localSize)) { $needsUpdate = $true; Write-Host 'Script update available!' -ForegroundColor Green } else { Write-Host 'Script is up to date' -ForegroundColor Green } } else { $needsUpdate = $true; Write-Host 'Script not found, will download' -ForegroundColor Yellow } } catch { $needsUpdate = $true; Write-Host 'Cannot check version, will download latest' -ForegroundColor Yellow }; if (-not (Test-Path $shortcutPath)) { $needsShortcut = $true; Write-Host 'Desktop shortcut missing, will create' -ForegroundColor Yellow } elseif (-not (Test-Path $logoPath)) { $needsShortcut = $true; Write-Host 'Logo missing, will download and update shortcut' -ForegroundColor Yellow }; if ($needsUpdate) { Write-Host 'Downloading latest script...' -ForegroundColor Yellow; try { Invoke-WebRequest -Uri '%SCRIPT_URL%' -OutFile '%LOCAL_SCRIPT_NAME%' -UseBasicParsing -TimeoutSec 30; Write-Host 'Script downloaded successfully!' -ForegroundColor Green; $downloadedFile = Get-Item '%LOCAL_SCRIPT_NAME%'; $versionData = @{ ETag = $remoteETag; Size = $remoteSize.ToString(); LastUpdate = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }; $versionData | ConvertTo-Json | Out-File $versionFile -Encoding UTF8; Write-Host 'Version info cached.' -ForegroundColor Green } catch { Write-Host 'Failed to download script: ' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red; Write-Host 'Using existing version if available...' -ForegroundColor Yellow } }; if ($needsShortcut) { Write-Host 'Setting up desktop shortcut...' -ForegroundColor Yellow; try { if (-not (Test-Path $logoPath)) { Write-Host 'Downloading logo...' -ForegroundColor Yellow; Invoke-WebRequest -Uri '%LOGO_URL%' -OutFile $logoPath -UseBasicParsing -TimeoutSec 15; Write-Host 'Logo downloaded.' -ForegroundColor Green } $ws = New-Object -ComObject WScript.Shell; $shortcut = $ws.CreateShortcut($shortcutPath); $shortcut.TargetPath = '%~f0'; $shortcut.WorkingDirectory = '%~dp0'; $shortcut.Description = 'Universal Video Downloader'; if (Test-Path $logoPath) { $shortcut.IconLocation = $logoPath + ',0' }; $shortcut.Save(); Write-Host 'Desktop shortcut created!' -ForegroundColor Green } catch { Write-Host 'Failed to create shortcut: ' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red } }; Write-Host 'Launch complete.' -ForegroundColor Green } catch { Write-Host 'Update check failed: ' -ForegroundColor Red; Write-Host $_.Exception.Message -ForegroundColor Red } }"

REM Check if script file exists after update process
if not exist %LOCAL_SCRIPT_NAME% (
    echo Critical Error: Script file not found after update check.
    echo Please check your internet connection and try again.
    pause
    exit /b 1
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
