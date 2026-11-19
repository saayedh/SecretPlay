# SecretPlay — Private Two-Device Encrypted Communication System

**SecretPlay** is an authenticated, end-to-end encrypted messaging and WebRTC voice calling system engineered exclusively for **two authorized Android devices**. It features a dual-module architecture: a playful, self-contained cyberpunk arcade puzzle game (**Cyber Circuit**) in front of an isolated, session-only E2EE private communication suite.

---

## Key Security & Architectural Features

- **Strictly Two Authorized Devices:** No public registration, no user discovery, no contact synchronization, no third-party analytics, and no advertisements. Enforced by cryptographic key-binding, Ed25519 challenge-response authentication, and 6-digit Short Authentication String (SAS) QR pairing.
- **Zero-Disk Session-Only Messaging:** Plaintext chat messages and ephemeral session keys exist strictly in volatile memory during an active mutual session. No messages are ever persisted to SQLite, flash storage, or offline server queues.
- **Immediate Local Locking & Wiping:** App backgrounding (`onUserLeaveHint` / `onStop` / `AppLifecycleState`), screen lock, or manual lock immediately covers private content (`FLAG_SECURE` + black privacy shield overlay), terminates any active WebRTC voice call, notifies the peer, wipes in-memory messages, and resets navigation to the game screen.
- **Dual-Mode Hybrid Networking:**
  - **Mode A (Cloudflare Cloud):** Free-tier compatible Cloudflare Workers + SQLite-backed Durable Objects with WebSocket Hibernation (`serializeAttachment` / `deserializeAttachment` / `getWebSockets`). Volatile in-memory relay; zero message persistence; zero-cost STUN default with optional config-gated TURN.
  - **Mode B (Windows Laptop Local Server):** Air-gapped, zero-Internet LAN/Hotspot coordination server (`Fastify` + `ws`) enforcing a private-IP-only filter (`isPrivateOrLoopbackIp`) and launched via Windows batch scripts (`run-local.bat`, `install-local.bat`, `stop-local.bat`).
- **P2P WebRTC Encrypted Voice Calling:** Real-time one-to-one voice calls utilizing direct DTLS-SRTP peer-to-peer media encryption over LAN (offline `iceServers: []`) or STUN/optional TURN (cloud), with authenticated E2EE signaling envelopes (`ChaCha20-Poly1305` + `Ed25519`), Android 14 `foregroundServiceType="microphone"` compliance (`VoiceCallService.kt`), audio focus, mute, speaker/earpiece/Bluetooth routing, and ICE reconnection.
- **Encrypted Account Recovery without Chat Recovery:** Offline identity backups protected via `Argon2id` / `PBKDF2` + `XChaCha20-Poly1305` containing zero chat history or session keys.

---

## Monorepo Directory Structure

```
SecretPlay/
├── android_app/                  # Flutter + Native Kotlin Android Application
│   ├── lib/
│   │   ├── app/                 # App root, global navigator & privacy shield overlay
│   │   ├── authentication/      # Salted Passphrase, BiometricPrompt & SAS QR Pairing
│   │   ├── chat/                # In-memory ephemeral chat session & UI
│   │   ├── core/                # Material 3 themes & protocol constants
│   │   ├── cryptography/        # Ed25519, Ephemeral X25519, HKDF, ChaCha20-Poly1305, XChaCha20
│   │   ├── game/                # Cyber Circuit 7x7 match-3 arcade mini-game (15 sectors)
│   │   ├── networking/          # Dual-mode WebSocket client, QR scanner & telemetry
│   │   ├── recovery/            # Encrypted identity recovery vault (zero chat history)
│   │   ├── security/            # Android Keystore wrapper & immediate AutoLockService
│   │   └── voice/               # WebRTC P2P voice service & incoming/outgoing call UI
│   ├── android/                 # Kotlin MainActivity (FLAG_SECURE, AudioManager) & VoiceCallService
│   └── test/                    # Automated Flutter cryptographic & session/locking tests (11 tests)
│
├── cloudflare/                  # Mode A: Cloudflare Workers & Durable Objects
│   ├── src/index.ts             # Worker entrypoint (/, /health, /ws, /revoke, /turn)
│   ├── durable_objects/         # SecretPlaySessionRelay with DO SQLite & WebSocket Hibernation
│   ├── protocols/               # Unified protocol definitions
│   ├── tests/                   # Automated Worker & DO Hibernation test suite
│   └── wrangler.jsonc           # Wrangler configuration (Free-tier compatible)
│
├── local_server/                # Mode B: Offline Windows Laptop Server
│   ├── src/                     # Fastify server, private LAN IP filter & SessionManager
│   ├── protocols/               # Unified protocol definitions
│   ├── tests/                   # Automated Node.js integration & crypto tests (10 tests)
│   └── README.md                # Windows Mobile Hotspot & offline setup guide
│
├── crypto_core/                 # Shared TypeScript Cryptographic & Protocol Core
│   ├── src/                     # Ed25519, X25519, ChaCha20-Poly1305, ReplayGuard, SAS, Vault
│   └── tests/                   # Automated cryptographic & anti-tamper tests (9 tests)
│
├── scripts/                     # Windows Batch Automation
│   ├── install-local.bat        # One-time local server installer & test runner
│   ├── run-local.bat            # Offline local server launcher with QR display
│   ├── stop-local.bat           # Graceful local server shutdown on port 8787
│   ├── deploy-cloudflare.bat    # Cloudflare typecheck, test & deployment script
│   └── build-android.bat        # Flutter dependency, analyzer, test & debug APK builder
│
└── docs/                        # Engineering & Security Documentation
    ├── ARCHITECTURE.md
    ├── THREAT_MODEL.md
    ├── CRYPTOGRAPHY.md
    ├── LOCAL_MODE.md
    ├── CLOUDFLARE_DEPLOYMENT.md
    ├── ANDROID_BUILD.md
    ├── RECOVERY.md
    └── SECURITY_TESTS.md
```

---

## Build, Test, Run & Deploy Commands

### 1. Run Shared `crypto_core` Build & Tests
```powershell
cd crypto_core
npx.cmd tsc
node --test tests/crypto_core.test.js
```

### 2. Run Cloudflare Worker & Durable Object Type-Check & Tests
```powershell
cd cloudflare
npx.cmd tsc --noEmit
npm.cmd test
```

### 3. Run Local Offline Server Build & Tests
```powershell
cd local_server
npx.cmd tsc
node --test tests/server_and_crypto.test.js
```

### 4. Start the Windows Offline Local Server
```cmd
scripts\run-local.bat
```

### 5. Run Flutter Static Analysis & Unit Tests
```powershell
cd android_app
& "D:\flutter\bin\cache\dart-sdk\bin\dart.exe" analyze
& "D:\flutter\bin\flutter.bat" --no-version-check test --no-pub
```

### 6. Build Android Debug APK
```cmd
scripts\build-android.bat
```
*(Requires Android SDK Platform 34 installed under `%LOCALAPPDATA%\Android\Sdk`; see [docs/ANDROID_BUILD.md](docs/ANDROID_BUILD.md)).*
