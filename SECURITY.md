# Security Policy & Vulnerability Reporting

## 1. Zero-Trust Architecture

SecretPlay is built upon a defense-in-depth zero-trust architecture:
- All communications are end-to-end encrypted with **X25519**, **HKDF-SHA256**, and **ChaCha20-Poly1305**.
- Mutual digital signatures utilize **Ed25519**.
- Media streams are strictly encrypted via **DTLS-SRTP**.
- No plaintext, session keys, or message histories are ever logged, cached on disk, or queued on servers.

---

## 2. Scope & Reporting Vulnerabilities

If you identify a security vulnerability or cryptographic flaw in Project SecretPlay, please follow responsible disclosure practices:
- Do NOT open a public issue on GitHub.
- Submit a detailed report including cryptographic proofs or reproduction steps to the designated security team.

---

## 3. Security Invariants Checklist

- [x] Ephemeral message buffers zeroed out upon session termination.
- [x] Android `FLAG_SECURE` enabled to block screenshots and task snapshot leaks.
- [x] Hard limit of exactly two authorized device slots.
- [x] Anti-replay enforcement via strictly monotonic sequence numbers.
- [x] Interactive Short Authentication String (SAS) verification against MitM.
- [x] Offline local server binds without external WAN dependency.
