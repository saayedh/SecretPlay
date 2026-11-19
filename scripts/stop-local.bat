@echo off
title SecretPlay - Stop Local Server

echo =====================================================================
echo                 SECRETPLAY STOP LOCAL SERVER
echo =====================================================================
echo.

set PORT=8787
echo Finding process listening on port %PORT%...

for /f "tokens=5" %%a in ('netstat -aon ^| findstr /r ":%PORT% .*LISTENING"') do (
    set PID=%%a
    echo Found process PID: !PID!
    taskkill /F /PID !PID! >nul 2>&1
    if !ERRORLEVEL! EQU 0 (
        echo [OK] SecretPlay server process (!PID!) stopped successfully.
    ) else (
        echo [WARN] Could not terminate PID !PID!. It may have already exited.
    )
)

echo Done.
timeout /t 2 >nul
