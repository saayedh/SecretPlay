@echo off
setlocal enabledelayedexpansion
title SecretPlay - Install Local Server Dependencies

echo =====================================================================
echo          SECRETPLAY LOCAL SERVER DEPENDENCY INSTALLER
echo =====================================================================
echo.

where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\node-v24.20.0-win-x64\node.exe" (
        set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\node-v24.20.0-win-x64;%PATH%"
    ) else (
        echo [ERROR] Node.js is required. Please install Node.js LTS first.
        pause
        exit /b 1
    )
)

set "SERVER_DIR=%~dp0..\local_server"
cd /d "%SERVER_DIR%"

echo [1/3] Installing NPM production & development packages...
call npm.cmd install
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] npm install failed. Check your internet connection.
    pause
    exit /b 1
)

echo [2/3] Compiling TypeScript source files...
call npx.cmd tsc
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] TypeScript compilation failed.
    pause
    exit /b 1
)

echo [3/3] Running automated local verification test suite...
call node --test tests/server_and_crypto.test.js
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Verification tests failed!
    pause
    exit /b 1
)

echo.
echo =====================================================================
echo [SUCCESS] Local server installed and verified!
echo You can now run 'run-local.bat' completely offline without internet!
echo =====================================================================
pause
