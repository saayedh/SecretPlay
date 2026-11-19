@echo off
setlocal enabledelayedexpansion
title SecretPlay - Local Offline Server Launcher

echo =====================================================================
echo              SECRETPLAY LOCAL OFFLINE SERVER LAUNCHER
echo =====================================================================
echo.

REM 1. Detect Node.js
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Node.js is not found in system PATH.
    echo Searching common user install paths...
    if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\node-v24.20.0-win-x64\node.exe" (
        set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\node-v24.20.0-win-x64;%PATH%"
        echo [INFO] Found Node.js in WinGet directory.
    ) else (
        echo [ERROR] Please install Node.js LTS (https://nodejs.org) and re-run.
        pause
        exit /b 1
    )
)

echo [OK] Node.js detected:
node --version
echo.

REM 2. Verify dependencies
set "SERVER_DIR=%~dp0..\local_server"
if not exist "%SERVER_DIR%\node_modules" (
    echo [WARN] Dependencies not found. Running install-local.bat...
    call "%~dp0install-local.bat"
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Failed to install dependencies.
        pause
        exit /b 1
    )
)

REM 3. Verify build output
if not exist "%SERVER_DIR%\dist\index.js" (
    echo [INFO] Building TypeScript project...
    cd /d "%SERVER_DIR%"
    call npx.cmd tsc
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] TypeScript compilation failed.
        pause
        exit /b 1
    )
)

echo ---------------------------------------------------------------------
echo  NETWORK CONNECTION ^& TROUBLESHOOTING INSTRUCTIONS:
echo ---------------------------------------------------------------------
echo  Option 1: Windows Mobile Hotspot (Air-Gapped / Zero Internet)
echo    1. Open Windows Settings -^> Network ^& internet -^> Mobile hotspot.
echo    2. Turn Mobile Hotspot ON (Share over Wi-Fi).
echo    3. Connect both Android devices to this laptop hotspot Wi-Fi.
echo    4. Laptop IP is typically 192.168.137.1 on port 8787.
echo.
echo  Option 2: Shared Local Wi-Fi Router
echo    1. Connect laptop and both Android devices to the SAME Wi-Fi router.
echo    2. Ensure AP Isolation / Client Isolation is disabled on the router.
echo.
echo  Troubleshooting:
echo    - If phones cannot reach port 8787, allow Node.js on Private networks
echo      in Windows Defender Firewall.
echo    - Verify health check from phone browser: http://^<LAN_IP^>:8787/health
echo ---------------------------------------------------------------------
echo.
echo Starting SecretPlay local coordination server...
echo.

cd /d "%SERVER_DIR%"
node dist/index.js

pause
