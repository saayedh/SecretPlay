# SecretPlay — Threat Model & Security Posture

## 1. System Adversaries & Trust Boundaries

SecretPlay operates under a strict Zero-Trust Model with respect to both network relays and infrastructure providers.

```
       ┌────────────────────────┐                   ┌────────────────────────┐
       │ Device A (Trusted App) │                   │ Device B (Trusted App) │
       └───────────┬────────────┘                   └───────────┬────────────┘
═══════════════════╪════════════════════════════════════════════╪═══════════════════
 [UNTRUSTED ZONE]  │                                            │
                   ▼                                            ▼
       ┌─────────────────────────────────────────────────────────────────┐
       │ Public Internet / LAN Relays (Cloudflare Workers / Local Node)  │
       │ - Untrusted Network Sniffers                                    │
       │ - Malicious Relay Servers (Compromised Cloudflare or Hotspot)   │
       │ - Active Man-in-the-Middle (MitM) Attackers                     │
       └─────────────────────────────────────────────────────────────────┘
```

---

## 2. Threat Analysis & Mitigations

| Threat | Description | Mitigation in SecretPlay |
| :--- | :--- | :--- |
| **Relay Server Compromise** | Server operator or attacker inspects traffic on Cloudflare or local Node server. | Zero plaintext transmitted. Server receives only ciphertext and ephemeral routing tags. No message history stored on disk or DB. |
| **Unauthorized Device Registration** | An uninvited third party attempts to connect to the session. | Cryptographic two-slot restriction. Server hard-rejects any device ID or key other than the two paired slots. |
| **Replay Attacks** | Attacker captures valid encrypted packets and retransmits them later. | Monotonic sequence counters, ephemeral session epochs, and strict timestamp validation windows (±30s). |
| **Man-in-the-Middle (MitM) during Pairing** | Attacker intercepts initial QR code or injects their own keys. | Interactive Short Authentication String (SAS) verification code displayed side-by-side on both devices. |
| **Physical Device Inspection / Seizure** | Attacker seizes unlocked device or pulls files from flash storage. | Session-only in-memory storage. No SQLite database, no cached images/audio. Immediate app background / screen lock triggers memory wipe. |
| **Cold Boot / Heap Scrape** | Forensic extraction of RAM after device is confiscated. | Sensitive byte arrays are explicitly overwritten with zeroes upon session termination. Plaintext lifetime minimized in Dart/Kotlin runtimes. |
| **Eavesdropping on Voice Calls** | Attacker intercepts WebRTC audio streams. | Media uses DTLS-SRTP peer-to-peer encryption. In local mode, audio packets remain on LAN. In cloud mode, TURN only relays encrypted SRTP packets. |

---

## 3. Honest Limitations & Non-Goals

1. **Compromised Operating System:** If the host Android device is rooted, infected with kernel malware, or running a compromised OS with a hardware screen reader, cryptographic protections inside userland cannot guarantee privacy.
2. **Managed Runtime GC Latency:** While Dart and Kotlin objects are dereferenced and primitive buffers zeroed, garbage-collected virtual machines do not offer synchronous, guaranteed hardware RAM scrubbing for all string allocations.
3. **Traffic Analysis:** While message content is hidden, packet sizes and timing may reveal that two devices are actively communicating unless artificial padding and dummy packets are introduced.
