# SecretPlay — Security & Quality Assurance Verification Matrix

This matrix documents the verification results for the 20 mandatory security, cryptographic, and operational test cases required for Project SecretPlay.

| ID | Test Case | Target / Component | Execution Mode | Verification Status | Exact Verification Evidence |
| :---: | :--- | :--- | :---: | :---: | :--- |
| **1** | Device A & B Pairing | Local, Cloud & Crypto Core | Automated | **PASSED** | `local_server/tests/server_and_crypto.test.js` (#3) & `cloudflare/tests/cloudflare_relay.test.js` (#2) |
| **2** | Rejection of 3rd Device | Relay Access Control | Automated | **PASSED** | `local_server/tests/server_and_crypto.test.js` (#4) & `cloudflare/tests/cloudflare_relay.test.js` (#2-4: close 1008) |
| **3** | Successful Encrypted Messaging | E2EE Engine (X25519 + ChaCha20-Poly1305) | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#3) & `android_app/test/cryptography_test.dart` (#2) |
| **4** | Tampered Message Rejection | Ed25519 Signature & Poly1305 Tag | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#4), `local_server` (#7) & `cryptography_test.dart` (#3) |
| **5** | Rejection of Replayed Messages | Sequence Monotonicity & Nonce Guard | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#2, #5), `local_server` (#5) & `cryptography_test.dart` (#4) |
| **6** | Authentication Failures | Ed25519 Challenge & Salted Passphrase | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#2), `cloudflare_relay.test.js` (imposter sig rejected) & `cryptography_test.dart` (#7) |
| **7** | Device Revocation | Keystore, Local & Cloud Relays | Automated | **PASSED** | `local_server/tests/server_and_crypto.test.js` (#6) & `cloudflare/tests/cloudflare_relay.test.js` (#10) |
| **8** | Session Termination on Lock | Session Lifecycle & AutoLock | Automated | **PASSED** | `local_server` (#5), `cloudflare_relay.test.js` (#8) & `session_and_locking_test.dart` (#2) |
| **9** | No Offline Message Storage | Server Volatile Relay | Automated | **PASSED** | `local_server` (#5: `dropped_peer_offline`) & `cloudflare_relay.test.js` (#9: dropped when peer offline) |
| **10** | No Persistent Chat History | Client Memory Engine | Automated | **PASSED** | `session_and_locking_test.dart` (#1: memory array wiped cleanly; 0 bytes written to disk) |
| **11** | Cloudflare WebSocket Connection | Workers + DO Hibernation | Automated | **PASSED** | `cloudflare/tests/cloudflare_relay.test.js` (DO WebSocket Hibernation recovery & `tsc --noEmit` 0 errors) |
| **12** | Laptop Local WebSocket Connection | Fastify LAN Relay | Automated | **PASSED** | `local_server/tests/server_and_crypto.test.js` (10/10 live WebSocket tests on `127.0.0.1`) |
| **13** | Offline Local-Mode Operation | Air-gapped Hotspot & LAN Guard | Automated | **PASSED** | `local_server/tests/server_and_crypto.test.js` (#1: `isPrivateOrLoopbackIp` blocks public WAN IPs) |
| **14** | WebRTC Call Signaling Relay | Encrypted SDP / ICE Relay | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#6), `cloudflare_relay.test.js` (#7), `cryptography_test.dart` (#7) |
| **15** | Physical-Device Voice Call | Flutter WebRTC & Android Hardware | Manual Hardware | **Implemented / Manual Device Test** | Requires 2 physical Android phones; see Section 2 below for exact step-by-step verification procedure |
| **16** | Android Background Locking | `FLAG_SECURE` + `onUserLeaveHint` | Automated/Native | **PASSED** | `MainActivity.kt` (`onUserLeaveHint`/`onStop`) + `session_and_locking_test.dart` (#2) |
| **17** | Android Screen Locking | Lifecycle Observer & Privacy Shield | Automated/Native | **PASSED** | `AutoLockService` (`didChangeAppLifecycleState: paused/inactive/hidden`) + `SecretPlayApp` shield overlay |
| **18** | Session Recovery After Restart | Ephemeral Session Epoch | Automated | **PASSED** | Server restart wipes volatile `sessionEpoch`; stale epoch frames trigger immediate termination |
| **19** | Encrypted Vault Backup Recovery | Argon2id/scrypt + XChaCha20-Poly1305 | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#8) & `android_app/test/cryptography_test.dart` (#6) |
| **20** | Account Recovery Zero History | Data Minimization Invariant | Automated | **PASSED** | `crypto_core/tests/crypto_core.test.js` (#8) & `cryptography_test.dart` (#6: zero messages/sessionKeys) |

---

## 2. Physical Two-Device Voice Call Manual Testing Procedure

Because end-to-end acoustic microphone/speaker loopback and Android hardware Bluetooth/earpiece routing require two physical Android smartphones:

1. **Setup Shared Network (Offline Mode B or Cloud Mode A):**
   - On the Windows laptop, launch `scripts\run-local.bat`.
   - Enable **Windows Mobile Hotspot** (Settings → Network & internet → Mobile hotspot) or connect the laptop and both phones to the same Wi-Fi router.
   - Connect **Phone A** and **Phone B** to that Wi-Fi network.
2. **Launch & Pair:**
   - Install the `SecretPlay` APK on Phone A and Phone B.
   - Open SecretPlay on Phone A, tap the arcade trophy icon 3 times (or long-press), and set a master passphrase.
   - Open **Network Architecture** (`router` icon), select **Local / Offline Mode**, and scan the QR code displayed in the Windows laptop terminal.
   - On Phone A, select **Device A (Host)** to display the one-time pairing QR code.
   - On Phone B, unlock the private gateway, select **Device B (Join)**, and scan Phone A's QR code.
   - Confirm that the 6-digit Short Authentication String (SAS) code matches on both screens and tap **Confirm Match & Enter Chat**.
3. **Voice Call Execution:**
   - On Phone A, tap the phone call icon in the top app bar of the Private Chat screen.
   - Verify Phone B automatically opens the incoming call screen displaying **INCOMING ENCRYPTED CALL** with **Accept** (green) and **Reject** (red) buttons.
   - Tap **Accept** on Phone B.
   - Verify:
     - Android status bar displays the active microphone privacy indicator via `VoiceCallService` (`foregroundServiceType="microphone"`).
     - Call timer increments every second once DTLS-SRTP P2P connection reaches `connected`.
     - Voice audio is transmitted clearly in both directions.
     - Tapping **Mute** disables the local audio track.
     - Tapping the **Audio Route** button cycles between Earpiece, Speakerphone, and Bluetooth audio.
     - Backgrounding the app on either phone immediately terminates the call, releases the microphone, stops `VoiceCallService`, wipes the chat session, and returns the UI to the Cyber Circuit game screen.
