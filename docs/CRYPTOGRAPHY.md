# SecretPlay — Cryptography Architecture & Protocols

## 1. Cryptographic Primitive Selection

SecretPlay adheres to the golden rule of applied cryptography: **Never invent proprietary cryptography**. All primitives and compositions rely on vetted, standardized cryptographic implementations (`package:cryptography` in Flutter/Dart and `node:crypto` in `crypto_core/`):

| Component | Standard / Algorithm | Parameters / Implementation Details |
| :--- | :--- | :--- |
| **Long-Term Device Identity (Signing)** | Ed25519 (RFC 8032) | 32-byte identity seed; signs WebSocket auth challenges & E2EE message/signaling envelopes |
| **Long-Term Device Identity (DH)** | X25519 (RFC 7748) | Deterministically derived from identity seed; exported in a 64-byte `[32B Ed25519 \|\| 32B X25519]` public bundle |
| **Ephemeral Key Agreement (E2EE)** | Ephemeral X25519 (ECDH) | Fresh ephemeral X25519 keypair generated per outgoing message & WebRTC signaling frame |
| **Key Derivation** | HKDF-SHA256 (RFC 5869) | Salted with `sessionEpoch`; domain-separated info tags (`SecretPlay-SessionKey-v1`, `SecretPlay-SignalKey-v1`) |
| **Authenticated Encryption (Chat & Signaling)** | ChaCha20-Poly1305 (RFC 8439) | 256-bit symmetric key, 96-bit (12-byte) nonce, 128-bit (16-byte) Poly1305 MAC |
| **Passphrase Verification & KDF** | Argon2id / PBKDF2-HMAC-SHA256 | Salted 16-byte random salt, constant-time verification; zero plaintext passphrases stored |
| **Backup Vault Encryption** | XChaCha20-Poly1305 | Extended 192-bit (24-byte) nonce preventing nonce collision across offline recovery exports |
| **Pairing Verification** | Short Authentication String (SAS) | Truncated HMAC-SHA256 over lexicographically ordered public keys and one-time invitation token (6 digits) |

---

## 2. Key Hierarchy & Derivation Flow

```
             [Sender Ephemeral X25519 Priv]   [Recipient Identity X25519 Pub]
                             │                               │
                             └───────────────┬───────────────┘
                                             │
                                       X25519 ECDH
                                             │
                                             ▼
                                     [Shared Secret]
                                             │
                      HKDF-SHA256 (Salt: sessionEpoch, Info: DomainTag)
                                             │
                                             ▼
                                [256-bit ChaCha20-Poly1305 Key]
                                             │
         Plaintext + 96-bit Nonce ───────────┘
                                             │
                                             ▼
                                 [Ciphertext + 16B AuthTag]
                                             │
                   Ed25519 Sign("${ciphertext}:${iv}:${seq}:${sessionEpoch}")
                                             │
                                             ▼
                                  [Authenticated Envelope]
```

---

## 3. Replay Protection & Envelope Authentication

Every encrypted chat message (`type: "msg"`) and encrypted WebRTC signaling payload (`type: "signal"`) carries:
1. `sessionEpoch`: Random UUID v4 issued by the relay only when both paired devices are simultaneously authenticated. Any frame carrying a stale or mismatched `sessionEpoch` is rejected immediately.
2. `seq`: Strictly monotonic integer counter maintained separately for chat and signaling streams. Any frame with `seq <= lastSeenSeq` is rejected as a replay attack before decryption.
3. `signature`: Ed25519 signature over `${ciphertextBase64}:${ivBase64}:${seq}:${sessionEpoch}` verified against the peer's pinned 32-byte Ed25519 identity public key before ECDH or AEAD decryption is attempted.

WebSocket connection authentication (`type: "auth"`) also uses Ed25519 challenge-response over `${deviceId}:${nonce}:${timestamp}` with a ±60-second clock skew window and a server-side `ReplayGuard` nonce cache.

---

## 4. Short Authentication String (SAS) Pairing

During the two-device QR pairing ceremony:
1. Device A generates a one-time UUID v4 `invitationCode` (5-minute TTL) and renders a QR code containing `(invitationCode, deviceAId, deviceAPubKey, wsUrl)`.
2. Device B scans the QR code, sends `pairing_claim` with `(invitationCode, deviceBId, deviceBPublicKey)`, and the relay returns `pairing_confirm` containing each peer's public key to both devices.
3. Both devices independently compute:
   $$\text{SAS} = \text{HMAC-SHA256}_{\text{invitationCode}}(\text{sort}(\text{Pub}_A, \text{Pub}_B))[0..4] \bmod 10^6$$
4. Both users visually compare the 6-digit SAS code before committing the peer's public key to Android Keystore. If an active relay attempts a Man-in-the-Middle key substitution, the sorted public key pairs differ and the 6-digit SAS codes will not match.

---

## 5. Honest Cryptographic Limitations

- **Independent Audit Status:** While SecretPlay uses established, peer-reviewed cryptographic primitives (`package:cryptography` and `node:crypto`), the composed application itself has not undergone a formal third-party cryptographic audit.
- **Managed Runtime Memory Erasure:** Dart (Flutter) and JavaScript (Node.js/V8) run inside garbage-collected managed runtimes. SecretPlay zeroes temporary `Buffer` instances in `crypto_core` and clears message lists and key references immediately on lock, but guaranteed physical RAM scrubbing of immutable string objects is not possible in managed VM environments.
