# SecretPlay — Cloudflare Workers & Durable Objects Deployment Guide

## 1. Cloudflare Free Tier Architecture

SecretPlay's cloud backend is architected strictly within the constraints of the **Cloudflare Free Plan**:

| Service Component | Free Tier Allowance | SecretPlay Resource Usage Strategy |
| :--- | :--- | :--- |
| **Cloudflare Workers** | 100,000 requests/day | Edge routing and initial WebSocket upgrade handshakes only |
| **Durable Objects (DO)** | Included on Workers Free | 1 DO instance per authorized pair (`primary-pair`) |
| **DO SQLite Storage** | Free tier included | Minimal pair metadata only (`is_paired`, `is_revoked`, `pubkeys`). Zero message persistence. |
| **WebSocket Hibernation** | Zero CPU billing during idle | DO hibernates into memory when no frames are transmitted |
| **WebRTC Media** | Direct P2P via STUN | Free public STUN (`stun.cloudflare.com:3478`). P2P media flows phone-to-phone. |
| **Cloudflare Calls / TURN** | Metered / Paid | **Disabled by default**. Optional configuration with explicit quotas. |

---

## 2. Prerequisites

1. A free Cloudflare account at [https://dash.cloudflare.com](https://dash.cloudflare.com).
2. Node.js LTS installed.
3. Wrangler CLI (installed automatically via `npm install`).

---

## 3. Deployment Steps

### Step 1: Install Dependencies
```cmd
cd cloudflare
npm install
```

### Step 2: Authenticate Wrangler
```cmd
npx wrangler login
```
This opens a secure browser window for Cloudflare OAuth authorization. No credentials or API tokens need to be stored in cleartext.

### Step 3: Validate Configuration & Type-check
```cmd
npx tsc --noEmit
```

### Step 4: Deploy to Cloudflare
```cmd
npx wrangler deploy
```
or run `scripts/deploy-cloudflare.bat`.

Output will display your production endpoint, for example:
```
Deployed secretplay-relay to:
https://secretplay-relay.<your-subdomain>.workers.dev
```

---

## 4. Cost Control & TURN Policy

1. **Zero-Cost STUN Default:** By default, WebRTC media uses standard STUN P2P negotiation. STUN packet exchange consumes zero Cloudflare bandwidth or compute charges.
2. **TURN Safeguard:** Cloudflare Real-Time TURN is disabled unless `ENABLE_CLOUDFLARE_TURN=true` is explicitly provided along with `CF_TURN_KEY_ID` and `CF_TURN_API_TOKEN` via `wrangler secret put`.
3. **Data Minimization:** No messages or voice recordings are ever written to KV, R2, D1, or Durable Object SQLite.
