@echo off
setlocal enabledelayedexpansion
title SecretPlay - Android APK Builder

echo =====================================================================
echo                SECRETPLAY ANDROID APK BUILDER
echo =====================================================================
echo.

set "CI=true"
set "FLUTTER_SUPPRESS_ANALYTICS=true"

REM 1. Check Flutter (auto-detect D:\flutter\bin if not in PATH)
where flutter >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "D:\flutter\bin\flutter.bat" (
        set "FLUTTER_ROOT=D:\flutter"
        set "PATH=D:\flutter\bin;%PATH%"
        echo [INFO] Auto-detected Flutter SDK at D:\flutter\bin
    ) else (
        echo [ERROR] Flutter SDK is not detected in your PATH.
        echo Please ensure Flutter SDK (v3.22+) is installed and in PATH.
        echo Installation Guide: https://docs.flutter.dev/get-started/install/windows
        pause
        exit /b 1
    )
)

echo [OK] Flutter SDK:
call flutter --no-version-check --version
echo.

REM 2. Check Android SDK / Java
if "%ANDROID_HOME%"=="" (
    if exist "%LOCALAPPDATA%\Android\Sdk" (
        set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
        set "ANDROID_SDK_ROOT=%LOCALAPPDATA%\Android\Sdk"
        echo [INFO] Detected ANDROID_HOME at %ANDROID_HOME%
    ) else (
        echo [WARN] ANDROID_HOME environment variable is not explicitly set.
    )
)

if not exist "%ANDROID_HOME%\platforms" (
    echo [WARN] Android SDK 'platforms' folder not found under %ANDROID_HOME%.
    echo        Open Android Studio -^> SDK Manager and install Android 14 (API 34)
    echo        SDK Platform and Android SDK Build-Tools before building the APK.
)

set "APP_DIR=%~dp0..\android_app"
cd /d "%APP_DIR%"

echo [1/4] Fetching Flutter dependencies...
call flutter --no-version-check pub get
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Failed to fetch pub packages.
    pause
    exit /b 1
)

echo.
echo [2/4] Running static code analysis...
call flutter --no-version-check analyze
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Static analysis reported errors. Fix before building.
    pause
    exit /b 1
)

echo.
echo [3/4] Running automated Flutter unit and crypto tests...
call flutter --no-version-check test
if %ERRORLEVEL% NEQ 0 (
    echo [ERROR] Flutter tests failed! Aborting build.
    pause
    exit /b 1
)

echo.
echo [4/4] Building Android debug APK...
call flutter --no-version-check build apk --debug

if %ERRORLEVEL% EQU 0 (
    echo.
    echo =====================================================================
    echo [SUCCESS] SecretPlay Debug APK built successfully!
    echo.
    echo APK Location:
    set "APK_PATH=%APP_DIR%\build\app\outputs\flutter-apk\app-debug.apk"
    if exist "%APK_PATH%" (
        echo  %APK_PATH%
    ) else (
        echo  build\app\outputs\flutter-apk\app-debug.apk
    )
    echo =====================================================================
) else (
    echo.
    echo [ERROR] Flutter build apk failed. Ensure Android SDK Platform 34 and
    echo         Build-Tools are installed via Android Studio SDK Manager.
    exit /b 1
)

pause
