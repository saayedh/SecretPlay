# SecretPlay — Windows Laptop Local Offline Coordination Server

This directory contains the offline Node.js + Fastify + WebSocket coordination and WebRTC signaling server for **SecretPlay (Mode B: Local / Offline Mode)**.

Once dependencies are installed via `scripts\install-local.bat`, the local server operates **100% offline with zero Internet access, zero public DNS dependencies, and zero external STUN/TURN calls**.

---

## 1. Quick Start (Windows 10 / 11)

### Step 1: One-Time Dependency Installation (while online)
From the repository root, run:
```cmd
scripts\install-local.bat
```
This installs `node_modules`, compiles the TypeScript sources to `dist/`, and executes the automated verification test suite.

### Step 2: Configure Windows Mobile Hotspot (or Shared Wi-Fi)
- **Option A — Windows 10/11 Mobile Hotspot (Recommended for air-gapped field use):**
  1. Open **Windows Settings** → **Network & internet** → **Mobile hotspot**.
  2. Set **Share my internet connection from** / **Share over** to **Wi-Fi**.
  3. Click **Edit** to set a WPA2/WPA3 Hotspot SSID and Password.
  4. Toggle **Mobile hotspot** to **ON**.
  5. Connect both Android phones to this hotspot Wi-Fi network. Windows typically assigns `192.168.137.1` to the laptop adapter.
  *(Do NOT use deprecated `netsh wlan start hostednetwork` commands, which are removed on modern Windows 10/11 Wi-Fi drivers).*
- **Option B — Shared Local Wi-Fi Router:**
  1. Connect the Windows laptop and both Android phones to the same local Wi-Fi network.
  2. Ensure **AP Isolation / Client Isolation** is disabled on the router so LAN devices can reach each other directly.

### Step 3: Launch the Offline Server
Run:
```cmd
scripts\run-local.bat
```
The server:
1. Detects all non-internal private IPv4 interfaces (`192.168.137.x`, `192.168.x.x`, `10.x.x.x`, `172.16-31.x.x`).
2. Enforces a private-IP-only request filter (`isPrivateOrLoopbackIp`) so connections from public WAN addresses are blocked (`HTTP 403`).
3. Generates a short-lived pairing token (15-minute TTL) and prints a scannable ASCII QR code directly in the console.

### Step 4: Stop the Server
Press `Ctrl+C` in the server console or run:
```cmd
scripts\stop-local.bat
```

---

## 2. Endpoints

| Endpoint | Method | Purpose |
| :--- | :---: | :--- |
| `/health` | `GET` | Returns `{ status: "healthy", mode: "local_offline", e2ee: true, zeroStorage: true }` |
| `/status` | `GET` | Returns pairing status, active session epoch presence, and connected device slots |
| `/pair-info` | `GET` | Returns active LAN IPv4 addresses, WebSocket URL, and rotating 15-minute pairing token |
| `/reset` | `POST` | Wipes in-memory pairing and active sessions for re-pairing |
| `/ws` | `WS` | Unified E2EE protocol relay for pairing, encrypted chat, and encrypted WebRTC signaling |

---

## 3. Security & Data Minimization Invariants

- **Strict Two-Device Cap:** Only `deviceA` and `deviceB` from the completed QR pairing ceremony can authenticate. Any third device is rejected with WebSocket close code `1008`.
- **Zero-Disk Volatile Memory:** All pairing state, session epochs, and relay buffers live strictly in Node.js process RAM. No SQLite database, log file, or message cache is written to disk.
- **No Offline Message Queue:** Messages sent when the peer device is not actively connected to `/ws` are dropped immediately (`status: "dropped_peer_offline"`).
- **Heartbeat & Timeout:** Default heartbeat interval is `5000 ms` with a `20000 ms` session timeout (configurable via `.env`).

---

## 4. Optional Local Coturn TURN Fallback

In 99% of Mobile Hotspot and shared Wi-Fi setups, WebRTC audio connects directly phone-to-phone using host ICE candidates (`iceServers: []`). If a corporate VLAN or multi-subnet LAN blocks direct phone-to-phone UDP while allowing phone-to-laptop traffic, you can run a local Coturn instance on the laptop:
```cmd
turnserver -n --log-file=stdout -a -u secretplay:localpass -r secretplay.local -p 3478 -L 192.168.137.1 -E 192.168.137.1 --no-cli
```
Even when relayed via local TURN, WebRTC media remains end-to-end encrypted between the two phones via **DTLS-SRTP**.
