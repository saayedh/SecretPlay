# SecretPlay — Local Offline Mode Deployment & Operating Guide

## 1. Overview

**SecretPlay Local Mode** allows two Android devices to establish an authenticated, end-to-end encrypted messaging session and direct peer-to-peer WebRTC voice calls **without requiring global Internet access, public DNS, or external servers**.

The Windows laptop acts strictly as a local network coordination relay.

---

## 2. Network Topology & Scenarios

### Option A: Windows Mobile Hotspot (Recommended for true offline field use)
1. On your Windows 10/11 laptop:
   - Open **Settings** → **Network & internet** → **Mobile hotspot**.
   - Set **Share over** to **Wi-Fi**.
   - Edit the Network name (SSID) and Network password.
   - Toggle **Mobile hotspot** to **ON**.
   *(Note: Windows 10/11 allows hotspot sharing even when not connected to an external uplink).*
2. Connect both Android smartphones to the laptop's Mobile Hotspot Wi-Fi network.
3. Both smartphones are automatically assigned local IPv4 addresses (typically in `192.168.137.x/24`).

### Option B: Shared Local Wi-Fi Router
1. Connect the Windows laptop and both Android phones to the same local Wi-Fi router.
2. Ensure **AP Isolation** (Client Isolation) is disabled in your router's administration panel so connected devices can communicate with each other over LAN IPv4.

---

## 3. Server Management on Windows

### Initial Installation (Requires Internet once)
Double-click `scripts/install-local.bat` or run:
```cmd
cd local_server
npm install
npx tsc
node --test tests/server_and_crypto.test.js
```

### Running Offline (Zero Internet required)
Double-click `scripts/run-local.bat` or execute:
```cmd
cd local_server
node dist/index.js
```

The server:
1. Identifies non-internal LAN IPv4 addresses.
2. Binds to `0.0.0.0:8787`.
3. Renders a pairing QR code in the terminal using ASCII blocks.
4. Accepts connections only over WebSocket (`ws://<LAN_IP>:8787/ws`).

### Stopping the Server
Double-click `scripts/stop-local.bat` to gracefully terminate the process listening on port 8787.

---

## 4. Connecting Android Devices

1. Launch SecretPlay on Android Device A.
2. Activate the secret gateway (3 rapid taps or long-press on the arcade trophy).
3. Authenticate using your master passphrase or biometric fingerprint.
4. Navigate to **Network Architecture** (`router icon`) → Select **Local Mode**.
5. Tap **Scan Laptop Terminal QR Code** and scan the QR code displayed in the Windows command prompt.
6. The app automatically connects to `ws://<laptop-ip>:8787/ws`.
7. Repeat the steps on Android Device B.
8. Once both devices connect, the status indicator turns **GREEN (PEER ONLINE • E2EE ACTIVE)**.

---

## 5. Offline WebRTC LAN Voice Calls

In Local Mode:
- The laptop WebSocket relays encrypted WebRTC signaling (`offer`, `answer`, `ice_candidate`).
- The WebRTC engine is configured with `iceServers: []` (empty array).
- Devices discover each other via local LAN host candidates (`typ host`).
- Audio flows directly phone-to-phone over Wi-Fi via DTLS-SRTP.
- No media or audio packets touch the laptop or any cloud service.
