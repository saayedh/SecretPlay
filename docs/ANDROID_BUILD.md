# SecretPlay — Android Client Build & Compilation Guide

## 1. Prerequisites & Host Environment Status

To build and compile the SecretPlay Android application:
- **Operating System:** Windows 10/11 (Verified on Windows 10/11 x64).
- **Flutter SDK:** Flutter `3.24.5` (Installed at `D:\flutter\bin\flutter.bat`).
- **Dart SDK:** Dart `3.5.4` bundled with Flutter (`D:\flutter\bin\cache\dart-sdk\bin\dart.exe`).
- **Java Development Kit (JDK):** OpenJDK `17.0.21` LTS (Verified in `PATH`).
- **Android Studio:** Installed at `C:\Program Files\Android\Android Studio`.
- **Android SDK (`%LOCALAPPDATA%\Android\Sdk`):**
  - Required packages:
    - `platforms;android-34` (Android 14 / API 34)
    - `build-tools;34.0.0`
    - `platform-tools`
  - **Host Audit Note:** On this workstation, `%LOCALAPPDATA%\Android\Sdk` currently exists as an empty directory because Android Studio's first-run SDK setup wizard has not yet downloaded the Android 34 platform SDK. Running `flutter --no-version-check build apk --debug` reports:
    `[!] No Android SDK found. Try setting the ANDROID_HOME environment variable.`
  - To complete APK assembly on this machine: open **Android Studio** → **SDK Manager**, install **Android 14.0 (API 34) SDK Platform** and **Android SDK Build-Tools**, accept licenses via `D:\flutter\bin\flutter.bat doctor --android-licenses`, and run `scripts\build-android.bat`.

---

## 2. Compilation & Verification Workflow

### Automated Script (Windows)
Run from the repository root:
```cmd
scripts\build-android.bat
```
`scripts\build-android.bat` automatically detects `D:\flutter\bin`, sets `ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk`, resolves dependencies, runs static analysis, runs the 11 Flutter cryptographic & lifecycle unit tests, and invokes `flutter --no-version-check build apk --debug`.

### Manual CLI Commands

1. **Navigate to the Android app directory:**
   ```powershell
   cd "C:\Users\SYeD Hadi Mosavi\.gemini\antigravity\scratch\SecretPlay\android_app"
   ```

2. **Fetch dependencies (offline cache supported):**
   ```powershell
   & "D:\flutter\bin\cache\dart-sdk\bin\dart.exe" pub get --offline
   ```

3. **Run static code analysis (Verified: 0 issues found):**
   ```powershell
   & "D:\flutter\bin\cache\dart-sdk\bin\dart.exe" analyze
   ```

4. **Execute automated cryptographic and lifecycle unit tests (Verified: 11/11 passed):**
   ```powershell
   & "D:\flutter\bin\flutter.bat" --no-version-check test --no-pub
   ```

5. **Build Android Debug APK (once Android SDK Platform 34 is installed):**
   ```powershell
   & "D:\flutter\bin\flutter.bat" --no-version-check build apk --debug
   ```

The compiled APK will be output to:
```
android_app/build/app/outputs/flutter-apk/app-debug.apk
```

---

## 3. Platform Security & Native Integration

### Screen Capture & Recents Protection (`FLAG_SECURE`)
In `android_app/android/app/src/main/kotlin/com/secretplay/app/MainActivity.kt`:
```kotlin
window.setFlags(
    WindowManager.LayoutParams.FLAG_SECURE,
    WindowManager.LayoutParams.FLAG_SECURE
)
```
In addition, `SecretPlayApp` (`lib/app/app.dart`) renders an immediate full-screen black privacy shield overlay whenever `AppLifecycleState` is not `resumed`, and `AutoLockService` wipes the active chat session, closes WebRTC media streams, and pops navigation back to `GameHomeScreen`.

### Android 14 Foreground Microphone Service & Audio Routing
In compliance with Android 14 platform privacy regulations, ongoing WebRTC calls run within `VoiceCallService.kt` with `foregroundServiceType="microphone"`, ensuring the Android status bar microphone privacy indicator is displayed whenever a call is active, and `MainActivity.kt` manages `AudioManager.MODE_IN_COMMUNICATION`, audio focus, speakerphone, earpiece, and Bluetooth SCO routing.
