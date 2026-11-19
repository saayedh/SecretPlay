# SecretPlay — Encrypted Identity Recovery Guide

## 1. Zero-History Recovery Philosophy

A core security principle of SecretPlay is **Zero-Disk Chat History**.

Traditional messaging apps offer encrypted backups that archive past conversations, attachments, and media. In high-threat scenarios, those archives become a liability if a backup vault is compromised or coerced.

**SecretPlay strictly separates Identity Recovery from Session Data:**
- **What is recovered:** Your 32-byte identity seed (`Ed25519` signing + `X25519` DH keypair), your device ID, and the pinned public key of your paired peer (flagged with `requiresReverification: true`).
- **What is NEVER recovered:** Past chat messages, call logs, audio recordings, media files, or ephemeral session keys. Once a session ends, its contents cease to exist.

---

## 2. Vault Format

```json
{
  "c": "<Base64 XChaCha20-Poly1305 Ciphertext>",
  "s": "<Base64 16-byte Cryptographic Salt>",
  "n": "<Base64 24-byte (192-bit) XChaCha20 Extended Nonce>",
  "m": "<Base64 16-byte Poly1305 Authentication Tag>"
}
```

The decrypted JSON payload contains strictly:
```json
{
  "version": "1.0",
  "deviceId": "dev-...",
  "privKey": "<Base64 32-byte Identity Seed>",
  "pubKey": "<Base64 64-byte Combined Ed25519+X25519 Public Key>",
  "peerKey": "<Base64 64-byte Peer Public Key>",
  "requiresReverification": true,
  "createdAt": 1731500000000
}
```

---

## 3. Cryptographic Derivation & Encryption Flow

1. **Key Derivation:**
   - Android (`RecoveryCryptoService`): `Argon2id(memory: 16384, parallelism: 2, iterations: 2, hashLength: 32)` with automatic fallback to `PBKDF2-HMAC-SHA256(iterations: 100000, bits: 256)`.
   - Node.js (`crypto_core`): `scrypt(N=16384, r=8, p=1, keyLen=32)`.
2. **Authenticated Encryption:**
   - Android: `XChaCha20-Poly1305` (256-bit key, 192-bit random nonce, 128-bit Poly1305 MAC).
   - Node.js `crypto_core`: `ChaCha20-Poly1305` (256-bit key, 96-bit random nonce, 128-bit Poly1305 MAC) with explicit assertion rejecting any payload containing `messages`, `history`, `chat`, `sessionKeys`, `audio`, or `recordings`.

---

## 4. Operational Recovery Procedure

### A. Exporting an Encrypted Identity Backup
1. In SecretPlay, open **Security Settings** → **Encrypted Account Recovery**.
2. Enter a high-entropy recovery passphrase.
3. Tap **Export Encrypted Vault**.
4. Copy the serialized JSON vault string to secure offline cold storage.

### B. Restoring onto a Replacement Device & Re-Verifying
1. On the replacement device, open **Security Settings** → **Encrypted Account Recovery** (or revoke the old device slot first).
2. Paste the encrypted vault JSON and enter the recovery passphrase.
3. Tap **Restore Identity from Vault**.
4. Because a replacement device must never be silently trusted without peer confirmation (`requiresReverification: true`), complete a fresh QR + 6-digit Short Authentication String (SAS) verification with the second authorized participant.
