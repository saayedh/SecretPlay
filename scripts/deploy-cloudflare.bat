@echo off
setlocal enabledelayedexpansion
title SecretPlay - Deploy Cloudflare Workers & Durable Objects

echo =====================================================================
echo         SECRETPLAY CLOUDFLARE DEPLOYMENT AUTOMATION
echo =====================================================================
echo.

where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\node-v24.20.0-win-x64\node.exe" (
        set "PATH=%LOCALAPPDATA%\Microsoft\WinGet\Packages\OpenJS.NodeJS.LTS_Microsoft.Winget.Source_8wekyb3d8bbwe\node-v24.20.0-win-x64;%PATH%"
    ) else (
        echo [ERROR] Node.js is required.
        pause
        exit /b 1
    )
)

set "CF_DIR=%~dp0..\cloudflare"
cd /d "%CF_DIR%"

echo [1/5] Checking Cloudflare Wrangler CLI...
call npx.cmd wrangler --version
if %ERRORLEVEL% NEQ 0 (
    echo [INFO] Installing Cloudflare Wrangler...
    call npm.cmd install
)

echo.
echo [2/5] Validating Configuration and Type-checking...
call npx.cmd tsc --noEmit
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Type checking failed!
    pause
    exit /b 1
)

echo.
echo [3/5] Running Cloudflare Worker & Durable Object automated tests...
call npm.cmd test
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Cloudflare unit tests failed! Aborting deployment.
    pause
    exit /b 1
)

echo.
echo [4/5] Verifying Cloudflare Authentication...
call npx.cmd wrangler whoami
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ACTION REQUIRED] You are not logged into Cloudflare.
    echo Opening browser for secure login with 'wrangler login'...
    call npx.cmd wrangler login
    if %ERRORLEVEL% NEQ 0 (
        echo [ERROR] Cloudflare login failed or cancelled.
        pause
        exit /b 1
    )
)

echo.
echo [5/5] Deploying Worker and Durable Objects (Free Tier Compatible)...
call npx.cmd wrangler deploy

if %ERRORLEVEL% EQU 0 (
    echo.
    echo =====================================================================
    echo [SUCCESS] SecretPlay Cloudflare Relay deployed successfully!
    echo Enter the deployed WSS URL into the SecretPlay Android app settings.
    echo =====================================================================
) else (
    echo [ERROR] Deployment failed. Check the error log above.
)

pause
