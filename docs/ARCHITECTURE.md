# SecretPlay — System Architecture

## 1. System Overview

**SecretPlay** is a dedicated, private two-person communication application featuring a dual-layer interface:
- **Surface Layer:** An engaging, fully functional mini-game.
- **Private Layer:** An isolated, authenticated, end-to-end encrypted messaging and WebRTC voice communication suite.

The system is designed strictly for **two authorized Android devices** with **zero permanent message storage**, **zero analytics**, and **zero public discovery**.

```
                   ┌──────────────────────────────────────────────┐
                   │               Android Client A               │
                   │  ┌───────────────┐      ┌─────────────────┐  │
                   │  │ Mini-Game UI  │      │ Private E2EE UI │  │
                   │  └───────────────┘      └────────┬────────┘  │
                   └──────────────────────────────────┼───────────┘
                                                      │
                            ┌─────────────────────────┴────────────────────────┐
                            │ Dual-Mode Hybrid Networking                      │
                            ▼                                                  ▼
                 ┌────────────────────┐                             ┌────────────────────┐
                 │ Cloudflare Mode A  │                             │   Local Mode B     │
                 │ Workers + DO WSS   │                             │ Node.js LAN Server │
                 └──────────┬─────────┘                             └──────────┬─────────┘
                            │                                                  │
                            └─────────────────────────┬────────────────────────┘
                                                      │
                   ┌──────────────────────────────────┼───────────┐
                   │               Android Client B   │           │
                   │  ┌───────────────┐      ┌────────▼────────┐  │
                   │  │ Mini-Game UI  │      │ Private E2EE UI │  │
                   │  └───────────────┘      └─────────────────┘  │
                   └──────────────────────────────────────────────┘
```

---

## 2. Operating Modes

### Mode A: Cloudflare Cloud Mode (Free-Tier Compatible)
- **Edge Worker:** Handles incoming HTTP/WebSocket upgrade requests and validates route parameters.
- **Durable Objects (DO):** Acts as the single-point-of-coordination per authorized pair using WebSocket Hibernation to remain completely within free tier limits.
- **Data Policy:** The DO holds **only ephemeral state in memory**.
  - No message text or ciphertext is saved to SQLite or KV.
  - Relays encrypted packets only when both paired devices maintain an active authenticated WebSocket session.
  - WebRTC signaling (encrypted SDP/ICE) is routed via the DO.
  - Media stream flows P2P via STUN/TURN (never through Workers).

### Mode B: Local Laptop Server (Fully Offline)
- **Node.js + Fastify + WebSockets:** Operates entirely without WAN/Internet access.
- **Connectivity:** Windows Mobile Hotspot or shared local Wi-Fi.
- **Signaling:** Fastify WebSocket relays encrypted messages and WebRTC signaling between phones over LAN IPv4.
- **Zero-Storage Guarantee:** All buffers are volatile in-memory queues dropped immediately upon relay or session termination.
- **Launcher:** Windows `.bat` scripts (`run-local.bat`, `install-local.bat`, `stop-local.bat`).

---

## 3. Cryptographic & Security Guarantees

1. **Identity & Authentication:**
   - Ed25519 for identity keys and digital signatures.
   - Mutual challenge-response authentication on WebSocket connect.
2. **End-to-End Encryption (E2EE):**
   - X25519 ephemeral key exchange.
   - HKDF-SHA256 key derivation.
   - ChaCha20-Poly1305 / AES-256-GCM AEAD encryption.
   - Monotonic counter and random IV for replay defense.
3. **Session-Only Memory Model:**
   - Plaintext messages exist only in Android memory during an active mutual session.
   - App backgrounding, screen lock, or session timeout instantly triggers memory wiping and UI locking.
4. **Encrypted Account Recovery:**
   - Argon2id key derivation from user passphrase.
   - Identity backup encrypted via XChaCha20-Poly1305.
   - Zero chat history or session keys in recovery payloads.
